package com.dsh.dshchat

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    // 系统 TTS（真机反馈 2026-11-04：朗读用系统资源，零第三方依赖）。
    // 惰性初始化；onInit 未就绪前到达的 speak 暂存，就绪后补播。
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var pendingSpeak: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dsh/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // bridge 校验 clientTimeZone 必须是 IANA Area/Location（IANA_ZONE 正则，
                    // dsh-remote-bridge src/host/bff-schedule.ts:488）；Dart timeZoneName
                    // 在 Android 返回缩写（如 CST）不合规，读原生 ID（如 Asia/Shanghai）。
                    "ianaZone" -> result.success(TimeZone.getDefault().id)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dsh/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "speak" -> {
                        val text = call.arguments as? String
                        if (text.isNullOrBlank()) {
                            result.success(false)
                        } else if (ttsReady) {
                            result.success(speakNow(text))
                        } else {
                            // onInit 是异步的：暂存待读文本，就绪后补播；
                            // 每个分支恰好调用一次 result（宪法级纪律）。
                            pendingSpeak = text
                            ensureTts()
                            result.success(true)
                        }
                    }
                    "stopSpeak" -> {
                        tts?.stop()
                        pendingSpeak = null
                        result.success(null)
                    }
                    "share" -> {
                        val text = call.arguments as? String
                        if (text.isNullOrBlank()) {
                            result.success(false)
                        } else {
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, text)
                            }
                            val chooser = Intent.createChooser(send, null)
                            val hasTarget = send.resolveActivity(packageManager) != null
                            if (hasTarget) startActivity(chooser)
                            result.success(hasTarget)
                        }
                    }
                    "pickImage" -> {
                        // 系统图片选择器（image/*）；异步回 onActivityResult。
                        // 同时只允许一个在途请求。
                        if (pickImageResult != null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        pickImageResult = result
                        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                            type = "image/*"
                            addCategory(Intent.CATEGORY_OPENABLE)
                        }
                        try {
                            startActivityForResult(intent, pickImageRequest)
                        } catch (e: Exception) {
                            pickImageResult = null
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // 选图请求码（pickImage：ACTION_GET_CONTENT 系统选择器，零权限零依赖）。
    private val pickImageRequest = 4201
    private var pickImageResult: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickImageRequest) return
        val result = pickImageResult
        pickImageResult = null
        if (result == null) return
        val uri: Uri? = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            // 复制进应用缓存目录（content:// URI 跨进程读取不稳定）。
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
            if (bytes == null) {
                result.success(null)
                return
            }
            val name = queryDisplayName(uri) ?: "image"
            val cacheFile = File(cacheDir, "pick-$name")
            cacheDir.mkdirs()
            cacheFile.writeBytes(bytes)
            result.success(mapOf("path" to cacheFile.absolutePath, "name" to name))
        } catch (e: Exception) {
            result.success(null)
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx >= 0 && c.moveToFirst()) return c.getString(idx)
        }
        return null
    }

    private fun ensureTts() {
        if (tts != null) return
        tts = TextToSpeech(this) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            if (ttsReady) {
                tts?.language = Locale.getDefault()
                val queued = pendingSpeak
                pendingSpeak = null
                if (queued != null) speakNow(queued)
            }
        }
    }

    private fun speakNow(text: String): Boolean {
        val engine = tts ?: return false
        // 四参重载（三参已废弃）；QUEUE_FLUSH 打断上一次朗读。
        val r = engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "dsh-chat-$text.hashCode()")
        return r == TextToSpeech.SUCCESS
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        ttsReady = false
        pendingSpeak = null
        super.onDestroy()
    }
}
