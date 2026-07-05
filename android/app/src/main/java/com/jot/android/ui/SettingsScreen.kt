package com.jot.android.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.jot.android.util.SettingsManager

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onBack: () -> Unit,
    onLogout: () -> Unit
) {
    val context = LocalContext.current
    val settingsManager = remember { SettingsManager(context) }

    var url by remember { mutableStateOf(settingsManager.webdavUrl) }
    var user by remember { mutableStateOf(settingsManager.username) }
    var pass by remember { mutableStateOf(settingsManager.password) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("同步设置") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
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
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                text = "坚果云 WebDAV 配置",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.primary
            )

            OutlinedTextField(
                value = url,
                onValueChange = { url = it },
                label = { Text("WebDAV 地址") },
                placeholder = { Text("https://dav.jianguoyun.com/dav/") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            OutlinedTextField(
                value = user,
                onValueChange = { user = it },
                label = { Text("账号（邮箱）") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            OutlinedTextField(
                value = pass,
                onValueChange = { pass = it },
                label = { Text("应用密码") },
                modifier = Modifier.fillMaxWidth(),
                visualTransformation = PasswordVisualTransformation(),
                singleLine = true
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "界面设置",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.primary
            )

            var listFontSize by remember { mutableFloatStateOf(settingsManager.listFontSize) }
            Column {
                Text(text = "列表文字大小: ${listFontSize.toInt()}sp", style = MaterialTheme.typography.bodyMedium)
                Slider(
                    value = listFontSize,
                    onValueChange = { listFontSize = it },
                    valueRange = 12f..30f,
                    steps = 18
                )
            }

            var editorFontSize by remember { mutableFloatStateOf(settingsManager.editorFontSize) }
            Column {
                Text(text = "编辑器文字大小: ${editorFontSize.toInt()}sp", style = MaterialTheme.typography.bodyMedium)
                Slider(
                    value = editorFontSize,
                    onValueChange = { editorFontSize = it },
                    valueRange = 12f..36f,
                    steps = 24
                )
            }

            Spacer(modifier = Modifier.height(4.dp))

            Button(
                onClick = {
                    settingsManager.webdavUrl = url
                    settingsManager.username = user
                    settingsManager.password = pass
                    settingsManager.listFontSize = listFontSize
                    settingsManager.editorFontSize = editorFontSize
                    onBack()
                },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary
                )
            ) {
                Text("保存设置")
            }

            OutlinedButton(
                onClick = {
                    settingsManager.username = ""
                    settingsManager.password = ""
                    settingsManager.isLoggedIn = false
                    onLogout()
                },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.outlinedButtonColors(
                    contentColor = MaterialTheme.colorScheme.error
                )
            ) {
                Text("退出登录")
            }

            // 坚果云使用说明
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))

            Text(
                text = "💡 使用说明",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
            )
            Text(
                text = "1. 前往坚果云网页版 → 账号信息 → 安全选项\n" +
                        "2. 第三方应用管理中新增应用，获取「应用密码」\n" +
                        "3. WebDAV 地址固定填写：https://dav.jianguoyun.com/dav/",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                lineHeight = MaterialTheme.typography.bodySmall.fontSize * 1.6f
            )
        }
    }
}
