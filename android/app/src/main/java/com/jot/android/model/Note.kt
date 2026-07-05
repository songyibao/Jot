package com.jot.android.model

import com.jot.android.service.SyncEngine
import java.io.File
import java.util.Date

/**
 * 笔记数据模型
 */
data class Note(
    /** 文件名（UUID，不含扩展名） */
    val id: String,
    
    /** 笔记展示标题（从文件内容第一行提取） */
    val title: String,
    
    /** 最后修改时间 */
    val modifiedDate: Date,
    
    /** 文件完整路径 */
    val file: File,
    
    /** 文件大小（字节） */
    val fileSize: Long
)
