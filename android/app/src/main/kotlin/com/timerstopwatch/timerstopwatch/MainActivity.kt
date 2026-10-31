package com.timerstopwatch.timerstopwatch

import android.Manifest
import android.app.AlarmManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.view.WindowManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        dartChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    // ---- 响铃 / 提示音 ----
                    "ringStart" -> {
                        AlarmRing.start(
                            this,
                            call.argument<String>("path"),
                            call.argument<Boolean>("vibrate") ?: true,
                            call.argument<Boolean>("dndLift") ?: false
                        )
                        result.success(null)
                    }
                    "ringStop" -> {
                        AlarmRing.stop()
                        DndHelper.sessionEnd(this)
                        result.success(null)
                    }
                    "soundPlay" -> {
                        AlarmRing.playOnce(
                            this,
                            call.argument<String>("path"),
                            call.argument<Int>("seconds") ?: 5,
                            call.argument<Boolean>("vibrate") ?: false
                        )
                        result.success(null)
                    }
                    // ---- 考试模式音频：assets 拷贝到私有目录并返回路径 ----
                    "ensureExamAudio" -> result.success(ExamAudio.ensure(this))
                    // ---- 前台服务 ----
                    "serviceStart" -> {
                        TimerService.start(
                            this,
                            (call.argument<Number>("endWallMs") ?: 0L).toLong(),
                            (call.argument<Number>("totalMs") ?: 0L).toLong(),
                            (call.argument<Number>("lastMarkMs") ?: -1L).toLong(),
                            call.argument<String>("ringPath"),
                            call.argument<Boolean>("vibrate") ?: true,
                            call.argument<Boolean>("dndLift") ?: false
                        )
                        result.success(null)
                    }
                    "servicePause" -> {
                        TimerService.instance?.setPaused((call.argument<Number>("remainingMs") ?: 0L).toLong())
                        result.success(null)
                    }
                    "serviceResume" -> {
                        TimerService.instance?.setResumed((call.argument<Number>("endWallMs") ?: 0L).toLong())
                        result.success(null)
                    }
                    "serviceLastMark" -> {
                        TimerService.instance?.setLastMark((call.argument<Number>("elapsedMs") ?: 0L).toLong())
                        result.success(null)
                    }
                    "serviceStop" -> {
                        TimerService.stop(this)
                        result.success(null)
                    }
                    // ---- 滚轮逐格反馈：线性马达 + 咔哒声 ----
                    "wheelTick" -> {
                        WheelFeedback.tick(this)
                        result.success(null)
                    }
                    // ---- 悬浮窗 ----
                    "overlayShow" -> {
                        OverlayWindow.show(
                            this,
                            (call.argument<Number>("remainingMs") ?: 0L).toLong(),
                            (call.argument<Number>("totalMs") ?: 0L).toLong()
                        )
                        result.success(null)
                    }
                    "overlayHide" -> {
                        OverlayWindow.hide()
                        result.success(null)
                    }
                    "overlayGranted" -> result.success(OverlayWindow.isGranted(this))
                    "overlayRequest" -> {
                        OverlayWindow.request(this)
                        result.success(null)
                    }
                    // ---- 权限 ----
                    "notifGranted" -> result.success(notificationsEnabled())
                    "notifRequest" -> requestNotificationPermission(result)
                    "exactGranted" -> result.success(canScheduleExact())
                    "exactRequest" -> {
                        runCatching {
                            startActivity(
                                Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName"))
                            )
                        }
                        result.success(null)
                    }
                    // ---- 勿扰 ----
                    "dndGranted" -> result.success(DndHelper.isGranted(this))
                    "dndRequest" -> {
                        DndHelper.request(this)
                        result.success(null)
                    }
                    "dndSessionStart" -> {
                        DndHelper.sessionStart(this)
                        result.success(null)
                    }
                    "dndSessionRestart" -> {
                        DndHelper.sessionRestart(this)
                        result.success(null)
                    }
                    "dndSessionEnd" -> {
                        DndHelper.sessionEnd(this)
                        result.success(null)
                    }
                    // ---- 假睡眠：窗口亮度 ----
                    "brightnessSet" -> {
                        val v = (call.argument<Number>("value") ?: 0.15).toDouble()
                        window.attributes = window.attributes.apply { screenBrightness = v.toFloat() }
                        result.success(null)
                    }
                    "brightnessReset" -> {
                        window.attributes = window.attributes.apply { screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE }
                        result.success(null)
                    }
                    // ---- 桌面图标随主题配色切换（activity-alias 启停） ----
                    "setIcon" -> {
                        setLauncherAlias(call.argument<String>("key") ?: "lightpurple")
                        result.success(null)
                    }
                    // ---- 音频导入 ----
                    "pickAudio" -> pickAudio(result)
                    "deleteAudio" -> {
                        val path = call.argument<String>("path")
                        if (path != null) runCatching { File(path).delete() }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        OverlayWindow.hide()
        super.onDestroy()
    }

    // ---------- 桌面图标：activity-alias 启停 ----------

    /**
     * 每套主题配色一个 alias（alias_<key>，各自指向专属图标资源），同一时刻只启用一个。
     * DONT_KILL_APP：切换时进程不重启（正在计时/前台服务不受影响）。
     *
     * 键大小写不敏感（Dart 枚举 name 为驼峰 lightPurple，资源键为小写 lightpurple）；
     * 未知键一律回落 lightpurple——任何输入都必须保证留有一个可启动的桌面入口。
     * 顺序：先启用目标、再禁用其余——过渡期桌面始终有可用入口，降低任务被系统收掉的概率
     * （Dart 侧另把切换时机延迟到应用退后台，见 NavShell._pendingIconKey）。
     */
    private fun setLauncherAlias(rawKey: String) {
        val key = ICON_KEYS.firstOrNull { it.equals(rawKey, ignoreCase = true) } ?: "lightpurple"
        val pm = packageManager
        fun setEnabled(k: String, enabled: Boolean) {
            pm.setComponentEnabledSetting(
                ComponentName(this, "$packageName.alias_$k"),
                if (enabled)
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
        }
        setEnabled(key, true)
        for (k in ICON_KEYS) {
            if (k != key) setEnabled(k, false)
        }
    }

    // ---------- 权限 ----------

    private fun notificationsEnabled(): Boolean =
        androidx.core.app.NotificationManagerCompat.from(this).areNotificationsEnabled()

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= 33) {
            if (notificationsEnabled()) {
                result.success(true)
                return
            }
            pendingResult = result
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), RC_NOTIF)
        } else {
            result.success(notificationsEnabled())
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == RC_NOTIF) {
            pendingResult?.success(notificationsEnabled())
            pendingResult = null
        }
    }

    private fun canScheduleExact(): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        val am = getSystemService(AlarmManager::class.java) ?: return true
        return am.canScheduleExactAlarms()
    }

    // ---------- 音频导入（ACTION_OPEN_DOCUMENT → 拷贝到应用私有目录） ----------

    private fun pickAudio(result: MethodChannel.Result) {
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        runCatching {
            startActivityForResult(Intent.createChooser(intent, "选择音频文件"), RC_PICK_AUDIO)
        }.onFailure {
            pendingResult?.success(null)
            pendingResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != RC_PICK_AUDIO) return
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            pendingResult?.success(null)
            pendingResult = null
            return
        }
        val copied = runCatching { copyAudioToPrivate(uri) }.getOrNull()
        pendingResult?.success(copied)
        pendingResult = null
    }

    private fun copyAudioToPrivate(uri: Uri): String? {
        val dir = File(filesDir, "audio").apply { mkdirs() }
        val ext = queryExtension(uri) ?: "audio"
        val target = File(dir, "audio_${System.currentTimeMillis()}.$ext")
        contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        } ?: return null
        return target.absolutePath
    }

    private fun queryExtension(uri: Uri): String? {
        runCatching {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIdx >= 0 && cursor.moveToFirst()) {
                    val name = cursor.getString(nameIdx) ?: return null
                    val dot = name.lastIndexOf('.')
                    if (dot in 0 until name.length - 1) return name.substring(dot + 1).lowercase()
                }
            }
        }
        return contentResolver.getType(uri)?.substringAfterLast('/')
    }

    companion object {
        const val CHANNEL = "timerstopwatch/app"
        const val RC_NOTIF = 200
        const val RC_PICK_AUDIO = 201

        /** 桌面图标 alias 键集合（与 Dart 侧 AppPalette.name 一一对应）。 */
        val ICON_KEYS = listOf("lightpurple", "deeppurple", "cyan", "yellow", "lightblue", "pink", "green")

        @Volatile
        var dartChannel: MethodChannel? = null
    }
}
