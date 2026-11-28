package com.dsh.dshchat

import android.Manifest
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.OpenableColumns
import android.provider.Settings
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

    // 通知（dsh/notify）：通道回调 + 权限申请回执 + 冷启动时未送达的点击载荷。
    private var notifyChannel: MethodChannel? = null
    private var notifyPermissionResult: MethodChannel.Result? = null
    private var pendingTap: Map<String, String>? = null

    // 语音输入（dsh/speech）：录音 + 麦克风权限回执，实现在 SpeechChannel.kt。
    private var speechChannel: SpeechChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dsh/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // bridge 校验 clientTimeZone 必须是 IANA Area/Location（IANA_ZONE 正则，
                    // dsh-remote-bridge src/host/bff-schedule.ts:488）；Dart timeZoneName
                    // 在 Android 返回缩写（如 CST）不合规，读原生 ID（如 Asia/Shanghai）。
                    "ianaZone" -> result.success(TimeZone.getDefault().id)
                    "deviceName" -> result.success(deviceDisplayName())
                    else -> result.notImplemented()
                }
            }
        val notify = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dsh/notify")
        notifyChannel = notify
        notify.setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureChannels" -> {
                    NotificationHelper.ensureChannels(this)
                    result.success(null)
                }
                "status" -> result.success(NotificationHelper.status(this))
                "requestPermission" -> {
                    // Android 13+ 才需要运行时权限；已有权限直接回 true。
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success(NotificationHelper.canPost(this))
                    } else if (notifyPermissionResult != null) {
                        // 同时只允许一个在途申请（每个分支恰好回一次 result）。
                        result.success(false)
                    } else {
                        notifyPermissionResult = result
                        requestPermissions(
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            notifyPermissionRequest,
                        )
                    }
                }
                "openSettings" -> {
                    NotificationHelper.openSettings(this)
                    result.success(null)
                }
                "show" -> {
                    val args = call.arguments as? Map<*, *>
                    val key = args?.get("key") as? String
                    val title = args?.get("title") as? String
                    val text = args?.get("text") as? String
                    if (key.isNullOrBlank() || title.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        result.success(
                            NotificationHelper.show(
                                this,
                                key,
                                title,
                                text ?: "",
                                args?.get("attention") == true,
                                args?.get("sessionId") as? String,
                            )
                        )
                    }
                }
                "cancel" -> {
                    val args = call.arguments as? Map<*, *>
                    val key = args?.get("key") as? String
                    if (!key.isNullOrBlank()) NotificationHelper.cancel(this, key)
                    result.success(null)
                }
                "cancelAll" -> {
                    NotificationHelper.cancelAll(this)
                    result.success(null)
                }
                "takeLaunchTap" -> {
                    val tap = pendingTap
                    pendingTap = null
                    result.success(tap)
                }
                else -> result.notImplemented()
            }
        }
        // 冷启动：从通知点进来时，把载荷交给 Dart（Dart 侧 takeLaunchTap 取）。
        handleNotifyIntent(intent)
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
                            // 部分 DocumentsProvider / 华为图库实现下补临时读授权更稳妥
                            // （docs/huawei-heic-upload-report.md §4.5）。
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        try {
                            startActivityForResult(intent, pickImageRequest)
                        } catch (e: Exception) {
                            pickImageResult = null
                            result.success(null)
                        }
                    }
                    "appVersion" -> {
                        // 版本随发版自动同步：Flutter 工具链把 pubspec 的 version
                        // 写进 gradle 的 versionName/versionCode，这里原样上抛，
                        // Dart 侧不再写死字符串（2026-11-15 发版号漂移修复）。
                        val pi = packageManager.getPackageInfo(packageName, 0)
                        result.success(
                            mapOf(
                                "version" to (pi.versionName ?: ""),
                                "code" to pi.longVersionCode
                            )
                        )
                    }
                    "downloadApk" -> {
                        // 系统下载器下载 APK（真机反馈 2026-11-04 第 9 项）。
                        // DownloadManager 是系统服务，不需要任何运行时权限。
                        // 第二轮反馈 C：返回任务 id（-1 = 失败），Dart 侧轮询
                        // downloadStatus 显示进度；完成后 installApk 拉起安装。
                        val args = call.arguments as? Map<*, *>
                        val url = args?.get("url") as? String
                        val name = args?.get("name") as? String
                        if (url.isNullOrBlank() || name.isNullOrBlank()) {
                            result.success(-1L)
                        } else {
                            try {
                                val req = DownloadManager.Request(Uri.parse(url))
                                    .setTitle(name)
                                    .setDescription("DSH Chat 更新包")
                                    .setMimeType(
                                        "application/vnd.android.package-archive")
                                    .setNotificationVisibility(
                                        DownloadManager.Request
                                            .VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                                    .setDestinationInExternalPublicDir(
                                        Environment.DIRECTORY_DOWNLOADS, name)
                                    .setAllowedOverMetered(true)
                                val dm = getSystemService(DOWNLOAD_SERVICE)
                                    as DownloadManager
                                result.success(dm.enqueue(req))
                            } catch (e: Exception) {
                                result.success(-1L)
                            }
                        }
                    }
                    "downloadStatus" -> {
                        // 查询下载任务状态（第二轮反馈 C）：返回
                        // {status, bytes, total}；status 为
                        // STATUS_SUCCESSFUL(8) / STATUS_FAILED(16) / 运行中(1-4)。
                        val args = call.arguments as? Map<*, *>
                        val id = (args?.get("id") as? Number)?.toLong()
                        val dm = getSystemService(DOWNLOAD_SERVICE) as DownloadManager
                        if (id == null || id < 0) {
                            result.success(null)
                        } else {
                            try {
                                val q = DownloadManager.Query().setFilterById(id)
                                dm.query(q)?.use { c ->
                                    if (c.moveToFirst()) {
                                        val si = c.getColumnIndex(
                                            DownloadManager.COLUMN_STATUS)
                                        val bi = c.getColumnIndex(
                                            DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
                                        val ti = c.getColumnIndex(
                                            DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
                                        result.success(mapOf(
                                            "status" to c.getInt(si),
                                            "bytes" to c.getLong(bi),
                                            "total" to c.getLong(ti)))
                                    } else {
                                        // 任务被系统清理/不存在
                                        result.success(mapOf(
                                            "status" to 16, "bytes" to 0L, "total" to 0L))
                                    }
                                } ?: result.success(mapOf(
                                    "status" to 16, "bytes" to 0L, "total" to 0L))
                            } catch (e: Exception) {
                                result.success(mapOf(
                                    "status" to 16, "bytes" to 0L, "total" to 0L))
                            }
                        }
                    }
                    "installApk" -> {
                        // 拉起安装器（第二轮反馈 C）：下载完成后自动调用。
                        // DownloadManager 的完成下载对当前 app（作为下载发起方）
                        // 可直接读，不需要 FileProvider / REQUEST_INSTALL_PACKAGES
                        // 声明——「安装未知应用」授权由系统安装器向用户索取。
                        val args = call.arguments as? Map<*, *>
                        val id = (args?.get("id") as? Number)?.toLong()
                        val dm = getSystemService(DOWNLOAD_SERVICE) as DownloadManager
                        if (id == null || id < 0) {
                            result.success(false)
                        } else {
                            try {
                                val uri = dm.getUriForDownloadedFile(id)
                                if (uri == null) {
                                    result.success(false)
                                } else {
                                    val intent = Intent(Intent.ACTION_VIEW)
                                        .setDataAndType(
                                            uri,
                                            "application/vnd.android.package-archive")
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                                            Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    startActivity(intent)
                                    result.success(true)
                                }
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    "openFile" -> {
                        // 系统打开文件（文件卡：非 md 文件走系统「打开方式」）。
                        // 具体写缓存 + FileProvider 在 PlatformFile.kt。
                        val args = call.arguments as? Map<*, *>
                        val name = args?.get("name") as? String
                        val mime = args?.get("mime") as? String
                        val bytes = args?.get("bytes") as? ByteArray
                        if (name.isNullOrBlank() || bytes == null) {
                            result.success(false)
                        } else {
                            result.success(PlatformFile.open(this, name, mime, bytes))
                        }
                    }
                    "shareFile" -> {
                        // 分享文件本体（产物卡/交付卡）；接收方拿到文件，
                        // 不是路径文本。写缓存 + FileProvider 在 PlatformFile.kt。
                        val args = call.arguments as? Map<*, *>
                        val name = args?.get("name") as? String
                        val mime = args?.get("mime") as? String
                        val bytes = args?.get("bytes") as? ByteArray
                        if (name.isNullOrBlank() || bytes == null) {
                            result.success(false)
                        } else {
                            result.success(PlatformFile.share(this, name, mime, bytes))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        speechChannel = SpeechChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    private val notifyPermissionRequest = 4301

    /** 从通知点进来：单例 Activity 不复用启动参数，靠 onNewIntent 补齐。 */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleNotifyIntent(intent)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (speechChannel?.onRequestPermissionsResult(requestCode, grantResults) == true) return
        if (requestCode != notifyPermissionRequest) return
        val result = notifyPermissionResult
        notifyPermissionResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        // 已授权但系统总开关关着也算发不出去，统一回 canPost。
        result?.success(granted && NotificationHelper.canPost(this))
    }

    /**
     * 把通知点击的 sessionId 转成 Flutter 事件：Flutter 侧已在监听就直接推，
     * 引擎还没起来（冷启动）就先存着等 takeLaunchTap 来取。
     */
    private fun handleNotifyIntent(intent: Intent?) {
        if (intent == null) return
        val sessionId = intent.getStringExtra(NotificationHelper.EXTRA_SESSION_ID)
        val key = intent.getStringExtra(NotificationHelper.EXTRA_KEY)
        if (sessionId.isNullOrBlank() && key.isNullOrBlank()) return
        val payload = HashMap<String, String>()
        if (!sessionId.isNullOrBlank()) payload["sessionId"] = sessionId
        if (!key.isNullOrBlank()) payload["key"] = key
        intent.removeExtra(NotificationHelper.EXTRA_SESSION_ID)
        intent.removeExtra(NotificationHelper.EXTRA_KEY)
        val channel = notifyChannel
        if (channel == null) {
            pendingTap = payload
        } else {
            channel.invokeMethod("tap", payload)
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
                result.success(mapOf("error" to "读取图片失败，请重新选择"))
                return
            }
            // 按字节魔数定真实类型：不信 DISPLAY_NAME（华为常无扩展名/纯数字），
            // 也不直接发 image/heic（内核内联 prompt 只收 4 种，见
            // docs/huawei-heic-upload-report.md §3/§4.3）。内核不收的格式在
            // 客户端转码成 JPEG/PNG 后再回传。
            when (val prepared = ImagePickHelper.prepare(bytes)) {
                is ImagePickHelper.Prepared.Failure -> {
                    result.success(mapOf("error" to prepared.message))
                    return
                }
                is ImagePickHelper.Prepared.Success -> {
                    val cacheFile = File(cacheDir, ImagePickHelper.cacheFileName(prepared.extension))
                    cacheDir.mkdirs()
                    cacheFile.writeBytes(prepared.bytes)
                    val name = ImagePickHelper.displayName(queryDisplayName(uri), prepared.mediaType)
                    result.success(
                        mapOf(
                            "path" to cacheFile.absolutePath,
                            "name" to name,
                            "mediaType" to prepared.mediaType,
                        )
                    )
                }
            }
        } catch (e: Exception) {
            // 不再静默吞掉：把可读原因回传，由 Dart 侧弹 SnackBar。
            result.success(mapOf("error" to "读取图片失败：${e.message ?: "未知错误"}"))
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
        speechChannel?.dispose()
        speechChannel = null
        super.onDestroy()
    }
    /**
     * 当前设备展示名：优先系统设置里的设备名（Android 7.1+），
     * 回退「厂商 + 型号」，再回退 Android。
     */
    private fun deviceDisplayName(): String {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                val configured = Settings.Global.getString(
                    contentResolver,
                    Settings.Global.DEVICE_NAME,
                )
                if (!configured.isNullOrBlank()) return configured.trim()
            }
        } catch (_: Exception) {
            // 某些 ROM 不允许读该设置，继续走型号回退。
        }
        val manufacturer = Build.MANUFACTURER?.trim().orEmpty()
        val model = Build.MODEL?.trim().orEmpty()
        return when {
            model.isBlank() -> manufacturer.ifBlank { "Android" }
            manufacturer.isBlank() || model.startsWith(manufacturer, ignoreCase = true) -> model
            else -> "$manufacturer $model"
        }
    }

}
