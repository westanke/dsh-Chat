package com.dsh.dshchat

import android.content.Intent
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
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
                    else -> result.notImplemented()
                }
            }
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
