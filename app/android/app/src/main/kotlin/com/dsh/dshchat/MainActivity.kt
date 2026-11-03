package com.dsh.dshchat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
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
    }
}
