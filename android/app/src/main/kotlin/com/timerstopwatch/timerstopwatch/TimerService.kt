package com.timerstopwatch.timerstopwatch

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * 倒计时前台服务：
 * - 运行模式：常驻通知实时显示剩余时间 + 距上次标记时长 + 「标记」按钮；注册精确闹铃兜底。
 * - 响铃模式：倒计时结束（前台/后台/进程被杀三种路径统一到这里），循环铃声 + 震动 + 全屏通知。
 */
class TimerService : Service() {

    private val handler = Handler(Looper.getMainLooper())

    private var mode = MODE_RUN
    private var endWall = 0L
    private var totalMs = 0L
    private var paused = false
    private var pausedRemainingMs = 0L
    private var lastMarkElapsedMs = -1L
    private var ringPath: String? = null
    private var vibrate = true
    private var dndLift = false

    private val ticker = object : Runnable {
        override fun run() {
            onTick()
            handler.postDelayed(this, 1000L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        when (intent.getStringExtra(EXTRA_MODE) ?: MODE_RUN) {
            MODE_RING -> {
                ringPath = intent.getStringExtra(EXTRA_RING_PATH)
                vibrate = intent.getBooleanExtra(EXTRA_VIBRATE, true)
                dndLift = intent.getBooleanExtra(EXTRA_DND_LIFT, false)
                enterRingMode()
            }
            else -> {
                endWall = intent.getLongExtra(EXTRA_END_WALL, 0L)
                totalMs = intent.getLongExtra(EXTRA_TOTAL, 0L)
                paused = intent.getBooleanExtra(EXTRA_PAUSED, false)
                pausedRemainingMs = intent.getLongExtra(EXTRA_PAUSED_REMAINING, 0L)
                lastMarkElapsedMs = intent.getLongExtra(EXTRA_LAST_MARK, -1L)
                ringPath = intent.getStringExtra(EXTRA_RING_PATH)
                vibrate = intent.getBooleanExtra(EXTRA_VIBRATE, true)
                dndLift = intent.getBooleanExtra(EXTRA_DND_LIFT, false)
                mode = MODE_RUN
                Log.d(TAG, "runMode endWall=$endWall total=$totalMs paused=$paused")
                startAsForeground(buildCountdownNotification())
                if (!paused) {
                    scheduleAlarm(endWall)
                    handler.removeCallbacks(ticker)
                    handler.post(ticker)
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        instance = null
        handler.removeCallbacks(ticker)
        OverlayWindow.hide()
        super.onDestroy()
    }

    private fun onTick() {
        if (mode != MODE_RUN || paused) return
        val remaining = endWall - System.currentTimeMillis()
        if (remaining <= 0) {
            enterRingMode()
        } else {
            val n = buildCountdownNotification()
            val nm = getSystemService(NotificationManager::class.java)
            nm?.notify(ID_COUNTDOWN, n)
            OverlayWindow.update(formatMs(remaining))
        }
    }

    private fun enterRingMode() {
        Log.d(TAG, "enterRing")
        handler.removeCallbacks(ticker)
        mode = MODE_RING
        cancelAlarm()
        // 倒计时结束：悬浮窗随之下线（计划第四节：结束时悬浮窗关闭）。
        OverlayWindow.hide()
        AlarmRing.start(this, ringPath, vibrate, dndLift)
        startAsForeground(buildRingNotification())
    }

    // ---------- Dart 侧经 MainActivity 转发的状态更新 ----------

    fun setPaused(remainingMs: Long) {
        paused = true
        pausedRemainingMs = remainingMs
        cancelAlarm()
        val nm = getSystemService(NotificationManager::class.java)
        nm?.notify(ID_COUNTDOWN, buildCountdownNotification())
    }

    fun setResumed(endWallMs: Long) {
        paused = false
        endWall = endWallMs
        scheduleAlarm(endWall)
        val nm = getSystemService(NotificationManager::class.java)
        nm?.notify(ID_COUNTDOWN, buildCountdownNotification())
        handler.removeCallbacks(ticker)
        handler.post(ticker)
    }

    fun setLastMark(elapsedMs: Long) {
        lastMarkElapsedMs = elapsedMs
        if (mode == MODE_RUN) {
            val nm = getSystemService(NotificationManager::class.java)
            nm?.notify(ID_COUNTDOWN, buildCountdownNotification())
        }
    }

    // ---------- 通知 ----------

    private fun currentRemainingMs(): Long =
        if (paused) pausedRemainingMs else endWall - System.currentTimeMillis()

    private fun notificationText(): String {
        val remaining = currentRemainingMs().coerceAtLeast(0)
        val sb = StringBuilder("剩余 ")
        sb.append(formatMs(remaining))
        val elapsed = (totalMs - remaining).coerceAtLeast(0)
        sb.append(" · ")
        if (lastMarkElapsedMs >= 0 && elapsed >= lastMarkElapsedMs) {
            sb.append("距上次标记 ")
            sb.append(formatMs(elapsed - lastMarkElapsedMs))
        } else {
            sb.append("已进行 ")
            sb.append(formatMs(elapsed))
        }
        return sb.toString()
    }

    private fun buildCountdownNotification(): Notification {
        val markIntent = PendingIntent.getBroadcast(
            this, RC_MARK,
            Intent(this, MarkActionReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CH_COUNTDOWN)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(if (paused) "倒计时已暂停" else "倒计时进行中")
            .setContentText(notificationText())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(contentIntent())
            .addAction(0, "标记", markIntent)
            .build()
    }

    private fun buildRingNotification(): Notification {
        val stopIntent = PendingIntent.getBroadcast(
            this, RC_RING_STOP,
            Intent(this, RingStopReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CH_RING)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("倒计时结束")
            .setContentText("点击关闭铃声")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(contentIntent(), true)
            .setContentIntent(contentIntent())
            .addAction(0, "关闭铃声", stopIntent)
            .build()
    }

    private fun contentIntent(): PendingIntent? {
        val launch = packageManager?.getLaunchIntentForPackage(packageName) ?: return null
        return PendingIntent.getActivity(
            this, RC_CONTENT, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun startAsForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(ID_COUNTDOWN, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(ID_COUNTDOWN, notification)
        }
    }

    private fun createChannels() {
        val nm = getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(
            NotificationChannel(CH_COUNTDOWN, "倒计时", NotificationManager.IMPORTANCE_LOW).apply {
                description = "倒计时进行中的常驻通知"
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CH_RING, "结束响铃", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "倒计时结束的闹铃通知"
            }
        )
    }

    // ---------- 精确闹铃（进程被杀后的兜底） ----------

    private fun alarmPendingIntent(): PendingIntent {
        val intent = Intent(this, AlarmReceiver::class.java)
            .putExtra(EXTRA_RING_PATH, ringPath)
            .putExtra(EXTRA_VIBRATE, vibrate)
            .putExtra(EXTRA_DND_LIFT, dndLift)
        return PendingIntent.getBroadcast(
            this, RC_ALARM, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun scheduleAlarm(endWallMs: Long) {
        val am = getSystemService(AlarmManager::class.java) ?: return
        val show = contentIntent()
        val info = AlarmManager.AlarmClockInfo(endWallMs, show)
        am.setAlarmClock(info, alarmPendingIntent())
    }

    private fun cancelAlarm() {
        val am = getSystemService(AlarmManager::class.java) ?: return
        am.cancel(alarmPendingIntent())
    }

    companion object {
        const val CH_COUNTDOWN = "timer_countdown"
        const val CH_RING = "timer_ring"
        const val ID_COUNTDOWN = 100
        const val RC_MARK = 101
        const val RC_RING_STOP = 102
        const val RC_CONTENT = 103
        const val RC_ALARM = 104

        const val EXTRA_MODE = "mode"
        const val MODE_RUN = "run"
        const val MODE_RING = "ring"
        const val EXTRA_END_WALL = "endWall"
        const val EXTRA_TOTAL = "total"
        const val EXTRA_PAUSED = "paused"
        const val EXTRA_PAUSED_REMAINING = "pausedRemaining"
        const val EXTRA_LAST_MARK = "lastMark"
        const val EXTRA_RING_PATH = "ringPath"
        const val EXTRA_VIBRATE = "vibrate"
        const val EXTRA_DND_LIFT = "dndLift"
        const val TAG = "TimerSvc"

        @Volatile
        var instance: TimerService? = null

        fun start(
            context: Context,
            endWall: Long,
            totalMs: Long,
            lastMarkElapsedMs: Long,
            ringPath: String?,
            vibrate: Boolean,
            dndLift: Boolean
        ) {
            val intent = Intent(context, TimerService::class.java)
                .putExtra(EXTRA_MODE, MODE_RUN)
                .putExtra(EXTRA_END_WALL, endWall)
                .putExtra(EXTRA_TOTAL, totalMs)
                .putExtra(EXTRA_LAST_MARK, lastMarkElapsedMs)
                .putExtra(EXTRA_RING_PATH, ringPath)
                .putExtra(EXTRA_VIBRATE, vibrate)
                .putExtra(EXTRA_DND_LIFT, dndLift)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, TimerService::class.java))
        }

        /** 输入毫秒，输出 mm:ss 或 h:mm:ss。 */
        fun formatMs(ms: Long): String {
            val totalSec = ms / 1000
            val h = totalSec / 3600
            val m = totalSec % 3600 / 60
            val s = totalSec % 60
            return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
        }
    }
}
