# Jot - 极简原生备忘录

> **Jot** 是一款为追求极简、安全与原生体验的用户打造的跨平台纯文本备忘录应用。
> 它放弃了复杂的排版、文件夹和私有云后端，**专注于记录本身**，并通过标准的 **WebDAV** 协议在 macOS 和 Android 之间实现无缝的跨端同步。

![Jot Logo](assets/logo.png)

## ✨ 核心理念与特性

- 🪶 **极简纯文本**：没有繁杂的 Markdown 渲染，没有任何花哨的格式干扰，只提供最纯粹的文本编辑体验。
- ⚡️ **极致原生体验**：
  - **macOS 端**：基于最新的 SwiftUI 架构，完美融入 macOS 设计语言，启动迅速，资源占用极低。
  - **Android 端**：采用最新的 Kotlin + Jetpack Compose 构建，支持 Material 3 动态取色机制。
- ☁️ **数据完全由你掌控**：Jot 没有自己的后台服务器。所有的笔记都通过标准的 WebDAV 协议（如坚果云）直接同步到你自己的网盘里。你的数据，永远属于你。
- 🔄 **优雅的无缝同步**：彻底抛弃手动同步的烦恼。无论是应用前后台切换，还是点开某篇笔记，应用都能通过响应式数据流（Reactive Data Flow）实现云端改动的静默拉取和 UI 顺滑更新，真正做到零感知的多端协作。

## 📂 仓库结构 (Monorepo)

本项目采用 Monorepo（单体仓库）的形式管理，确保多端代码的业务逻辑在迭代中保持高度一致。

```text
.
├── macOS/              # macOS 端原生代码 (Swift / SwiftUI)
├── Android/            # Android 端原生代码 (Kotlin / Jetpack Compose)
├── assets/             # 共用的设计资源文件
└── README.md
```

## 🛠 技术栈

### macOS 端
* **开发语言**: Swift 6
* **UI 框架**: SwiftUI (macOS 15.0+)
* **依赖管理**: Swift Package Manager (SPM)
* **核心机制**: `@Observable` 状态管理，原生文件监听机制 (DispatchSource)，并发网络请求 (Swift Concurrency)

### Android 端
* **开发语言**: Kotlin 2.1+
* **UI 框架**: Jetpack Compose & Material 3
* **架构模式**: MVVM + Hilt (依赖注入) + Kotlin Coroutines & StateFlow
* **构建系统**: Gradle KTS + Version Catalogs

## 🚀 如何使用

1. **准备 WebDAV 账号**
   - 推荐使用**坚果云**。前往坚果云官网 → 账户信息 → 安全选项，创建一个“第三方应用密码”。
2. **首次打开应用**
   - 无论是在 macOS 还是 Android 端，首次打开都必须配置 WebDAV 服务（坚果云的地址通常填 `https://dav.jianguoyun.com/dav/`）。
   - 输入你的账号（邮箱）和刚刚申请的应用密码。
   - 点击登录，应用会自动校验连通性并在你的云端创建 `Jot` 专属同步目录。
3. **开始记录**
   - 验证通过后，即可享受随时随地的极简记录体验。所有改动将自动在两端双向同步。

## 🔒 隐私与安全

Jot **不会**收集你的任何个人信息、使用习惯或笔记内容。所有的密码仅保存在本地设备的最安全区域（macOS 的 Keychain 和 Android 的 Encrypted SharedPreferences/沙盒内）。所有的网络请求均直接发生在你的设备和你的 WebDAV 服务商之间。

---
*Made with ❤️ for minimalist note-taking.*
