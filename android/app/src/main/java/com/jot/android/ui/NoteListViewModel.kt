package com.jot.android.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.jot.android.model.Note
import com.jot.android.service.FileService
import com.jot.android.service.SyncEngine
import com.jot.android.service.WebDAVClient
import com.jot.android.util.SettingsManager
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.File

/** 编辑器顶部同步状态：空闲 / 同步中 / 已同步（短暂显示后自动回到 Idle） */
enum class EditorSyncState { IDLE, SYNCING, SYNCED }

class NoteListViewModel(application: Application) : AndroidViewModel(application) {
    val notesDir = File(application.filesDir, "notes")
    private val settingsManager = SettingsManager(application)

    private val _notes = MutableStateFlow<List<Note>>(emptyList())
    val notes = _notes.asStateFlow()

    // 列表顶部同步按钮旋转用
    private val _isSyncing = MutableStateFlow(false)
    val isSyncing = _isSyncing.asStateFlow()

    // 编辑器右上角图标状态
    private val _editorSyncState = MutableStateFlow(EditorSyncState.IDLE)
    val editorSyncState = _editorSyncState.asStateFlow()

    // 新建备忘录后通知 UI 自动导航：非 null 时代表有待跳转的新笔记
    private val _pendingNavigateToNote = MutableStateFlow<Note?>(null)
    val pendingNavigateToNote = _pendingNavigateToNote.asStateFlow()

    init {
        if (settingsManager.isLoggedIn) {
            setupStorageAndLoad()
        }
    }

    fun setupStorageAndLoad() {
        if (!notesDir.exists()) notesDir.mkdirs()
        refreshNotes()
    }

    fun refreshNotes() {
        _notes.value = FileService.listMarkdownFiles(notesDir)
    }

    /** 新建备忘录，创建完成后通过 pendingNavigateToNote 通知 UI 跳转编辑器 */
    fun createNote() {
        viewModelScope.launch {
            val file = FileService.createFile(notesDir)
            refreshNotes()
            // 找到刚创建的 Note 对象，发出跳转信号
            val newNote = _notes.value.firstOrNull { it.file.absolutePath == file.absolutePath }
            _pendingNavigateToNote.value = newNote
        }
    }

    /** UI 已消费跳转信号，清空 */
    fun onNavigationHandled() {
        _pendingNavigateToNote.value = null
    }

    fun deleteNote(note: Note) {
        viewModelScope.launch {
            FileService.deleteFile(note.file)
            refreshNotes()
            triggerSync()
        }
    }

    /** 通用同步入口：更新列表顶部旋转状态 */
    fun triggerSync() {
        viewModelScope.launch {
            _isSyncing.value = true
            val client = buildClient()
            try {
                SyncEngine.triggerSync(notesDir, client)
            } catch (_: Exception) {
            } finally {
                _isSyncing.value = false
                refreshNotes()
            }
        }
    }

    /**
     * 编辑器专用同步入口：
     * 转圈（SYNCING）→ 成功后变对勾（SYNCED）→ 2 秒后自动恢复 IDLE
     */
    fun triggerEditorSync() {
        viewModelScope.launch {
            _editorSyncState.value = EditorSyncState.SYNCING
            _isSyncing.value = true
            val client = buildClient()
            try {
                SyncEngine.triggerSync(notesDir, client)
                _editorSyncState.value = EditorSyncState.SYNCED
                delay(2000)
                _editorSyncState.value = EditorSyncState.IDLE
            } catch (_: Exception) {
                _editorSyncState.value = EditorSyncState.IDLE
            } finally {
                _isSyncing.value = false
                refreshNotes()
            }
        }
    }

    private fun buildClient(): WebDAVClient {
        val baseUrl = settingsManager.webdavUrl.let { if (it.endsWith("/")) it else "$it/" }
        return WebDAVClient(
            baseUrl = "${baseUrl}Jot/",
            user = settingsManager.username,
            pass = settingsManager.password
        )
    }
}
