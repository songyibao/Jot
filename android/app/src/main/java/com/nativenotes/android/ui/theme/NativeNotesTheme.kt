package com.jot.android.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// 主色调：深绿 + 暖白的组合，类似高端笔记软件的气质
private val primaryColor = Color(0xFF2D6A4F)        // 深绿（主题色）
private val primaryContainerColor = Color(0xFFD8F3DC) // 浅绿（按钮容器）
private val secondaryColor = Color(0xFF52B788)       // 中绿（次要元素）
private val surfaceColor = Color(0xFFF8FAF8)         // 微绿白（背景）
private val onSurfaceColor = Color(0xFF1B1C1B)       // 近黑色（文字）

private val LightColorScheme = lightColorScheme(
    primary = primaryColor,
    onPrimary = Color.White,
    primaryContainer = primaryContainerColor,
    onPrimaryContainer = Color(0xFF0D3B22),
    secondary = secondaryColor,
    onSecondary = Color.White,
    background = surfaceColor,
    surface = Color.White,
    onSurface = onSurfaceColor,
    onBackground = onSurfaceColor,
    outline = Color(0xFFBDBDBD),
    outlineVariant = Color(0xFFE8EDE8),
)

@Composable
fun JotTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = LightColorScheme,
        content = content
    )
}
