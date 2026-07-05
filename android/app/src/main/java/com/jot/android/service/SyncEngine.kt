package com.jot.android.service

import android.util.Log
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.abs

data class FileSyncState(
    val eTag: String,
    val localModifiedDate: Long
)

data class SyncState(
    val files: MutableMap<String, FileSyncState> = mutableMapOf()
)

enum class SyncStatus {
    IDLE, SYNCING, SUCCESS, ERROR
}

object SyncEngine {
    private const val TAG = "SyncEngine"
    private val gson = Gson()
    private val mutex = Mutex()
    private var isSyncingInternal = false
    private var syncRequested = false

    private val _status = MutableStateFlow(SyncStatus.IDLE)
    val status = _status.asStateFlow()

    private val _lastErrorMessage = MutableStateFlow<String?>(null)
    val lastErrorMessage = _lastErrorMessage.asStateFlow()

    private fun parseWebDAVDate(dateString: String): Long {
        return try {
            val format = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss z", Locale.US)
            format.parse(dateString)?.time ?: System.currentTimeMillis()
        } catch (e: Exception) {
            System.currentTimeMillis()
        }
    }

    private fun getSyncStateFile(directory: File): File {
        return File(directory, ".sync_state.json")
    }

    // 供 ViewModel 查询当前 syncState 以驱动 UI 指示灯
    fun loadSyncStatePublic(directory: File): SyncState = loadSyncState(directory)

    // 使用 TypeToken 精确指定泛型类型，解决 Gson 类型擦除导致 FileSyncState
    // 被反序列化为 LinkedTreeMap 而非正确类型的致命 Bug。
    // 直接存储 Map 而非 SyncState 包装类，进一步规避嵌套泛型擦除问题。
    private val syncStateType = object : TypeToken<MutableMap<String, FileSyncState>>() {}.type

    private fun loadSyncState(directory: File): SyncState {
        val file = getSyncStateFile(directory)
        if (!file.exists()) return SyncState()
        return try {
            val map: MutableMap<String, FileSyncState>? = gson.fromJson(file.readText(), syncStateType)
            SyncState(map ?: mutableMapOf())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load sync state: ${e.message}", e)
            SyncState()
        }
    }

    private fun saveSyncState(directory: File, state: SyncState) {
        val file = getSyncStateFile(directory)
        try {
            // 直接序列化 Map 本身（非包装类），读写格式保持一致
            file.writeText(gson.toJson(state.files, syncStateType))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save sync state: ${e.message}", e)
        }
    }

    enum class NoteSyncState {
        SYNCED, PENDING, CONFLICT
    }

    fun getFileSyncState(file: File, syncState: SyncState): NoteSyncState {
        if (file.name.contains("_conflict_")) return NoteSyncState.CONFLICT
        val state = syncState.files[file.name] ?: return NoteSyncState.PENDING
        
        val diff = abs(file.lastModified() - state.localModifiedDate)
        return if (diff > 1500) NoteSyncState.PENDING else NoteSyncState.SYNCED
    }

    suspend fun triggerSync(directory: File, client: WebDAVClient) {
        mutex.withLock {
            if (isSyncingInternal) {
                syncRequested = true
                return
            }
            isSyncingInternal = true
        }

        try {
            do {
                mutex.withLock { syncRequested = false }
                _status.value = SyncStatus.SYNCING
                performSync(directory, client)
            } while (syncRequested)
            _status.value = SyncStatus.SUCCESS
        } catch (e: Exception) {
            Log.e(TAG, "Sync failed", e)
            _status.value = SyncStatus.ERROR
            _lastErrorMessage.value = e.message
        } finally {
            mutex.withLock { isSyncingInternal = false }
        }
    }

    private suspend fun performSync(directory: File, client: WebDAVClient) {
        val syncState = loadSyncState(directory)
        
        val remoteFilesList = try {
            client.listFiles()
        } catch (e: Exception) {
            if (e is WebDAVException && e.code == 404) {
                client.mkcol("")
                client.listFiles()
            } else {
                throw e
            }
        }
        val remoteFiles = remoteFilesList.associateBy { it.name }

        val localFiles = (directory.listFiles { f -> f.extension == "md" && !f.name.startsWith(".") } ?: emptyArray())
            .associateBy { it.name }
            
        val localModifiedDates = localFiles.mapValues { it.value.lastModified() }

        val newFilesState = syncState.files.toMutableMap()

        remoteFiles.forEach { (name, remote) ->
            val localFile = localFiles[name]
            val state = syncState.files[name]
            
            val remoteChanged = state == null || state.eTag != remote.eTag
            val localModDate = localModifiedDates[name] ?: localFile?.lastModified() ?: 0L
            val localChanged = localFile != null && (state == null || abs(localModDate - state.localModifiedDate) > 1500)

            if (localFile != null) {
                if (remoteChanged && localChanged) {
                    // Conflict
                    val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
                    val conflictName = name.replace(".md", "_conflict_$timestamp.md")
                    val conflictFile = File(directory, conflictName)
                    localFile.renameTo(conflictFile)

                    var conflictETag = client.upload(conflictName, conflictFile.readBytes())
                    if (conflictETag == null) {
                        conflictETag = client.listFiles(conflictName).firstOrNull()?.eTag
                    }
                    if (conflictETag != null) {
                        newFilesState[conflictName] = FileSyncState(conflictETag, conflictFile.lastModified())
                    }

                    val remoteData = client.download(remote.href)
                    localFile.writeBytes(remoteData)
                    localFile.setLastModified(parseWebDAVDate(remote.lastModifiedStr))
                    newFilesState[name] = FileSyncState(remote.eTag, localFile.lastModified())
                } else if (remoteChanged) {
                    // Remote updated
                    val remoteData = client.download(remote.href)
                    localFile.writeBytes(remoteData)
                    localFile.setLastModified(parseWebDAVDate(remote.lastModifiedStr))
                    newFilesState[name] = FileSyncState(remote.eTag, localFile.lastModified())
                } else if (localChanged) {
                    // Local updated
                    var eTag = client.upload(name, localFile.readBytes())
                    if (eTag == null) {
                        eTag = client.listFiles(name).firstOrNull()?.eTag
                    }
                    val finalETag = eTag
                    if (finalETag != null) {
                        newFilesState[name] = FileSyncState(finalETag, localModDate)
                    }
                } else {
                    if (state != null) {
                        newFilesState[name] = state
                    }
                }
            } else {
                if (state != null) {
                    // Deleted locally
                    client.delete(remote.href)
                    newFilesState.remove(name)
                } else {
                    // New remote
                    val remoteData = client.download(remote.href)
                    val newLocalFile = File(directory, name)
                    newLocalFile.writeBytes(remoteData)
                    newLocalFile.setLastModified(parseWebDAVDate(remote.lastModifiedStr))
                    newFilesState[name] = FileSyncState(remote.eTag, newLocalFile.lastModified())
                }
            }
        }

        localFiles.forEach { (name, localFile) ->
            if (remoteFiles.containsKey(name)) return@forEach
            
            val localModDate = localModifiedDates[name] ?: localFile.lastModified()
            val state = syncState.files[name]
            if (state != null) {
                // Deleted remotely
                localFile.delete()
                newFilesState.remove(name)
            } else {
                // New locally
                var eTag: String? = client.upload(name, localFile.readBytes())
                if (eTag == null) {
                    eTag = client.listFiles(name).firstOrNull()?.eTag
                }
                val finalETag = eTag
                if (finalETag != null) {
                    newFilesState[name] = FileSyncState(finalETag, localModDate)
                }
            }
        }

        // Cleanup state for non-existent files
        val iterator = newFilesState.keys.iterator()
        while (iterator.hasNext()) {
            val name = iterator.next()
            if (!localFiles.containsKey(name) && !remoteFiles.containsKey(name)) {
                iterator.remove()
            }
        }

        saveSyncState(directory, SyncState(newFilesState))
    }
}
