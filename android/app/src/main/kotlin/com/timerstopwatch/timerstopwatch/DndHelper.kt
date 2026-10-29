package com.timerstopwatch.timerstopwatch

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.provider.Settings

/**
 * 勿扰模式助手：需用户授予"勿扰访问权限"（ACCESS_NOTIFICATION_POLICY）。
 * 会话开始保存原状态并开启优先级勿扰；响铃前可临时解除；会话结束恢复原状。
 */
object DndHelper {
    private var previousFilter = NotificationManager.INTERRUPTION_FILTER_ALL
    private var sessionActive = false

    fun isGranted(context: Context): Boolean {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return false
        return nm.isNotificationPolicyAccessGranted
    }

    /** 打开系统的"勿扰访问权限"设置页。 */
    fun request(context: Context) {
        runCatching {
            context.startActivity(
                Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    /** 倒计时开始：保存当前勿扰状态并开启"仅限优先事项"勿扰。 */
    fun sessionStart(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (!nm.isNotificationPolicyAccessGranted) return
        val current = nm.currentInterruptionFilter
        if (current != NotificationManager.INTERRUPTION_FILTER_ALL) {
            previousFilter = current
        } else {
            previousFilter = NotificationManager.INTERRUPTION_FILTER_ALL
        }
        runCatching { nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY) }
        sessionActive = true
    }

    /** "响铃前临时解除勿扰"开关：确保结束铃声可闻。 */
    fun ringLift(context: Context) {
        if (!sessionActive) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        runCatching { nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL) }
    }

    /**
     * 进程被杀后恢复计时会话时重新接管勿扰：先把勿扰复位为"全部"再开始会话，
     * 保证 previousFilter 记录的是干净基线——否则会话结束时会把"优先级勿扰"
     * 当作原状恢复回去，导致勿扰永远卡在开启状态。
     */
    fun sessionRestart(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (!nm.isNotificationPolicyAccessGranted) return
        runCatching { nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL) }
        sessionStart(context)
    }

    /** 倒计时结束 / 取消 / 响铃关闭：恢复会话前的勿扰状态。 */
    fun sessionEnd(context: Context) {
        if (!sessionActive) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        runCatching { nm.setInterruptionFilter(previousFilter) }
        sessionActive = false
    }
}
