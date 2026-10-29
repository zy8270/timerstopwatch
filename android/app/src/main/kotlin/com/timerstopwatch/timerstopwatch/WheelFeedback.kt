package com.timerstopwatch.timerstopwatch

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * 滚轮逐格反馈：数字每变化一格 → 线性马达轻震（EFFECT_TICK，API 29+，无则弱波形兜底）
 * + 波轮"咔哒"声（res/raw/wheel_tick.wav，SoundPool 短音，走系统音效声道跟随系统音量）。
 */
object WheelFeedback {
    private var soundPool: SoundPool? = null
    private var tickId = 0

    fun tick(context: Context) {
        vibrate(context)
        playTick(context)
    }

    private fun vibrator(context: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

    private fun vibrate(context: Context) {
        val v = vibrator(context) ?: return
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                v.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK))
            } else {
                v.vibrate(VibrationEffect.createOneShot(10, VibrationEffect.DEFAULT_AMPLITUDE))
            }
        }
    }

    private fun playTick(context: Context) {
        val sp = soundPool ?: SoundPool.Builder()
            .setMaxStreams(1)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .build()
            .also {
                soundPool = it
                tickId = it.load(context, R.raw.wheel_tick, 1)
            }
        sp.play(tickId, 0.7f, 0.7f, 1, 0, 1f)
    }
}
