package com.jot.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.jot.android.model.Note
import com.jot.android.ui.NoteEditorScreen
import com.jot.android.ui.NoteListScreen
import com.jot.android.ui.NoteListViewModel
import com.jot.android.ui.SettingsScreen
import com.jot.android.ui.theme.JotTheme

class MainActivity : ComponentActivity() {
    private val viewModel: NoteListViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            JotTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    val context = androidx.compose.ui.platform.LocalContext.current
                    val settingsManager = remember { com.jot.android.util.SettingsManager(context) }
                    var isLoggedIn by remember { mutableStateOf(settingsManager.isLoggedIn) }

                    if (!isLoggedIn) {
                        com.jot.android.ui.LoginScreen(
                            viewModel = viewModel,
                            onLoginSuccess = { isLoggedIn = true }
                        )
                    } else {
                        var selectedNote by remember { mutableStateOf<Note?>(null) }
                        var isSettingsOpen by remember { mutableStateOf(false) }

                        // ─── 应用启动 / 从后台回前台时触发同步 ─────────────────────
                        // ON_RESUME 在两种场景下都会触发：
                        //   1. 冷启动 Activity 时（第一次 onCreate 后紧接着 onResume）
                        //   2. App 从后台切回前台时（用户按 Home 再回来）
                        val lifecycleOwner = LocalLifecycleOwner.current
                        DisposableEffect(lifecycleOwner) {
                            val observer = LifecycleEventObserver { _, event ->
                                if (event == Lifecycle.Event.ON_RESUME) {
                                    viewModel.triggerSync()
                                }
                            }
                            lifecycleOwner.lifecycle.addObserver(observer)
                            onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
                        }

                        // ─── 关键修复：用 lastKnownNote 保住退出动画时的笔记引用 ───────
                        // 当 selectedNote 变为 null（返回操作）时，AnimatedContent 正处于
                        // 从 index=1 → index=0 的退出动画阶段。如果此时 selectedNote 为 null，
                        // 则退出帧中 selectedNote?.let{} 渲染为空，造成"缩放闪现"的怪异效果。
                        // lastKnownNote 在 selectedNote 变为非 null 时跟踪更新，变为 null 时保持，
                        // 让退出动画期间仍有完整的 NoteEditorScreen 可以渲染。
                        var lastKnownNote by remember { mutableStateOf<Note?>(null) }
                        LaunchedEffect(selectedNote) {
                            if (selectedNote != null) lastKnownNote = selectedNote
                        }

                        // ─── 新建备忘录后自动跳转到编辑器 ───────────────────────────
                        val pendingNote by viewModel.pendingNavigateToNote.collectAsState()
                        LaunchedEffect(pendingNote) {
                            pendingNote?.let { note ->
                                selectedNote = note
                                lastKnownNote = note
                                viewModel.onNavigationHandled()
                            }
                        }

                        // ─── 系统返回手势拦截 ────────────────────────────────────────
                        BackHandler(enabled = isSettingsOpen || selectedNote != null) {
                            when {
                                isSettingsOpen -> isSettingsOpen = false
                                selectedNote != null -> {
                                    selectedNote = null
                                    viewModel.refreshNotes()
                                }
                            }
                        }

                        // ─── 页面索引：决定动画方向 ──────────────────────────────────
                        val screenIndex = when {
                            isSettingsOpen -> 2
                            selectedNote != null -> 1
                            else -> 0
                        }

                        AnimatedContent(
                            targetState = screenIndex,
                            transitionSpec = {
                                if (targetState > initialState) {
                                    // 向前：右滑入 + 左滑出
                                    slideInHorizontally { it } togetherWith slideOutHorizontally { -it }
                                } else {
                                    // 向后：左滑入 + 右滑出
                                    slideInHorizontally { -it } togetherWith slideOutHorizontally { it }
                                }
                            },
                            label = "screen_transition"
                        ) { target ->
                            when (target) {
                                2 -> SettingsScreen(
                                    onBack = { isSettingsOpen = false },
                                    onLogout = {
                                        isSettingsOpen = false
                                        selectedNote = null
                                        isLoggedIn = false
                                    }
                                )
                                1 -> {
                                    // 使用 lastKnownNote 而非 selectedNote，
                                    // 保证退出动画阶段（selectedNote 已经是 null）依然能渲染完整界面
                                    val noteToDisplay = lastKnownNote
                                    if (noteToDisplay != null) {
                                        NoteEditorScreen(
                                            note = noteToDisplay,
                                            viewModel = viewModel,
                                            onBack = {
                                                selectedNote = null
                                                viewModel.refreshNotes()
                                            }
                                        )
                                    }
                                }
                                else -> NoteListScreen(
                                    viewModel = viewModel,
                                    onNoteClick = { note -> selectedNote = note },
                                    onSettingsClick = { isSettingsOpen = true }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
