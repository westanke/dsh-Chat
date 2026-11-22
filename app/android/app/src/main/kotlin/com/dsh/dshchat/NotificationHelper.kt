package com.dsh.dshchat

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * 系统通知（对齐 dsh-go 的通知模式：两条通道 + 点击回会话）。
 *
 * 通道划分：
 * - `done`      一轮回答结束（低打扰，静音、不弹横幅）；
 * - `attention` 需要用户处理（审批 / 提问，响铃 + 横幅）。
 *
 * 零第三方依赖：NotificationCompat + NotificationChannel（API 26+ 才有通道；
 * minSdk 以下直接走默认通道语义）。
 */
object NotificationHelper {
    const val CHANNEL_DONE = "done"
    const val CHANNEL_ATTENTION = "attention"

    const val EXTRA_KEY = "dsh.notifyKey"
    const val EXTRA_SESSION_ID = "dsh.sessionId"
    const val EXTRA_KIND = "dsh.kind"
    const val EXTRA_EVENT_ID = "dsh.eventId"

    private const val GROUP = "dsh.session"

    private fun idOf(key: String): Int = key.hashCode()

    fun notificationManager(ctx: Context): NotificationManager =
        ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    /** 建通道（幂等）：应用启动与设置页各调一次都安全。 */
    fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = notificationManager(ctx)
        val done = NotificationChannel(
            CHANNEL_DONE,
            "回答完成",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "一轮回答结束、任务做完时提醒（不打扰）"
            setShowBadge(true)
            enableVibration(false)
            setSound(null, null)
        }
        val attention = NotificationChannel(
            CHANNEL_ATTENTION,
            "需要你处理",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "工具审批、提问等待回答时提醒"
            setShowBadge(true)
            enableVibration(true)
        }
        nm.createNotificationChannel(done)
        nm.createNotificationChannel(attention)
    }

    /** 系统层面是否允许弹通知（Android 13+ 还要运行时权限）。 */
    fun canPost(ctx: Context): Boolean {
        val grantedByOs = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                ctx, Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        return grantedByOs && NotificationManagerCompat.from(ctx).areNotificationsEnabled()
    }

    fun status(ctx: Context): Map<String, Boolean> {
        val enabled = NotificationManagerCompat.from(ctx).areNotificationsEnabled()
        val permission = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                ctx, Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        return mapOf("permission" to permission, "enabled" to enabled)
    }

    /**
     * 弹一条通知。返回是否真的发出（无权限/系统关闭返回 false）。
     * [sessionId] 会写进点击 Intent，App 据此跳到对应会话。
     */
    fun show(
        ctx: Context,
        key: String,
        title: String,
        text: String,
        attention: Boolean,
        sessionId: String?,
    ): Boolean {
        if (!canPost(ctx)) return false
        ensureChannels(ctx)
        val tap = Intent(ctx, MainActivity::class.java).apply {
            action = "dsh.notify.$key"
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_KEY, key)
            if (!sessionId.isNullOrBlank()) putExtra(EXTRA_SESSION_ID, sessionId)
        }
        val pi = PendingIntent.getActivity(
            ctx,
            idOf(key),
            tap,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val channel = if (attention) CHANNEL_ATTENTION else CHANNEL_DONE
        val builder = NotificationCompat.Builder(ctx, channel)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setGroup(GROUP)
            .setPriority(
                if (attention) NotificationCompat.PRIORITY_HIGH
                else NotificationCompat.PRIORITY_LOW
            )
        if (attention) builder.setCategory(NotificationCompat.CATEGORY_REMINDER)
        return try {
            NotificationManagerCompat.from(ctx).notify(idOf(key), builder.build())
            true
        } catch (e: SecurityException) {
            false
        }
    }

    fun cancel(ctx: Context, key: String) {
        try {
            NotificationManagerCompat.from(ctx).cancel(idOf(key))
        } catch (_: Exception) {
            // 忽略：取消失败无影响。
        }
    }

    fun cancelAll(ctx: Context) {
        try {
            NotificationManagerCompat.from(ctx).cancelAll()
        } catch (_: Exception) {
            // 忽略。
        }
    }

    /** 跳系统通知设置（权限被永久拒绝时只能在这里改）。 */
    fun openSettings(ctx: Context) {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, ctx.packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:${ctx.packageName}"))
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            ctx.startActivity(intent)
        } catch (_: Exception) {
            // 部分 ROM 无此页面：忽略。
        }
    }
}
