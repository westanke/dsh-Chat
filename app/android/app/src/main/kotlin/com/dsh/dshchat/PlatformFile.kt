package com.dsh.dshchat

import android.app.Activity
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File

/**
 * 文件打开 / 分享：字节写进应用缓存，再用 FileProvider 授权给系统查看器
 * 或分享面板。全程不需要存储权限，也不把文件暴露到公共目录。
 *
 * 从 MainActivity 拆出来（宪法 §7 单文件 ≤ 500 行），行为与原 openFile
 * 分支一致：文件名只保留最后一段并做字符白名单，避免路径穿越。
 */
object PlatformFile {
    private fun cached(
        context: Context,
        dirName: String,
        name: String,
        bytes: ByteArray,
    ): File {
        val dir = File(context.cacheDir, dirName)
        dir.mkdirs()
        val safe = name.substringAfterLast('/')
            .replace(Regex("[^A-Za-z0-9._\\-\\u4e00-\\u9fa5]"), "_")
        val file = File(dir, safe)
        file.writeBytes(bytes)
        return file
    }

    private fun uriFor(context: Context, file: File) =
        FileProvider.getUriForFile(context, "com.dsh.dshchat.fileprovider", file)

    /** 系统「打开方式」。没有可处理的应用返回 false。 */
    fun open(
        activity: Activity,
        name: String,
        mime: String?,
        bytes: ByteArray,
    ): Boolean {
        return try {
            val uri = uriFor(activity, cached(activity, "open", name, bytes))
            val view = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(
                    uri,
                    mime?.takeIf { it.isNotBlank() } ?: "application/octet-stream",
                )
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            val hasTarget = view.resolveActivity(activity.packageManager) != null
            if (hasTarget) activity.startActivity(view)
            hasTarget
        } catch (e: Exception) {
            false
        }
    }

    /** 系统分享面板，接收方拿到文件本体。 */
    fun share(
        activity: Activity,
        name: String,
        mime: String?,
        bytes: ByteArray,
    ): Boolean {
        return try {
            val uri = uriFor(activity, cached(activity, "share", name, bytes))
            val send = Intent(Intent.ACTION_SEND).apply {
                type = mime?.takeIf { it.isNotBlank() } ?: "application/octet-stream"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(send, "分享文件")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(chooser)
            true
        } catch (e: Exception) {
            false
        }
    }
}
