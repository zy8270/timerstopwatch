package com.timerstopwatch.timerstopwatch

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import java.io.File

/**
 * 结束响铃 / 提示音播放：系统闹铃声或自定义音频，USAGE_ALARM 声道（勿扰下仍可响）。
 * 进程内单例，Dart 通道与前台服务 / 闹铃广播共用。
 */
object AlarmRing {
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private val handler = Handler(Looper.getMainLooper())
    private var oneShotStop: Runnable? = null

    /** 循环响铃（倒计时结束），直至 [stop]。 */
    fun start(context: Context, customPath: String?, vibrate: Boolean, dndLift: Boolean) {
        if (dndLift) DndHelper.ringLift(context)
        stop()
        val ctx = context.applicationContext
        player = MediaPlayer().apply {
            runCatching {
                val uri = pickUri(customPath, RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                setDataSource(ctx, uri)
            }.onFailure {
                runCatching { setDataSource(ctx, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)) }
            }
            setAudioAttributes(alarmAttributes())
            isLooping = true
            runCatching { prepare(); start() }
        }
        if (vibrate) startVibration(ctx)
    }

    /** 播放一遍提示音（剩余提醒），[seconds] 秒后自动停止。 */
    fun playOnce(context: Context, customPath: String?, seconds: Int, vibrate: Boolean) {
        stop()
        val ctx = context.applicationContext
        player = MediaPlayer().apply {
            runCatching {
                val uri = pickUri(customPath, RingtoneManager.TYPE_NOTIFICATION)
                if (uri != null) setDataSource(ctx, uri)
            }
            setAudioAttributes(alarmAttributes())
            isLooping = false
            runCatching { prepare(); start() }
        }
        if (vibrate) {
            vibrator = ctx.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 200), -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(200)
            }
        }
        val stopper = Runnable { stop() }
        oneShotStop = stopper
        handler.postDelayed(stopper, seconds * 1000L)
    }

    private fun pickUri(customPath: String?, defaultType: Int): Uri? {
        if (!customPath.isNullOrEmpty() && File(customPath).exists()) return Uri.fromFile(File(customPath))
        return RingtoneManager.getDefaultUri(defaultType)
    }

    private fun alarmAttributes(): AudioAttributes =
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

    private fun startVibration(ctx: Context) {
        vibrator = ctx.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator ?: return
        val pattern = longArrayOf(0, 600, 400)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    fun stop() {
        oneShotStop?.let { handler.removeCallbacks(it) }
        oneShotStop = null
        runCatching {
            player?.let { if (it.isPlaying) it.stop() }
            player?.release()
        }
        player = null
        vibrator?.cancel()
        vibrator = null
    }
}
