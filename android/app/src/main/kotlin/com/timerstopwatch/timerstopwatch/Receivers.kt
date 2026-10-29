package com.timerstopwatch.timerstopwatch

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** 精确闹铃到点：即使进程被杀也能拉起响铃（前台服务 + 全屏通知）。 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("TimerRcv", "alarm fired")
        val ringPath = intent.getStringExtra(TimerService.EXTRA_RING_PATH)
        val vibrate = intent.getBooleanExtra(TimerService.EXTRA_VIBRATE, true)
        val dndLift = intent.getBooleanExtra(TimerService.EXTRA_DND_LIFT, false)
        val service = Intent(context, TimerService::class.java)
            .putExtra(TimerService.EXTRA_MODE, TimerService.MODE_RING)
            .putExtra(TimerService.EXTRA_RING_PATH, ringPath)
            .putExtra(TimerService.EXTRA_VIBRATE, vibrate)
            .putExtra(TimerService.EXTRA_DND_LIFT, dndLift)
        try {
            context.startForegroundService(service)
        } catch (e: Exception) {
            Log.w("TimerRcv", "fgs start failed, ring inline: ${e.message}")
            AlarmRing.start(context, ringPath, vibrate, dndLift)
        }
    }
}

/** 常驻通知上的「标记」按钮：转发给 Flutter 引擎（引擎已死则忽略）。 */
class MarkActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("TimerRcv", "mark action, channel=${MainActivity.dartChannel != null}")
        try {
            MainActivity.dartChannel?.invokeMethod("onNotificationMark", null)
        } catch (e: Exception) {
            Log.w("TimerRcv", "mark forward failed: ${e.message}")
        }
    }
}

/** 响铃通知上的「关闭铃声」按钮。 */
class RingStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("TimerRcv", "ring stop action")
        AlarmRing.stop()
        DndHelper.sessionEnd(context)
        TimerService.stop(context)
        try {
            MainActivity.dartChannel?.invokeMethod("onRingStopped", null)
        } catch (_: Exception) {
        }
    }
}
