package com.jot.android.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jot.android.service.WebDAVClient
import com.jot.android.util.SettingsManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun LoginScreen(
    viewModel: NoteListViewModel,
    onLoginSuccess: () -> Unit
) {
    val context = LocalContext.current
    val settingsManager = remember { SettingsManager(context) }
    val coroutineScope = rememberCoroutineScope()

    var url by remember { mutableStateOf(settingsManager.webdavUrl) }
    var username by remember { mutableStateOf(settingsManager.username) }
    var password by remember { mutableStateOf(settingsManager.password) }
    var isLoading by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(32.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "Welcome to Jot",
                style = MaterialTheme.typography.headlineLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "极简、原生、属于你的备忘录",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
            )
            Spacer(modifier = Modifier.height(48.dp))

            OutlinedTextField(
                value = url,
                onValueChange = { url = it },
                label = { Text("WebDAV 服务器地址") },
                placeholder = { Text("https://dav.jianguoyun.com/dav/") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri)
            )
            Spacer(modifier = Modifier.height(16.dp))

            OutlinedTextField(
                value = username,
                onValueChange = { username = it },
                label = { Text("WebDAV 账号") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email)
            )
            Spacer(modifier = Modifier.height(16.dp))

            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text("应用密码") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password)
            )
            Spacer(modifier = Modifier.height(32.dp))

            if (errorMessage != null) {
                Text(
                    text = errorMessage ?: "",
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(bottom = 16.dp)
                )
            }

            Button(
                onClick = {
                    if (url.isBlank() || username.isBlank() || password.isBlank()) {
                        errorMessage = "请完整填写所有信息"
                        return@Button
                    }
                    isLoading = true
                    errorMessage = null

                    coroutineScope.launch {
                        try {
                            val baseUrl = if (url.endsWith("/")) url else "$url/"
                            val finalUrl = "${baseUrl}Jot/"
                            val client = WebDAVClient(finalUrl, username, password)

                            withContext(Dispatchers.IO) {
                                try {
                                    client.listFiles()
                                } catch (e: Exception) {
                                    // 尝试创建目录
                                    client.mkcol("")
                                    client.listFiles()
                                }
                            }

                            // 验证成功，保存配置
                            settingsManager.webdavUrl = baseUrl
                            settingsManager.username = username
                            settingsManager.password = password
                            settingsManager.isLoggedIn = true

                            // 触发 ViewModel 的初始化逻辑（创建本地文件夹等）
                            viewModel.setupStorageAndLoad()

                            onLoginSuccess()
                        } catch (e: Exception) {
                            errorMessage = "验证失败: ${e.message ?: "未知网络错误"}"
                        } finally {
                            isLoading = false
                        }
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                enabled = !isLoading
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        color = MaterialTheme.colorScheme.onPrimary,
                        strokeWidth = 2.dp
                    )
                } else {
                    Text("连接并登录", fontSize = 16.sp)
                }
            }
        }
    }
}
