package com.timerstopwatch.timerstopwatch

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 后台倒计时悬浮窗：半透明黑底圆角小窗 + 大号时间 + 「标记」按钮 + "✕" 关闭，可拖动。
 * 需要 SYSTEM_ALERT_WINDOW（"显示在其他应用上层"）权限。
 */
object OverlayWindow {
    private var wm: WindowManager? = null
    private var root: View? = null
    private var timeText: TextView? = null
    private var params: WindowManager.LayoutParams? = null

    fun isGranted(context: Context): Boolean = Settings.canDrawOverlays(context)

    /** 打开当前应用的"显示在其他应用上层"设置页。 */
    fun request(context: Context) {
        runCatching {
            context.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    android.net.Uri.parse("package:${context.packageName}")
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    fun show(context: Context, initialText: String) {
        val ctx = context.applicationContext
        if (!isGranted(ctx)) {
            android.util.Log.d("OverlayWin", "show: not granted")
            return
        }
        if (root != null) {
            update(initialText)
            return
        }
        android.util.Log.d("OverlayWin", "show: adding view")
        val windowManager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val density = ctx.resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = ctx.resources.displayMetrics.widthPixels / 2 - dp(70)
            y = dp(80)
        }

        val container = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply {
                setColor(Color.argb(0xB3, 0x00, 0x00, 0x00))
                cornerRadius = dp(20).toFloat()
            }
            // 留白收紧：此前 20/12/8/12，文字同步加大。
            setPadding(dp(14), dp(6), dp(4), dp(6))
        }

        val tv = TextView(ctx).apply {
            text = initialText
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            fontFeatureSettings = "tnum"
        }
        timeText = tv

        // 「标记」按钮：与常驻通知的标记同路（广播 → Flutter 引擎），不打断倒计时。
        val mark = TextView(ctx).apply {
            text = "标记"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            setPadding(dp(10), dp(4), dp(10), dp(4))
            isClickable = true
            setOnClickListener {
                runCatching { ctx.sendBroadcast(Intent(ctx, MarkActionReceiver::class.java)) }
                android.widget.Toast.makeText(ctx, "已标记", android.widget.Toast.LENGTH_SHORT).show()
            }
        }

        val close = TextView(ctx).apply {
            text = "✕"
            setTextColor(Color.argb(0xB3, 0xFF, 0xFF, 0xFF))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            setPadding(dp(10), dp(4), dp(10), dp(4))
            isClickable = true
            setOnClickListener { hide() }
        }

        container.addView(tv, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        container.addView(mark, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        container.addView(close, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))

        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var dragged = false
        container.setOnTouchListener { _, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX; downY = e.rawY
                    startX = p.x; startY = p.y
                    dragged = false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - downX
                    val dy = e.rawY - downY
                    if (kotlin.math.abs(dx) > 10 || kotlin.math.abs(dy) > 10) dragged = true
                    p.x = startX + dx.toInt()
                    p.y = startY + dy.toInt()
                    runCatching { windowManager.updateViewLayout(container, p) }
                }
                MotionEvent.ACTION_UP -> {
                    if (dragged) {
                        runCatching { windowManager.updateViewLayout(container, p) }
                        return@setOnTouchListener true
                    }
                }
            }
            false
        }

        runCatching { windowManager.addView(container, p) }
        wm = windowManager
        root = container
        params = p
    }

    fun update(text: String) {
        timeText?.post { timeText?.text = text }
    }

    fun hide() {
        val view = root
        runCatching { if (view != null) wm?.removeView(view) }
        root = null
        timeText = null
        params = null
    }
}
