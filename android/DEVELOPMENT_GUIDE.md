# NativeNotes Android 端开发指导手册

本文档由 macOS 端架构师编写，旨在为 Android 端（借助 Android Studio 内置 Gemini 等 AI 助手）开发提供权威的核心逻辑参考。Android 端必须严格遵循本文档所描述的**数据结构**、**UI 交互逻辑**以及最核心的**三向比对防冲突同步引擎机制**，以确保双端体验的绝对一致性和底层数据的安全互通。

---

## 1. 核心架构与存储范式

本应用采用 **Local-First (本地优先)** 的设计理念。
- **存储介质**：所有笔记以纯文本的 Markdown 格式 (`.md`) 存储在设备的本地持久化目录中。
- **不可变 ID 设计**：文件在被创建时，文件名**必须是一个随机且永远不变的 UUID**（例如 `8F14E45F-E9B0-4D56-A833-25A11F651C8B.md`）。
- **动态标题解析**：界面上展示的笔记“标题”不依赖任何数据库，而是**实时提取该 `.md` 文件内容的第一行（非空行）**。
  - 提取规则：如果第一行以 `# ` 等 Markdown 标题语法开头，需通过正则去掉标记符号（如 `# 新备忘录` 提取为 `新备忘录`）。
  - 如果文件为空，默认展示占位符 `空备忘录`。
- **优势**：无论用户怎么修改标题，底层文件系统中只会发生文本更新，而绝对不会发生文件的“重命名（Rename）”，从而彻底根除了跨平台同步中因重命名导致的严重同步错乱。

---

## 2. 核心同步引擎 (Sync Engine) - 重点

这是整个 App 最核心的模块，必须严格采用如下所述的 **基于 ETag 的三向比对逻辑** 进行开发。

### 2.1 状态记录册 (`.sync_state.json`)
在笔记同级目录下，维护一个 `.sync_state.json` 文件，用来记录上一次成功同步后每个文件的快照信息。
```json
{
  "files": {
    "UUID-1234.md": {
      "eTag": "server_unique_etag_string",
      "localModifiedDate": 1783158037000 
    }
  }
}
```

### 2.2 核心比对与执行逻辑
在每次触发同步时，按照以下矩阵进行状态判定：

1. **拉取全量云端列表 (PROPFIND)**：获取坚果云目录下所有 `.md` 文件的名称和对应的 `eTag`。
2. **拉取全量本地列表 (File System)**：获取本地所有 `.md` 文件的名称及其**最后修改时间戳 (LastModified)**。
3. **针对每个文件计算两个布尔值**：
   - `remoteChanged`: `(state == null) || (state.eTag != remote.eTag)`
   - `localChanged`: `(state == null) || abs(localModifiedDate - state.localModifiedDate) > 1秒`
4. **决策矩阵**：
   - **双端修改 (冲突)** `remoteChanged && localChanged`：
     - **极度重要**：切勿互相覆盖！将本地文件重命名为 `[UUID]_conflict_[时间戳].md`，并将此冲突文件上传。
     - 然后下载云端的文件作为当前主文件。
     - **注意避坑**：冲突文件上传后，**必须立刻将其最新的 eTag 和时间戳也写入记录册**。否则下一次同步时，该冲突文件会被系统认为又是一次新的冲突，导致无限生成 `conflict_conflict_...` 的俄罗斯套娃。
   - **仅远端修改** `remoteChanged`：直接下载远端文件，覆盖本地，并更新记录册。
   - **仅本地修改** `localChanged`：将本地文件 `PUT` 上传至服务器。
     - **注意避坑**：上传完毕后，必须获取服务器为该文件生成的新 `eTag`，并将其与本地时间戳存入记录册。如果 HTTP 响应头未返回 ETag，必须单独发一次 PROPFIND 把最新 ETag 捞回来，**绝对不能在记录册里存空 ETag**，否则下次同步会误判为远端变动。
   - **无变化**：跳过。
5. **处理删除**：
   - 本地没有，但记录册有、远端有：说明本地被用户删除了。执行 `DELETE` 请求删除云端文件。
   - 远端没有，但记录册有、本地有：说明云端被其他设备删除了。执行本地文件删除。

### 2.3 线程安全与并发锁队列
当用户频繁打字或频繁切换后台时，会高频触发 `triggerSync()`。同步操作 (I/O) 较慢，必须通过单例或协程锁（如 Mutex 或 Actor）保护执行：
- 内部维护一个 `isSyncing` 状态。
- 若在正在同步时，外部又请求了同步，**不能简单丢弃请求**，必须将其标记为 `syncRequested = true`。
- 当前班车同步完成后，检查 `syncRequested`。若为 true，重置标志并立刻**再跑一次完整的同步**。
- 这保证了用户停下键盘的最后一次修改，绝对能被可靠地上传至云端。

---

## 3. UI 交互与体验要求 (Compose 层面)

Android 端同样需要追求极致的交互体验。

### 3.1 自动保存与防抖 (Debounce)
- **绝对不需要“保存”按钮**。
- 用户在 EditorScreen 输入文本时，双向绑定 ViewModel 中的 `currentContent`。
- 采用协程的 debounce 机制：监测 `currentContent` 的变化，当用户**停止输入超过 1 秒钟**后：
  1. 将内容原子化地写入本地对应的 `.md` 文件。
  2. 写入成功后，调用 `SyncEngine.triggerSync()` 触发一次后台云端同步。

### 3.2 侧边栏红绿灯状态指示器
在文件列表的每一个 NoteRow 右侧，绘制一个极小的圆形指示灯，动态表示该文件的同步安全状态：
- 🟢 **绿色 (Synced)**：本地时间戳与 `.sync_state.json` 记录一致。
- 🟡 **黄色 (Pending)**：本地时间戳大于记录时间戳，说明刚才写了东西，班车（SyncEngine）还在路上，还没传上去。
- 🔴 **红色 (Conflict)**：文件名包含 `_conflict_`。

*(注：如果采用 `ViewModel + StateFlow / State`，请确保 UI 能够正确响应列表元素的属性变化。由于 Kotlin Data Class 默认 `equals()` 会比较所有字段，因此当时间戳改变导致重新生成 Data Class 实例时，Compose 会自动触发该 Row 的重组，指示灯即可实时变色。)*

### 3.3 全局同步旋转按钮
- 在应用顶部的 TopAppBar 放置一个 `Sync` 图标。
- 当 `SyncEngine.status == Syncing` 时，通过 Compose 的 `infiniteRepeatable` 动画让该图标持续平滑旋转。
- 让用户确切知道后台正在搬运数据。

### 3.4 启动与切屏同步
- 在 `MainActivity` 的生命周期中，监听 App 切换到前台 (`ON_RESUME` 或 Compose 的 `LifecycleEventObserver`)。
- 每次 App 回到前台，强制触发一次 `triggerSync()`，以拉取其他设备（比如 Mac）可能在此期间写入云端的最新修改。

---

## 4. Android 特殊环境注意事项

- **网络库**：强烈建议使用 `OkHttp`。WebDAV 的 `PROPFIND` 和 `MKCOL` 是非标准的 HTTP Method，Retrofit 配置起来可能需要自定义注解，直接用 OkHttp 构建 Request 会非常简单高效。XML 解析用简单的正则即可（不需要引入厚重的 XML 解析库），提取 `<d:href>` 和 `<d:getetag>`。
- **坚果云 URL 拼接**：要求用户在设置里填写账号、应用密码。BaseURL 一般固定为 `https://dav.jianguoyun.com/dav/NativeNotes/`。请求头必须带上 `Authorization: Basic [base64(user:pass)]`。

祝你在 Android 端的开发中一切顺利！按照这份架构指南构建，你将获得一个坚如磐石且体验极佳的原生安卓笔记应用。
