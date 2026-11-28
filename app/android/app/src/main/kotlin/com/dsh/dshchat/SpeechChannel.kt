package com.dsh.dshchat

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `dsh/speech` 通道：把 Dart 侧的 `status` / `requestPermission` / `start` /
 * `stop` / `cancel` 转给 [SpeechRecorder]。录音本身在 SpeechRecorder.kt，
 * 权限回执由 MainActivity 的 `onRequestPermissionsResult` 转发进来。
 */
class SpeechChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, SpeechRecorder.CHANNEL)
    private val recorder = SpeechRecorder(activity)
    private var pending: MethodChannel.Result? = null
    private var disposed = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(statusMap())
            "requestPermission" -> requestPermission(result)
            "start" -> {
                val maxBytes = call.argument<Int>("maxBytes") ?: DEFAULT_MAX_BYTES
                try {
                    recorder.start(maxBytes)
                    result.success(null)
                } catch (error: Exception) {
                    // 回字符串而不是 error：Dart 侧统一转成内联文案，不打印堆栈。
                    result.success(error.message ?: "录音启动失败")
                }
            }
            "stop" -> {
                try {
                    result.success(SpeechRecorder.map(recorder.stop()))
                } catch (error: Exception) {
                    result.error(
                        "mic/failed",
                        error.message ?: "录音失败",
                        null,
                    )
                }
            }
            "cancel" -> {
                recorder.cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun statusMap(): Map<String, Any> = mapOf(
        "supported" to recorder.supported(),
        "granted" to recorder.granted(),
        // Android 的运行时权限总是可以再申请；已授权时申请会立刻回 true。
        "canRequest" to true,
    )

    private fun requestPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || recorder.granted()) {
            result.success(true)
            return
        }
        if (pending != null) {
            // 同时只允许一个在途申请，每个分支恰好回一次 result。
            result.success(false)
            return
        }
        pending = result
        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_CODE)
    }

    /** MainActivity 转发：返回 true 表示这次回执归语音通道。 */
    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending
        pending = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        result?.success(granted)
        return true
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        pending?.success(false)
        pending = null
        recorder.cancel()
        channel.setMethodCallHandler(null)
    }

    companion object {
        private const val REQUEST_CODE = 4302
        // 与桥 MAX_AUDIO_BYTES 对齐；真正上限由 Dart 按 catalog 下发。
        private const val DEFAULT_MAX_BYTES = 4 * 1024 * 1024
    }
}
