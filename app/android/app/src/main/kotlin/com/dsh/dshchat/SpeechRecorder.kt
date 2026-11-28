package com.dsh.dshchat

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.util.Base64
import java.io.ByteArrayOutputStream

/**
 * 语音输入的录音器：16 kHz / 单声道 / PCM16，边录边攒原始 PCM，
 * 结束（[stop]）时补 44 字节 WAV 头再回给 Dart——桥的 `speech-transcribe`
 * 只接受这种 WAV（见 dsh-remote-bridge `src/host/ws-speech.ts`）。
 *
 * 只在 [SpeechChannel] 里用；所有回调都在主线程触发，读写 PCM 的线程
 * 与 stop/cancel 之间用 [lock] 同步。
 */
class SpeechRecorder(private val context: Context) {
    private val lock = Any()
    private val pcm = ByteArrayOutputStream()
    private var record: AudioRecord? = null
    private var worker: Thread? = null

    @Volatile
    private var recording = false

    @Volatile
    private var failure: String? = null

    /** Android 分支恒为 true；没有通道的端由 Dart 侧判定不支持。 */
    fun supported(): Boolean = true

    fun granted(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    /** 开始录音；[maxBytes] 是 WAV 总字节上限（含 44 字节头）。 */
    @Synchronized
    fun start(maxBytes: Int) {
        if (recording) return
        val maxPcm = maxBytes.coerceAtLeast(WAV_HEADER_BYTES + CHUNK_BYTES)
        pcm.reset()
        failure = null
        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) throw IllegalStateException("当前设备不支持 16 kHz 录音")
        val bufferSize = maxOf(minBuffer, SAMPLE_RATE / 5 * BYTES_PER_SAMPLE)
        val source = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            MediaRecorder.AudioSource.VOICE_RECOGNITION
        } else {
            MediaRecorder.AudioSource.MIC
        }
        val recorder = try {
            AudioRecord(
                source,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
            )
        } catch (error: Exception) {
            throw IllegalStateException("麦克风初始化失败：${error.message}")
        }
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            throw IllegalStateException("麦克风被占用或没有录音权限")
        }
        try {
            recorder.startRecording()
        } catch (error: Exception) {
            recorder.release()
            throw IllegalStateException("录音启动失败：${error.message}")
        }
        record = recorder
        recording = true
        worker = Thread({ pump(recorder, maxPcm) }, "dsh-speech-recorder").apply {
            isDaemon = true
            start()
        }
    }

    /** 结束录音并返回 WAV（空录音也回合法头，由 Dart 侧判空）。 */
    @Synchronized
    fun stop(): ByteArray {
        finish()
        val data = synchronized(lock) { pcm.toByteArray() }
        failure?.let { throw IllegalStateException(it) }
        return wavBytes(data)
    }

    /** 丢弃缓冲（取消）。 */
    @Synchronized
    fun cancel() {
        finish()
        synchronized(lock) { pcm.reset() }
    }

    private fun pump(recorder: AudioRecord, maxPcm: Int) {
        val buffer = ShortArray(CHUNK_SAMPLES)
        val bytes = ByteArray(CHUNK_SAMPLES * BYTES_PER_SAMPLE)
        try {
            while (recording) {
                val read = recorder.read(buffer, 0, buffer.size)
                if (read < 0) {
                    failure = "录音中断（错误码 $read）"
                    break
                }
                if (read == 0) continue
                for (i in 0 until read) {
                    val sample = buffer[i].toInt()
                    bytes[i * 2] = (sample and 0xFF).toByte()
                    bytes[i * 2 + 1] = ((sample shr 8) and 0xFF).toByte()
                }
                synchronized(lock) {
                    val room = maxPcm - WAV_HEADER_BYTES - pcm.size()
                    if (room > 0) {
                        pcm.write(bytes, 0, minOf(room, read * BYTES_PER_SAMPLE))
                    }
                    if (pcm.size() >= maxPcm - WAV_HEADER_BYTES) recording = false
                }
            }
        } catch (error: Exception) {
            failure = "录音失败：${error.message}"
        }
    }

    /** 停线程、停录音、释放设备；可重复调用。 */
    private fun finish() {
        recording = false
        worker?.let { thread ->
            try {
                thread.join(600)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
        worker = null
        record?.let { recorder ->
            try {
                if (recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    recorder.stop()
                }
            } catch (_: Exception) {
                // 已停止或设备被拔掉，忽略。
            }
            recorder.release()
        }
        record = null
    }

    companion object {
        const val CHANNEL = "dsh/speech"
        const val SAMPLE_RATE = 16_000
        const val CHANNELS = 1
        const val BITS_PER_SAMPLE = 16
        const val BYTES_PER_SAMPLE = 2
        const val WAV_HEADER_BYTES = 44
        private const val CHUNK_SAMPLES = 3_200 // 200 ms
        private const val CHUNK_BYTES = CHUNK_SAMPLES * BYTES_PER_SAMPLE

        /** 给 Dart 的 `SpeechRecording.fromMap`：base64 WAV + 采样数。 */
        fun map(wav: ByteArray): Map<String, Any> = mapOf(
            "format" to "wav",
            "base64" to Base64.encodeToString(wav, Base64.NO_WRAP),
            "bytes" to wav.size,
            "sampleRate" to SAMPLE_RATE,
            "samples" to ((wav.size - WAV_HEADER_BYTES) / BYTES_PER_SAMPLE).coerceAtLeast(0),
        )

        /** 在 PCM16 数据前补标准 44 字节 RIFF/WAVE 头（小端）。 */
        fun wavBytes(pcmData: ByteArray): ByteArray {
            val out = ByteArray(WAV_HEADER_BYTES + pcmData.size)
            val byteRate = SAMPLE_RATE * CHANNELS * BYTES_PER_SAMPLE
            val blockAlign = CHANNELS * BYTES_PER_SAMPLE
            "RIFF".toByteArray(Charsets.US_ASCII).copyInto(out, 0)
            putInt(out, 4, 36 + pcmData.size)
            "WAVE".toByteArray(Charsets.US_ASCII).copyInto(out, 8)
            "fmt ".toByteArray(Charsets.US_ASCII).copyInto(out, 12)
            putInt(out, 16, 16)
            putShort(out, 20, 1) // PCM
            putShort(out, 22, CHANNELS)
            putInt(out, 24, SAMPLE_RATE)
            putInt(out, 28, byteRate)
            putShort(out, 32, blockAlign)
            putShort(out, 34, BITS_PER_SAMPLE)
            "data".toByteArray(Charsets.US_ASCII).copyInto(out, 36)
            putInt(out, 40, pcmData.size)
            pcmData.copyInto(out, WAV_HEADER_BYTES)
            return out
        }

        private fun putInt(target: ByteArray, offset: Int, value: Int) {
            target[offset] = (value and 0xFF).toByte()
            target[offset + 1] = ((value shr 8) and 0xFF).toByte()
            target[offset + 2] = ((value shr 16) and 0xFF).toByte()
            target[offset + 3] = ((value shr 24) and 0xFF).toByte()
        }

        private fun putShort(target: ByteArray, offset: Int, value: Int) {
            target[offset] = (value and 0xFF).toByte()
            target[offset + 1] = ((value shr 8) and 0xFF).toByte()
        }
    }
}
