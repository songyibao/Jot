package com.jot.android.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.jot.android.model.Note
import com.jot.android.service.FileService
import com.jot.android.util.SettingsManager
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NoteEditorScreen(
    note: Note,
    viewModel: NoteListViewModel,
    onBack: () -> Unit
) {
    var content by remember(note.id) { mutableStateOf(FileService.readFile(note.file)) }
    var hasUnsavedChanges by remember { mutableStateOf(false) }
    val editorSyncState by viewModel.editorSyncState.collectAsState()
    
    val context = LocalContext.current
    val settingsManager = remember { SettingsManager(context) }
    val editorFontSize = settingsManager.editorFontSize

    // ── 响应式内容刷新（优雅解决同步覆盖问题） ─────────────────────────
    // 监听全局同步状态。当同步完成（isSyncing 从 true 变 false）时：
    // 如果当前编辑器没有未保存的修改（用户没在打字），我们安全地重新读取文件内容。
    // 如果云端有新修改同步下来了，界面会自动、无缝地更新，不会闪烁。
    val isSyncing by viewModel.isSyncing.collectAsState()
    LaunchedEffect(isSyncing) {
        if (!isSyncing && !hasUnsavedChanges) {
            val latestDiskContent = FileService.readFile(note.file)
            if (content != latestDiskContent) {
                content = latestDiskContent
            }
        }
    }

    // ── 防抖自动保存 + 触发云端同步 ──────────────────────────────────
    // 用户停止输入 1.5 秒后自动保存并同步
    LaunchedEffect(content) {
        if (!hasUnsavedChanges) return@LaunchedEffect
        delay(1500)
        val onDisk = FileService.readFile(note.file)
        if (content != onDisk) {
            FileService.writeFile(content, note.file)
            viewModel.triggerEditorSync()
        }
    }

    // ── 退到后台时同步（覆盖防抖可能错过的最后一次修改）────────────────
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_PAUSE) {
                // App 被切到后台或用户按 Home 键 → 立刻保存并同步
                val onDisk = FileService.readFile(note.file)
                if (content != onDisk) {
                    FileService.writeFile(content, note.file)
                }
                viewModel.triggerEditorSync()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    // ── 旋转动画（同步中时使用）─────────────────────────────────────
    val infiniteTransition = rememberInfiniteTransition(label = "editor_sync_spin")
    val rotation by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 800, easing = LinearEasing)
        ),
        label = "rotation"
    )

    // ── 动态标题（实时从内容第一行提取）─────────────────────────────
    val displayTitle = remember(content) {
        val firstLine = content.lines().firstOrNull { it.isNotBlank() } ?: ""
        when {
            firstLine.isEmpty() -> "空备忘录"
            firstLine.startsWith("#") -> firstLine.replace(Regex("^#+\\s*"), "").ifEmpty { "空备忘录" }
            else -> firstLine.take(40)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = displayTitle,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                },
                navigationIcon = {
                    IconButton(onClick = {
                        // 返回前先保存未保存的内容
                        val onDisk = FileService.readFile(note.file)
                        if (content != onDisk) {
                            FileService.writeFile(content, note.file)
                            viewModel.triggerEditorSync()
                        }
                        onBack()
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
                actions = {
                    // 右上角同步状态图标
                    when (editorSyncState) {
                        EditorSyncState.SYNCING -> {
                            IconButton(onClick = {}) {
                                Icon(
                                    imageVector = Icons.Default.Refresh,
                                    contentDescription = "同步中",
                                    modifier = Modifier.rotate(rotation),
                                    tint = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.9f)
                                )
                            }
                        }
                        EditorSyncState.SYNCED -> {
                            IconButton(onClick = {}) {
                                Icon(
                                    imageVector = Icons.Default.Check,
                                    contentDescription = "已同步",
                                    tint = Color(0xFFA5D6A7) // 浅绿色对勾，在深绿TopBar上清晰可见
                                )
                            }
                        }
                        EditorSyncState.IDLE -> {
                            // 无图标，保持界面简洁
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                    titleContentColor = MaterialTheme.colorScheme.onPrimary,
                    navigationIconContentColor = MaterialTheme.colorScheme.onPrimary,
                )
            )
        }
    ) { padding ->
        TextField(
            value = content,
            onValueChange = {
                content = it
                hasUnsavedChanges = true
            },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            placeholder = {
                Text(
                    "开始写点什么…",
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.35f)
                )
            },
            textStyle = TextStyle(
                fontSize = editorFontSize.sp,
                lineHeight = (editorFontSize * 1.6f).sp,
                color = MaterialTheme.colorScheme.onSurface
            ),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = MaterialTheme.colorScheme.background,
                unfocusedContainerColor = MaterialTheme.colorScheme.background,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
                cursorColor = MaterialTheme.colorScheme.primary
            )
        )
    }
}
