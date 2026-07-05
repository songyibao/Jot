package com.jot.android.service

import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.Base64
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

data class WebDAVFile(
    val name: String,
    val href: String,
    val eTag: String,
    val isDirectory: Boolean
)

class WebDAVClient(
    private val baseUrl: String,
    private val user: String,
    private val pass: String
) {
    private val client = OkHttpClient()
    private val auth = "Basic " + Base64.getEncoder().encodeToString("$user:$pass".toByteArray())
    private val normalizedBaseUrl: String = if (baseUrl.endsWith("/")) baseUrl else "$baseUrl/"

    private fun buildUrl(path: String): HttpUrl {
        return if (path.startsWith("http")) {
            path.toHttpUrlOrNull() ?: throw IOException("Invalid absolute URL: $path")
        } else if (path.startsWith("/")) {
            val base = normalizedBaseUrl.toHttpUrlOrNull() ?: throw IOException("Invalid base URL")
            val hostStr = "${base.scheme}://${base.host}${if (base.port != 80 && base.port != 443) ":${base.port}" else ""}"
            (hostStr + path).toHttpUrlOrNull() ?: throw IOException("Invalid path concatenation: $hostStr$path")
        } else {
            (normalizedBaseUrl + path).toHttpUrlOrNull() ?: throw IOException("Invalid relative URL: $normalizedBaseUrl$path")
        }
    }

    suspend fun listFiles(path: String = ""): List<WebDAVFile> = suspendCoroutine { continuation ->
        val url = buildUrl(path)
        val requestBody = """
            <?xml version="1.0" encoding="utf-8" ?>
            <d:propfind xmlns:d="DAV:">
                <d:prop>
                    <d:getetag/>
                    <d:resourcetype/>
                </d:prop>
            </d:propfind>
        """.trimIndent().toRequestBody("text/xml".toMediaType())

        val request = Request.Builder()
            .url(url)
            .addHeader("Authorization", auth)
            .addHeader("Depth", "1")
            .method("PROPFIND", requestBody)
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                continuation.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                if (!response.isSuccessful) {
                    continuation.resumeWithException(IOException("Unexpected code $response"))
                    return
                }
                val body = response.body?.string() ?: ""
                val files = parsePropfindResponse(body)
                val filteredFiles = files.filter { it.name.isNotEmpty() && !it.isDirectory }
                continuation.resume(filteredFiles)
            }
        })
    }

    private fun parsePropfindResponse(xml: String): List<WebDAVFile> {
        val files = mutableListOf<WebDAVFile>()
        // Improved regex to handle namespaces and case sensitivity
        val responseRegex = Regex("<[^>]*response>([\\s\\S]*?)</[^>]*response>", RegexOption.IGNORE_CASE)
        val hrefRegex = Regex("<[^>]*href>([\\s\\S]*?)</[^>]*href>", RegexOption.IGNORE_CASE)
        val etagRegex = Regex("<[^>]*getetag>([\\s\\S]*?)</[^>]*getetag>", RegexOption.IGNORE_CASE)
        val collectionRegex = Regex("<[^>]*collection\\s*/>", RegexOption.IGNORE_CASE)

        responseRegex.findAll(xml).forEach { match ->
            val content = match.groupValues[1]
            val href = hrefRegex.find(content)?.groupValues?.get(1)?.trim() ?: ""
            val etag = etagRegex.find(content)?.groupValues?.get(1)?.trim()?.replace("\"", "") ?: ""
            val isDirectory = collectionRegex.containsMatchIn(content)
            
            val name = href.trimEnd('/').split('/').last()
            files.add(WebDAVFile(name, href, etag, isDirectory))
        }
        return files
    }

    suspend fun download(path: String): ByteArray = suspendCoroutine { continuation ->
        val url = buildUrl(path)
        val request = Request.Builder()
            .url(url)
            .addHeader("Authorization", auth)
            .get()
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                continuation.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                if (!response.isSuccessful) {
                    continuation.resumeWithException(IOException("Unexpected code $response"))
                    return
                }
                continuation.resume(response.body?.bytes() ?: byteArrayOf())
            }
        })
    }

    suspend fun upload(path: String, data: ByteArray): String? = suspendCoroutine { continuation ->
        val url = buildUrl(path)
        val request = Request.Builder()
            .url(url)
            .addHeader("Authorization", auth)
            .put(data.toRequestBody("text/markdown".toMediaType()))
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                continuation.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                if (!response.isSuccessful) {
                    continuation.resumeWithException(IOException("Unexpected code $response"))
                    return
                }
                // Check both ETag and etag headers
                val etag = (response.header("ETag") ?: response.header("etag"))?.replace("\"", "")
                continuation.resume(etag)
            }
        })
    }

    suspend fun delete(path: String): Unit = suspendCoroutine { continuation ->
        val url = buildUrl(path)
        val request = Request.Builder()
            .url(url)
            .addHeader("Authorization", auth)
            .delete()
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                continuation.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                if (!response.isSuccessful && response.code != 404) {
                    continuation.resumeWithException(IOException("Unexpected code $response"))
                    return
                }
                continuation.resume(Unit)
            }
        })
    }

    suspend fun mkcol(path: String): Unit = suspendCoroutine { continuation ->
        val url = buildUrl(path)
        val request = Request.Builder()
            .url(url)
            .addHeader("Authorization", auth)
            .method("MKCOL", null)
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                continuation.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                if (!response.isSuccessful && response.code != 405) { // 405 means already exists
                    continuation.resumeWithException(IOException("Unexpected code $response"))
                    return
                }
                continuation.resume(Unit)
            }
        })
    }
}
