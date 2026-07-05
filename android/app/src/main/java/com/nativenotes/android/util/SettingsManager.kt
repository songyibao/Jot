package com.jot.android.util

import android.content.Context
import android.content.SharedPreferences

class SettingsManager(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("jot_prefs", Context.MODE_PRIVATE)

    var webdavUrl: String
        get() = prefs.getString("webdav_url", "https://dav.jianguoyun.com/dav/") ?: "https://dav.jianguoyun.com/dav/"
        set(value) = prefs.edit().putString("webdav_url", value).apply()

    var username: String
        get() = prefs.getString("username", "") ?: ""
        set(value) = prefs.edit().putString("username", value).apply()

    var password: String
        get() = prefs.getString("password", "") ?: ""
        set(value) = prefs.edit().putString("password", value).apply()

    var isLoggedIn: Boolean
        get() = prefs.getBoolean("is_logged_in", false)
        set(value) = prefs.edit().putBoolean("is_logged_in", value).apply()

    var listFontSize: Float
        get() = prefs.getFloat("list_font_size", 16f)
        set(value) = prefs.edit().putFloat("list_font_size", value).apply()

    var editorFontSize: Float
        get() = prefs.getFloat("editor_font_size", 16f)
        set(value) = prefs.edit().putFloat("editor_font_size", value).apply()

    fun clear() {
        prefs.edit().clear().apply()
    }
}
