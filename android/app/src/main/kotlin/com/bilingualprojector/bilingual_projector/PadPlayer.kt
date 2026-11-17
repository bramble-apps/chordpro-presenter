package com.bilingualprojector.bilingual_projector

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/**
 * The worship pad's sound on Android: each loop is written to an audio
 * stream over and over, so it never stops to restart (the media player
 * leaves a small gap each time a loop starts again). A new key fades in on
 * its own stream while the old one fades out.
 *
 * Channel `bp/pads`: `play` {wav, fade}, `stop` {fade}, `volume` {volume}.
 */
object PadPlayer {
    private val voices = mutableListOf<Voice>()

    @Volatile
    private var master = 0.7f

    fun attach(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "bp/pads")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        val wav = call.argument<ByteArray>("wav")!!
                        val fade = call.argument<Double>("fade") ?: 3.0
                        fadeOutAll(fade)
                        synchronized(voices) {
                            voices.add(Voice(wav, fade).also { it.start() })
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        fadeOutAll(call.argument<Double>("fade") ?: 2.0)
                        result.success(null)
                    }
                    "volume" -> {
                        master = (call.argument<Double>("volume") ?: 0.7).toFloat()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    fun detach() = fadeOutAll(0.05)

    private fun fadeOutAll(fade: Double) {
        synchronized(voices) {
            for (v in voices) v.fadeOut(fade)
            voices.clear()
        }
    }

    /** One looping sound (a 16-bit WAV), with its own fade. */
    private class Voice(wav: ByteArray, fadeIn: Double) {
        private val rate: Int
        private val channels: Int
        private val pcm: ShortArray
        private val track: AudioTrack

        // The fade: from [from] to [to] over [fadeFrames], equal power.
        @Volatile private var from = 0f
        @Volatile private var to = 1f
        @Volatile private var fadeFrames = 1
        @Volatile private var fadeDone = 0
        @Volatile private var running = true
        private var level = 0f

        init {
            val head = ByteBuffer.wrap(wav).order(ByteOrder.LITTLE_ENDIAN)
            channels = head.getShort(22).toInt()
            rate = head.getInt(24)
            pcm = ShortArray((wav.size - 44) / 2)
            ByteBuffer.wrap(wav, 44, wav.size - 44)
                .order(ByteOrder.LITTLE_ENDIAN)
                .asShortBuffer()
                .get(pcm)
            fadeFrames = max(1, (fadeIn * rate).toInt())
            val mask = if (channels == 2) AudioFormat.CHANNEL_OUT_STEREO
            else AudioFormat.CHANNEL_OUT_MONO
            val min = AudioTrack.getMinBufferSize(rate, mask, AudioFormat.ENCODING_PCM_16BIT)
            track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(rate)
                        .setChannelMask(mask)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .build()
                )
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setBufferSizeInBytes(max(min * 2, rate * channels)) // ~0.5 s
                .build()
        }

        fun start() {
            track.setVolume(0f)
            track.play()
            Thread({ run() }, "pad").start()
        }

        fun fadeOut(seconds: Double) {
            from = level
            to = 0f
            fadeDone = 0
            fadeFrames = max(1, (seconds * rate).toInt())
        }

        private fun run() {
            val chunk = 1024 * channels // ~32 ms
            var at = 0
            try {
                while (running) {
                    // Volume for this chunk.
                    fadeDone = minOf(fadeDone + chunk / channels, fadeFrames)
                    val x = fadeDone.toFloat() / fadeFrames
                    level = if (to > from) from + (to - from) * sin(x * PI / 2).toFloat()
                    else to + (from - to) * cos(x * PI / 2).toFloat()
                    track.setVolume(level * master)
                    if (to == 0f && fadeDone >= fadeFrames) break
                    // The loop, around and around.
                    val n = minOf(chunk, pcm.size - at)
                    track.write(pcm, at, n)
                    at += n
                    if (at >= pcm.size) at = 0
                }
            } finally {
                running = false
                try {
                    track.pause()
                    track.flush()
                    track.release()
                } catch (_: Exception) {
                }
            }
        }
    }
}
