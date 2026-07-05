package com.jot.android.service

import com.jot.android.model.Note
import java.io.File
import java.util.Date
import java.util.UUID

/**
 * 文件系统操作服务
 * 负责 .md 文件的增删改查和标题解析
 */
object FileService {

    /**
     * 列举目录下所有 .md 文件，按修改时间降序排列
     * 需传入 syncStateMap 以计算每条笔记的同步状态
     */
    fun listMarkdownFiles(directory: File, syncStateMap: Map<String, FileSyncState> = emptyMap()): List<Note> {
        if (!directory.exists() || !directory.isDirectory) return emptyList()

        return directory.listFiles { file -> file.extension.lowercase() == "md" && !file.name.startsWith(".") }
            ?.map { file ->
                val title = extractTitle(file)
                val localModDate = file.lastModified()
                val syncState = run {
                    if (file.name.contains("_conflict_")) return@run SyncEngine.NoteSyncState.CONFLICT
                    val state = syncStateMap[file.name]
                        ?: return@run SyncEngine.NoteSyncState.PENDING
                    val diff = kotlin.math.abs(localModDate - state.localModifiedDate)
                    if (diff > 1500) SyncEngine.NoteSyncState.PENDING else SyncEngine.NoteSyncState.SYNCED
                }
                Note(
                    id = file.nameWithoutExtension,
                    title = title,
                    modifiedDate = Date(localModDate),
                    file = file,
                    fileSize = file.length(),
                    syncState = syncState
                )
            }
            ?.sortedByDescending { it.modifiedDate }
            ?: emptyList()
    }

    /**
     * 从文件内容第一行提取标题
     */
    fun extractTitle(file: File): String {
        return try {
            file.bufferedReader().use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    val trimmed = line?.trim() ?: ""
                    if (trimmed.isNotEmpty()) {
                        if (trimmed.startsWith("#")) {
                            val title = trimmed.replace(Regex("^#+\\s*"), "")
                            return if (title.isEmpty()) "空备忘录" else title
                        }
                        return trimmed
                    }
                }
                "空备忘录"
            }
        } catch (e: Exception) {
            "空备忘录"
        }
    }

    /**
     * 读取文件内容
     */
    fun readFile(file: File): String {
        return try {
            file.readText()
        } catch (e: Exception) {
            ""
        }
    }

    /**
     * 写入文件内容
     */
    fun writeFile(content: String, file: File) {
        file.writeText(content)
    }

    /**
     * 在指定目录创建新的 .md 文件（使用 UUID 命名）
     */
    fun createFile(directory: File): File {
        if (!directory.exists()) directory.mkdirs()
        val fileName = "${UUID.randomUUID().toString().uppercase()}.md"
        val file = File(directory, fileName)
        file.writeText("# 新备忘录\n")
        return file
    }

    /**
     * 删除文件
     */
    fun deleteFile(file: File) {
        if (file.exists()) {
            file.delete()
        }
    }
}
