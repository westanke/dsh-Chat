package com.dsh.dshchat

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.ByteArrayOutputStream

/**
 * 选图后的字节处理：按字节魔数定真实类型 + 把内核不收的格式在客户端转码。
 *
 * 背景（docs/huawei-heic-upload-report.md）：
 * - 判类型只信字节，不信 OpenableColumns.DISPLAY_NAME —— 华为/荣耀图库常返回
 *   无扩展名、纯数字 ID 或 null 的显示名，按文件名猜扩展名必然误拒。
 * - 内核内联 prompt 只收 png/jpeg/webp/gif 四种
 *   （@deepseek-ai/dsh-attachment-local/lib/index.js:998-1009 的
 *   imageLimits.mediaTypes 是 Object.freeze 死字面量，无配置入口）。
 *   华为「高效照片」HEIC、HEIF、BMP、AVIF 必须先转成 JPEG/PNG 再发。
 * - 魔数表对齐 dsh-remote-bridge/src/host/image-handoff.ts:165-189
 *   sniffMediaType；转码口径对齐 dsh-companion ImageTranscoder.kt。
 *
 * 本文件不依赖 Activity/Context，纯字节进纯字节出，便于人工核对。
 */
internal object ImagePickHelper {

    /** 内核内联 prompt 接受的 mediaType（其它一律转码后再发）。 */
    val supportedMediaTypes: Set<String> = setOf(
        "image/png", "image/jpeg", "image/webp", "image/gif"
    )

    /** 与 composer.dart:332-339 的发送上限一致（8 MiB）。 */
    const val MAX_IMAGE_BYTES: Long = 8L * 1024 * 1024

    /** 解码上限，仅防超大图 OOM；不是压缩（dsh-companion issue #15 裁定）。 */
    private const val MAX_DECODE_PIXELS: Long = 4096L * 4096L
    private const val JPEG_QUALITY = 90

    sealed interface Prepared {
        data class Success(
            val bytes: ByteArray,
            val mediaType: String,
            val extension: String,
        ) : Prepared

        /** 面向用户的中文失败原因（不再静默吞掉）。 */
        data class Failure(val message: String) : Prepared
    }

    /**
     * 把选择器返回的原始字节整成「可直接内联发送」的字节。
     * 已在 supportedMediaTypes 内的原样返回；其余（含认不出的）尝试解码并
     * 重编码成 JPEG/PNG；解码不了给明确原因。
     */
    fun prepare(bytes: ByteArray, limitBytes: Long = MAX_IMAGE_BYTES): Prepared {
        val sniffed = sniffMediaType(bytes)
        if (sniffed != null && sniffed in supportedMediaTypes) {
            return Prepared.Success(bytes, sniffed, extensionFor(sniffed))
        }
        return when (val r = transcode(bytes, limitBytes)) {
            is TranscodeResult.Success ->
                Prepared.Success(r.bytes, r.mediaType, extensionFor(r.mediaType))
            is TranscodeResult.TooLarge ->
                Prepared.Failure("图片转码后超过 8MB，请选小一点的图")
            TranscodeResult.Undecodable -> Prepared.Failure(
                if (sniffed == null) {
                    "无法识别这张图片的格式，请换一张 PNG/JPEG 图片"
                } else {
                    "这台设备无法解码该图片格式，请换一张 PNG/JPEG 图片"
                }
            )
        }
    }

    /** 按字节魔数嗅探真实 mediaType；认不出返回 null。与 bridge sniffMediaType 同表。 */
    fun sniffMediaType(bytes: ByteArray): String? {
        if (matches(bytes, 0, 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)) {
            return "image/png"
        }
        if (matches(bytes, 0, 0xff, 0xd8, 0xff)) return "image/jpeg"
        if (ascii(bytes, 0, "GIF87a") || ascii(bytes, 0, "GIF89a")) return "image/gif"
        if (ascii(bytes, 0, "RIFF") && ascii(bytes, 8, "WEBP")) return "image/webp"
        if (matches(bytes, 0, 0x42, 0x4d)) return "image/bmp"
        if (ascii(bytes, 4, "ftyp") && bytes.size >= 12) {
            val brand = ascii(bytes, 8, 4)
            return when {
                brand.startsWith("avi") -> "image/avif"
                brand.startsWith("hei") || brand.startsWith("hev") ||
                    brand.startsWith("mif") -> "image/heic"
                else -> null
            }
        }
        return null
    }

    /** mediaType → 缓存文件/展示名用的扩展名。 */
    fun extensionFor(mediaType: String): String = when (mediaType) {
        "image/png" -> "png"
        "image/jpeg" -> "jpg"
        "image/webp" -> "webp"
        "image/gif" -> "gif"
        "image/bmp" -> "bmp"
        "image/heic" -> "heic"
        "image/avif" -> "avif"
        else -> "bin"
    }

    /**
     * 缓存文件名：只用真实扩展名，不拼 DISPLAY_NAME（它可能含 '/'、为空或为 "image"）。
     * 用 nanoTime 保证连续选图不互相覆盖（_send 会读该文件长度做 8MiB 检查）。
     */
    fun cacheFileName(extension: String): String = "pick-${System.nanoTime()}.$extension"

    /** 净化显示名并补上真实扩展名；name 只用于展示/服务端 handoff 文件名。 */
    fun displayName(raw: String?, mediaType: String): String {
        val cleaned = (raw ?: "image")
            .substringAfterLast('/')
            .replace(knownImageExtension, "")
            .replace(Regex("[^A-Za-z0-9._\\-\\u4e00-\\u9fa5]"), "_")
            .trim('_')
            .takeIf { it.isNotBlank() } ?: "image"
        return "$cleaned.${extensionFor(mediaType)}"
    }

    private val knownImageExtension = Regex(
        "\\.(heic|heif|jpe?g|png|webp|gif|bmp|avif)$",
        RegexOption.IGNORE_CASE,
    )

    // ---- 转码（照搬 dsh-companion/app/.../data/ImageTranscoder.kt:36-127） ----

    private sealed interface TranscodeResult {
        data class Success(val bytes: ByteArray, val mediaType: String) : TranscodeResult
        data class TooLarge(val sizeBytes: Long) : TranscodeResult
        object Undecodable : TranscodeResult
    }

    private fun transcode(bytes: ByteArray, limitBytes: Long): TranscodeResult {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds) }
        val width = bounds.outWidth
        val height = bounds.outHeight
        if (width <= 0 || height <= 0) return TranscodeResult.Undecodable

        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSizeFor(width, height)
        }
        val decoded = runCatching {
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        }.getOrNull() ?: return TranscodeResult.Undecodable

        return try {
            // 带 alpha 编 PNG 保透明，否则 JPEG；一律 PNG 会让 8MiB HEIC
            // 变成几十 MB 撞发送上限。
            val mediaType = if (decoded.hasAlpha()) "image/png" else "image/jpeg"
            val format = if (mediaType == "image/png") {
                Bitmap.CompressFormat.PNG
            } else {
                Bitmap.CompressFormat.JPEG
            }
            val encoded = runCatching {
                ByteArrayOutputStream().use { out ->
                    if (!decoded.compress(format, JPEG_QUALITY, out)) null
                    else out.toByteArray()
                }
            }.getOrNull() ?: return TranscodeResult.Undecodable
            if (encoded.size.toLong() > limitBytes) {
                TranscodeResult.TooLarge(encoded.size.toLong())
            } else {
                TranscodeResult.Success(encoded, mediaType)
            }
        } finally {
            decoded.recycle()
        }
    }

    private fun sampleSizeFor(width: Int, height: Int): Int {
        if (width <= 0 || height <= 0) return 1
        var sample = 1
        while (width.toLong() / sample * (height.toLong() / sample) > MAX_DECODE_PIXELS) {
            sample *= 2
        }
        return sample
    }

    // ---- 字节小工具 ----

    private fun matches(b: ByteArray, off: Int, vararg sig: Int): Boolean {
        if (b.size < off + sig.size) return false
        for (i in sig.indices) {
            if ((b[off + i].toInt() and 0xff) != sig[i]) return false
        }
        return true
    }

    private fun ascii(b: ByteArray, off: Int, s: String): Boolean {
        if (b.size < off + s.length) return false
        for (i in s.indices) {
            if ((b[off + i].toInt() and 0xff) != s[i].code) return false
        }
        return true
    }

    private fun ascii(b: ByteArray, off: Int, len: Int): String {
        if (b.size < off + len) return ""
        return buildString(len) {
            for (i in 0 until len) append((b[off + i].toInt() and 0xff).toChar())
        }
    }
}
