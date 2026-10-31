package com.timerstopwatch.timerstopwatch

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 后台倒计时悬浮窗（需要 SYSTEM_ALERT_WINDOW）：
 * - 完整形态：半透明黑底圆角小窗，行布局 [标记按钮(圆角底) | 大号时间 | ✕]；
 *   上下留白与左留白一致（行容器 6dp，时间文字去行距/竖直 padding）。
 * - 整窗任意位置可拖动（含按钮上）；点击「时间」→「返回计时器」灰色半透明药丸
 *   **Z 轴悬浮盖在时间正上方**（时间隐约透出，窗口位置尺寸完全不动），点击拉起
 *   应用，6 秒无操作自动淡出。
 * - 贴边交互（v3.17，v3.20 补拖离还原）：拖动中距屏幕左右边缘 ≤10px 时，**整个悬浮窗
 *   内容原地变成纵向进度条预览**（上半灰=已流逝、下半彩色=剩余，窗口形状不变）——提示
 *   用户此时松手会贴边；拖出区域即恢复。松手在区域内 → 收起为贴边进度条（高=悬浮窗
 *   高度、宽=标记按钮高度）；**贴边条再被拖离边缘时原地长回悬浮窗**（朝屏幕内侧生长，
 *   围绕手指、贴边那侧不跳），松手即保持完整形态。
 * - 点击贴边条 → 展开回原位：**单段对称缓动（AccelerateDecelerate）**，窗口宽/高/位置
 *   四元同帧补间，条淡出与窗淡入交叉过渡——修掉了旧版"先长成满宽窗、再挪一小步、
 *   末尾停住"的突兀观感（旧 Decelerate 前 25% 时间就走完 44% 距离）。
 * - 位置记忆（v3.21）：用户拖动后的落点存 SharedPreferences（overlay_window/pos_x,pos_y），
 *   下次弹出还原；**只有自由放置才记录**——拖到边缘收起是临时贴边姿态，不覆盖记忆值。
 *   首次（无记录）默认水平居中、竖直中心在屏幕 3/4 高度（覆盖层 y 相对状态栏下方父区域，
 *   须补 statusBarInset 才是整屏比例）。
 * - 进度条填充为**方形色块经圆角背景遮罩裁剪**（不随高度缩小圆角，避免"压扁的
 *   鸡蛋"）；填充锚定底部，剩余随时间从上往下减小；颜色随剩余持续渐变
 *   绿→黄→红。
 * - 数据：TimerService 每秒推 剩余/总时长 毫秒值（update），进度条与时间文本同源。
 */
object OverlayWindow {
    private var wm: WindowManager? = null
    private var root: FrameLayout? = null
    private var fullView: LinearLayout? = null
    private var previewBar: VerticalProgressView? = null
    private var barView: VerticalProgressView? = null
    private var timeText: TextView? = null
    private var markView: TextView? = null
    private var closeView: TextView? = null
    private var backBtn: TextView? = null
    private var params: WindowManager.LayoutParams? = null

    /// 窗口补间（Choreographer 自驱动）的存活哨兵：null = 不在播（被 hide/触摸接管）。
    private var tweenToken: Any? = null

    /// 窗口宽高是否被锁成固定 px（收起条尺寸 / 展开中途）。触摸接管时恢复 WRAP_CONTENT。
    private var lockedSize = false

    /// 拖离边缘触发的长回（位置跟手）进行中；手指位置与纵向抓取偏移。
    private var dragExpand = false
    private var dragFingerX = 0f
    private var dragFingerY = 0f
    private var dragGrabDy = 0f
    /// 本手势内条已长回成窗（松手不再判定吸附）。
    private var dragExpanded = false
    /// 条贴右边：长回时保持右边缘跟随手指（窗口向左生长）。
    private var dragAnchorRight = false
    private var dragAnchorDx = 0f

    private val mainHandler = Handler(Looper.getMainLooper())
    private var density = 1f
    private var remainingMs = 0L
    private var totalMs = 0L
    private var collapsed = false
    private var previewActive = false
    private var paused = false
    /// 收起前悬浮窗的尺寸（展开目标）与位置（clamp 后的展开落点）。
    private var fullWpx = 0
    private var fullHpx = 0
    private var lastFullX = 0
    private var lastFullY = 0
    /// 贴边条尺寸（收起时定下，展开动画的起点）。
    private var barWpx = 0
    private var barHpx = 0

    /** 贴边吸附阈值：距屏幕左右边缘不足此像素数时进入"松手即贴边"状态（预览+收起）。 */
    private const val EDGE_SNAP_PX = 10
    private const val BAR_WIDTH_FALLBACK_DP = 32
    private const val BAR_HEIGHT_FALLBACK_DP = 140
    private const val BACK_BTN_AUTO_HIDE_MS = 2000L

    private fun dp(v: Int) = (v * density).toInt()

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
    fun show(context: Context, initialRemainingMs: Long, initialTotalMs: Long) {
        val ctx = context.applicationContext
        if (!isGranted(ctx)) {
            android.util.Log.d("OverlayWin", "show: not granted")
            return
        }
        remainingMs = initialRemainingMs
        totalMs = initialTotalMs
        if (root != null) {
            update(initialRemainingMs, initialTotalMs)
            return
        }
        android.util.Log.d("OverlayWin", "show: adding view")
        val windowManager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        density = ctx.resources.displayMetrics.density

        // ---- 行：[标记] [时间槽] [✕] ----
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply {
                setColor(Color.argb(0xB3, 0x00, 0x00, 0x00))
                cornerRadius = dp(20).toFloat()
            }
            setPadding(dp(6), dp(6), dp(4), dp(6))
        }

        timeText = TextView(ctx).apply {
            text = TimerService.formatMs(initialRemainingMs)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            fontFeatureSettings = "tnum"
            // 紧凑行高：去掉字体的上下行距留白与自身竖直 padding——
            // 窗口上下留白只剩行容器的 6dp（与左侧到「标记」的留白一致）。
            includeFontPadding = false
            // 横向 6dp：收紧与「标记」/「✕」的间距（v3.18，✕ 居中于右侧空间）。
            setPadding(dp(6), 0, dp(6), 0)
        }

        // 「返回计时器」：Z 轴悬浮盖在时间正上方（同槽居中），窗口不动。
        // 尺寸控制在时间文字宽度以内（12sp + 小 padding），避免比时间宽而撑大窗口。
        backBtn = TextView(ctx).apply {
            text = "返回计时器"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            maxLines = 1
            background = GradientDrawable().apply {
                setColor(Color.argb(0x99, 0x55, 0x55, 0x55))
                cornerRadius = dp(14).toFloat()
            }
            setPadding(dp(8), dp(5), dp(8), dp(5))
            visibility = View.GONE
        }

        // 时间槽：时间文字 + 覆盖其上的返回按钮（同槽层叠）。
        val timeSlot = FrameLayout(ctx).apply {
            addView(timeText, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT))
            addView(backBtn, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
        }

        // 「标记」按钮：圆角半透明底；与常驻通知的标记同路（广播 → Flutter 引擎），不打断倒计时。
        markView = TextView(ctx).apply {
            text = "标记"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            includeFontPadding = false
            background = GradientDrawable().apply {
                setColor(Color.argb(0x4D, 0xFF, 0xFF, 0xFF))
                cornerRadius = dp(14).toFloat()
            }
            setPadding(dp(12), dp(6), dp(12), dp(6))
        }

        // ✕：竖直方向与时间同样去行距留白，视觉居中于行内；左 8dp/右 10dp——
        // 时间尾 6dp + 左 8dp = 14dp，右 10dp + 行容器 4dp = 14dp，✕ 恰在右侧空间正中。
        val close = TextView(ctx).apply {
            text = "✕"
            setTextColor(Color.argb(0xB3, 0xFF, 0xFF, 0xFF))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            includeFontPadding = false
            setPadding(dp(8), 0, dp(10), 0)
        }
        closeView = close

        row.addView(markView, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        row.addView(timeSlot, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        row.addView(close, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))

        fullView = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            addView(row, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        }

        // 贴边预览条：拖动进入吸附区时，整个窗口内容（原尺寸）变成进度条。
        previewBar = VerticalProgressView(ctx).apply {
            cornerRadiusDp = 20f
            visibility = View.GONE
            fraction = if (totalMs > 0) remainingMs.toFloat() / totalMs else 0f
        }

        // 贴边收起后的进度条：高=悬浮窗高、宽=标记按钮高（collapse 时动态设置尺寸）。
        barView = VerticalProgressView(ctx).apply {
            visibility = View.GONE
            fraction = if (totalMs > 0) remainingMs.toFloat() / totalMs else 0f
        }

        val frame = FrameLayout(ctx).apply {
            addView(fullView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT))
            addView(previewBar, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
            addView(barView, FrameLayout.LayoutParams(dp(BAR_WIDTH_FALLBACK_DP), dp(BAR_HEIGHT_FALLBACK_DP)))
        }

        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }

        // 先量出真实内容尺寸：窗口是 WRAP_CONTENT，默认位置与"贴边 clamp"都必须按真实
        // 宽高算（旧代码用 dp(70) 估算，默认位置实际是偏左的）。量好再定位，避免首帧跳位。
        frame.measure(
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        val winW = frame.measuredWidth.coerceAtLeast(1)
        val winH = frame.measuredHeight.coerceAtLeast(1)
        val screenW = ctx.resources.displayMetrics.widthPixels
        val screenH = ctx.resources.displayMetrics.heightPixels
        // 位置：优先还原用户上次拖动后记住的落点；首次（无记录）默认水平居中、
        // 竖直中心位于屏幕 3/4 高度。
        // 注意覆盖层窗口的 y 是相对"状态栏下方父区域"的（被状态栏内缩），
        // 要落到整屏 3/4 需把状态栏高度补回来，否则会低约 5%。
        val savedPos = loadPosition(ctx)
        val defX = savedPos?.first ?: ((screenW - winW) / 2)
        val defY = savedPos?.second
            ?: (screenH * 3 / 4 - winH / 2 - statusBarInset(ctx))
        // 与拖动时的 clamp 口径一致，避免还原到越界位置。
        p.x = defX.coerceIn(0, (screenW - dp(24)).coerceAtLeast(0))
        p.y = defY.coerceIn(0, (screenH - dp(240)).coerceAtLeast(0))

        // 整窗单一触摸处理：按钮不各自消费事件——任何位置（含标记/✕上）都能拖动；
        // 松手时按命中区域分发点击（标记/时间/✕/返回按钮/进度条）。
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var dragged = false
        frame.setOnTouchListener { _, e ->
            val pp = params ?: return@setOnTouchListener false
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    // 补间播到一半被按住：就地落定（恢复自适应尺寸），后续拖动/点击接管。
                    cancelTween()
                    downX = e.rawX; downY = e.rawY
                    startX = pp.x; startY = pp.y
                    dragged = false
                    dragExpanded = false
                    dragGrabDy = e.rawY - pp.y
                    // 收起条贴的是哪一边：长回时朝屏幕内侧展开（右边缘贴着手指、
                    // 窗口向左长；左边缘反之），松手才不会又落回吸附区。
                    dragAnchorRight = collapsed &&
                        (pp.x + frame.width) >= frame.resources.displayMetrics.widthPixels - EDGE_SNAP_PX
                    dragAnchorDx = if (dragAnchorRight) {
                        (pp.x + frame.width) - e.rawX
                    } else {
                        e.rawX - pp.x
                    }
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - downX
                    val dy = e.rawY - downY
                    if (!dragged && (kotlin.math.abs(dx) > dp(6) || kotlin.math.abs(dy) > dp(6))) dragged = true
                    if (dragged) {
                        dragFingerX = e.rawX
                        dragFingerY = e.rawY
                        if (collapsed) {
                            // 还在吸附区：整条可沿边缘上下滑动。
                            if (edgeZone(frame) != null) {
                                pp.x = clampX(startX + dx.toInt(), frame)
                                pp.y = clampY(startY + dy.toInt(), frame)
                                runCatching { windowManager.updateViewLayout(frame, pp) }
                            } else {
                                // 拖离吸附区 → 原地长回悬浮窗（尺寸补间，位置跟手）。
                                dragExpanded = true
                                expand(fromDrag = true)
                            }
                        } else if (dragExpanded) {
                            // 长回过程中及之后：位置始终按锚点公式跟手（不能用 startX+dx，
                            // 那是条的坐标，会让窗口跳回条的位置）。
                            applyDragAnchorPosition(frame, pp)
                            if (!dragExpand) runCatching { windowManager.updateViewLayout(frame, pp) }
                        } else if (!dragExpand) {
                            pp.x = clampX(startX + dx.toInt(), frame)
                            pp.y = clampY(startY + dy.toInt(), frame)
                            runCatching { windowManager.updateViewLayout(frame, pp) }
                            updateEdgePreview(frame)
                        }
                    }
                }
                MotionEvent.ACTION_UP -> {
                    if (dragged) {
                        // 松手位置是否落在吸附区（拖离长回的情况不算，那条早已离开边缘）。
                        val inZone = !dragExpanded && edgeZone(frame) != null
                        // 本手势里条刚长回成窗：松手不再判定吸附（否则会立刻缩回条）。
                        if (!dragExpanded) maybeCollapse(frame)
                        // 只在"自由放置"时记住落点；拖到边缘收起是临时贴边姿态，
                        // 不能覆盖用户上次选的悬浮位置（否则下次弹出被挤在边上）。
                        if (!inZone) savePosition(pp.x, pp.y)
                        return@setOnTouchListener true
                    }
                    handleTap(e.rawX, e.rawY)
                }
            }
            true
        }

        runCatching { windowManager.addView(frame, p) }
        wm = windowManager
        root = frame
        params = p
        frame.post {
            if (root === frame && !collapsed) {
                fullWpx = frame.width
                fullHpx = frame.height
            }
        }
    }

    // ---------- 位置持久化：记住用户拖到的落点，下次弹出还原 ----------

    private const val PREFS = "overlay_window"
    private const val KEY_X = "pos_x"
    private const val KEY_Y = "pos_y"
    private const val NO_POS = -1

    /**
     * 覆盖层窗口的 y 坐标是相对"状态栏下方父区域"的（父区域顶边 = 状态栏高度），
     * 要按整屏高度算位置时必须补回这段偏移。取不到时按 24dp 兜底。
     */
    private fun statusBarInset(ctx: Context): Int {
        val id = ctx.resources.getIdentifier("status_bar_height", "dimen", "android")
        if (id > 0) {
            val h = runCatching { ctx.resources.getDimensionPixelSize(id) }.getOrDefault(0)
            if (h > 0) return h
        }
        return dp(24)
    }

    /** 读上次保存的完整窗左上角；无记录（首次）返回 null。 */
    private fun loadPosition(ctx: Context): Pair<Int, Int>? {
        val sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val x = sp.getInt(KEY_X, NO_POS)
        val y = sp.getInt(KEY_Y, NO_POS)
        return if (x == NO_POS || y == NO_POS) null else x to y
    }

    private fun savePosition(x: Int, y: Int) {
        val ctx = root?.context ?: return
        runCatching {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putInt(KEY_X, x).putInt(KEY_Y, y).apply()
        }
    }

    // ---------- 点击分发（整窗触摸的松手命中） ----------

    private fun handleTap(rawX: Float, rawY: Float) {
        if (collapsed) {
            expand()
            return
        }
        if (hit(backBtn, rawX, rawY)) {
            hideBackBtn()
            if (paused) resumeTimer() else launchApp()
        } else if (hit(timeText, rawX, rawY)) {
            if (backBtn?.visibility == View.VISIBLE) hideBackBtn() else showBackBtn()
        } else if (hit(markView, rawX, rawY)) {
            mark()
        } else if (hit(closeView, rawX, rawY)) {
            hide()
        } else if (backBtn?.visibility == View.VISIBLE) {
            hideBackBtn()
        }
    }

    private fun hit(v: View?, rawX: Float, rawY: Float): Boolean {
        if (v == null || v.visibility != View.VISIBLE || v.width == 0) return false
        val loc = IntArray(2)
        v.getLocationOnScreen(loc)
        return rawX >= loc[0] && rawX <= loc[0] + v.width && rawY >= loc[1] && rawY <= loc[1] + v.height
    }

    private fun mark() {
        val ctx = root?.context ?: return
        runCatching { ctx.sendBroadcast(Intent(ctx, MarkActionReceiver::class.java)) }
        android.widget.Toast.makeText(ctx, "已标记", android.widget.Toast.LENGTH_SHORT).show()
    }

    private fun launchApp() {
        val ctx = root?.context ?: return
        runCatching {
            val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName) ?: return
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(launch)
        }
    }

    /** 「继续计时」：经 MainActivity.dartChannel 回调 Dart 侧 resume（引擎不在则静默失败）。 */
    private fun resumeTimer() {
        runCatching { MainActivity.dartChannel?.invokeMethod("onOverlayResume", null) }
            .onFailure { android.util.Log.d("OverlayWin", "resume: dart channel unavailable") }
    }

    // ---------- 「返回计时器」按钮：Z 轴盖在时间上方，淡入/淡出 ----------

    private val hideBackBtnRunnable = Runnable { hideBackBtn() }

    /** 暂停中显示「继续计时」（点击远程继续），运行中显示「返回计时器」（点击拉起应用）。 */
    private fun backBtnText(): String = if (paused) "继续计时" else "返回计时器"

    /** 由 TimerService 的暂停/继续驱动（setPaused/setResumed）。 */
    fun setPaused(v: Boolean) {
        paused = v
        val b = backBtn
        if (b != null && b.visibility == View.VISIBLE) b.text = backBtnText()
    }

    private fun showBackBtn() {
        val b = backBtn ?: return
        mainHandler.removeCallbacks(hideBackBtnRunnable)
        b.text = backBtnText()
        b.visibility = View.VISIBLE
        b.alpha = 0f
        b.animate().alpha(1f).setDuration(150).start()
        mainHandler.postDelayed(hideBackBtnRunnable, BACK_BTN_AUTO_HIDE_MS)
    }

    private fun hideBackBtn() {
        val b = backBtn ?: return
        mainHandler.removeCallbacks(hideBackBtnRunnable)
        b.animate().alpha(0f).setDuration(120).withEndAction {
            b.visibility = View.GONE
        }.start()
    }

    // ---------- 贴边吸附区判定 / 拖动预览 / 收起 / 展开 ----------

    /** 距左右边缘 ≤[EDGE_SNAP_PX] 时返回贴哪边（true=左 / false=右），否则 null。 */
    private fun edgeZone(frame: View): Boolean? {
        val p = params ?: return null
        val screenW = frame.resources.displayMetrics.widthPixels
        val leftGap = p.x
        val rightGap = screenW - (p.x + frame.width)
        return when {
            leftGap <= EDGE_SNAP_PX -> true
            rightGap <= EDGE_SNAP_PX -> false
            else -> null
        }
    }

    /**
     * 拖动中实时预览：进入吸附区 → 整个窗口内容（原尺寸原地）变成纵向进度条
     * （上半灰=已流逝、下半彩色=剩余），窗口形状不变；拖出即恢复。
     */
    private fun updateEdgePreview(frame: FrameLayout) {
        if (collapsed) return
        val inZone = edgeZone(frame) != null
        if (inZone == previewActive) return
        previewActive = inZone
        if (inZone) {
            // 返回按钮静默复位（整个内容都换成进度条了，按钮不再悬浮）。
            mainHandler.removeCallbacks(hideBackBtnRunnable)
            backBtn?.visibility = View.GONE
            previewBar?.let { pv ->
                pv.layoutParams = FrameLayout.LayoutParams(frame.width, frame.height, Gravity.CENTER)
                pv.fraction = if (totalMs > 0) remainingMs.toFloat() / totalMs else 0f
                pv.visibility = View.VISIBLE
            }
            fullView?.visibility = View.INVISIBLE
        } else {
            previewBar?.visibility = View.GONE
            fullView?.visibility = View.VISIBLE
        }
    }

    /** 松手时在吸附区内 → 收起为贴边进度条。 */
    private fun maybeCollapse(frame: FrameLayout) {
        if (collapsed) return
        edgeZone(frame)?.let { collapse(frame, it) }
    }

    /**
     * 收起：窗口先滑到贴边，再在同一段补间里长成条宽/条高，同时完整窗淡出、贴边条淡入。
     * 三件事共用一条对称缓动曲线（不再"先滑到位、再跳变尺寸"）。
     */
    private fun collapse(frame: FrameLayout, toLeft: Boolean) {
        val p = params ?: return
        val full = fullView ?: return
        val bar = barView ?: return
        fullWpx = frame.width
        fullHpx = full.height
        lastFullX = p.x
        lastFullY = p.y
        // 进度条尺寸与悬浮窗联动：高 = 悬浮窗高度；宽 = 「标记」按钮高度
        // （太窄会和系统返回手势冲突）。
        barWpx = markView?.height?.takeIf { it > 0 } ?: dp(BAR_WIDTH_FALLBACK_DP)
        barHpx = full.height.takeIf { it > 0 } ?: dp(BAR_HEIGHT_FALLBACK_DP)
        bar.layoutParams = bar.layoutParams.apply {
            width = barWpx
            height = barHpx
        }
        val screenW = frame.resources.displayMetrics.widthPixels
        val targetX = if (toLeft) dp(2) else screenW - barWpx - dp(2)

        collapsed = true
        previewActive = false
        previewBar?.visibility = View.GONE
        bar.visibility = View.VISIBLE
        bar.alpha = 0f
        bar.scaleY = 0f

        // 起点：完整窗（满宽满高、不透明）；终点：贴边条（条宽条高、不透明）。
        tween(
            durMs = 200,
            fromX = p.x, toX = targetX,
            fromY = p.y, toY = p.y,
            fromW = frame.width, toW = barWpx,
            fromH = frame.height, toH = barHpx,
            onFrame = { e ->
                // 前 55% 淡出完整窗，后 60% 淡入贴边条（中间略有交叠，无黑场）。
                full.alpha = (1f - e / 0.55f).coerceIn(0f, 1f)
                bar.alpha = ((e - 0.4f) / 0.6f).coerceIn(0f, 1f)
                bar.scaleY = ((e - 0.4f) / 0.6f).coerceIn(0f, 1f)
            },
            onEnd = {
                full.alpha = 1f
                full.visibility = View.GONE
                bar.alpha = 1f
                bar.scaleY = 1f
                // 窗口锁成贴边条尺寸（WRAP_CONTENT 会让窗口收缩到条宽，锁定后展开起点确定）。
                p.x = targetX
                lockSize(barWpx, barHpx)
            },
        )
    }

    /**
     * 展开：贴边条原地长回悬浮窗，位置同步补间到目标，同时条淡出、完整窗淡入。
     *
     * 关键（真机反馈的"先变窗再移动、末尾停顿"根因）：
     * ①缓动曲线用对称的 **AccelerateDecelerate**（旧 Decelerate 在前 25% 时间就走完
     *   44% 距离，末尾 100ms 只挪 12px = 视觉停顿）；
     * ②内容不能首帧直接切成完整窗（旧做法在条上瞬间出现满宽窗=又一次闪现），
     *   改为条与窗在整段补间里交叉淡变；
     * ③窗口尺寸由补间逐帧驱动，内容始终按条尺寸裁剪，不会跳变。
     */
    private fun expand(fromDrag: Boolean = false) {
        val frame = root ?: return
        val p = params ?: return
        val full = fullView ?: return
        val bar = barView ?: return
        // 打断正在播的补间（就地落定），从当前实况起跳。
        cancelTween()

        val screenW = frame.resources.displayMetrics.widthPixels
        val fullW = fullWpx.takeIf { it > 0 } ?: frame.width
        val fullH = fullHpx.takeIf { it > 0 } ?: frame.height
        val targetX = lastFullX.coerceIn(dp(24), (screenW - fullW - dp(24)).coerceAtLeast(dp(24)))
        val targetY = lastFullY.coerceIn(dp(0), (frame.resources.displayMetrics.heightPixels - fullH - dp(24)).coerceAtLeast(dp(0)))
        // 起点取当前窗口实况（拖离时可能已不在贴边位）。
        val startW = frame.width.coerceAtLeast(1)
        val startH = frame.height.coerceAtLeast(1)
        val startX = p.x
        val startY = p.y

        collapsed = false
        previewActive = false
        previewBar?.visibility = View.GONE
        full.visibility = View.VISIBLE
        full.alpha = 0f
        bar.visibility = View.VISIBLE
        bar.alpha = 1f
        bar.scaleY = 1f
        dragExpand = fromDrag

        tween(
            durMs = if (fromDrag) 180 else 260,
            fromX = startX, toX = targetX,
            fromY = startY, toY = targetY,
            fromW = startW, toW = fullW,
            fromH = startH, toH = fullH,
            // 拖离边缘长回：位置完全由手指驱动（补间只管尺寸），否则两者同时写 p.x 会打架。
            movePos = !fromDrag,
            onFrame = { e ->
                // 条在前 45% 淡出，完整窗在 35%~100% 淡入（窗只在尺寸够大时才显形）。
                bar.alpha = (1f - e / 0.45f).coerceIn(0f, 1f)
                full.alpha = ((e - 0.35f) / 0.65f).coerceIn(0f, 1f)
                if (fromDrag) {
                    // 围绕手指长大，且保持贴边那侧不动：右边缘条 → 窗口向左长；左边缘条 → 向右长。
                    applyDragAnchorPosition(frame, p)
                }
            },
            onEnd = {
                full.alpha = 1f
                bar.alpha = 1f
                bar.visibility = View.GONE
                dragExpand = false
                if (!fromDrag) {
                    p.x = targetX
                    p.y = targetY
                }
                releaseSize()
                // 落位后把"原位"更新为当前位置：拖离边缘长回后，若用户接着拖到贴边再松手，
                // 收起记录的位置才是用户想要的展开落点。
                fullWpx = fullW
                fullHpx = fullH
                lastFullX = p.x
                lastFullY = p.y
            },
        )
    }

    /**
     * 拖离边缘长回时，窗口围绕手指长大：右边缘的条保持右边缘跟着手指（向左生长），
     * 左边缘的条保持左边缘跟着手指（向右生长）。宽度用窗口当前实况。
     */
    private fun applyDragAnchorPosition(frame: View, p: WindowManager.LayoutParams) {
        val screenW = frame.resources.displayMetrics.widthPixels
        val screenH = frame.resources.displayMetrics.heightPixels
        val w = p.width.takeIf { it > 0 } ?: frame.width
        val h = p.height.takeIf { it > 0 } ?: frame.height
        val px = if (dragAnchorRight) {
            (dragFingerX + dragAnchorDx - w).toInt()
        } else {
            (dragFingerX - dragAnchorDx).toInt()
        }
        val py = (dragFingerY - dragGrabDy).toInt()
        p.x = px.coerceIn(0, (screenW - w).coerceAtLeast(0))
        p.y = py.coerceIn(0, (screenH - h).coerceAtLeast(0))
    }

    /** 窗口锁成固定 px 尺寸（补间期间禁用 WRAP_CONTENT 的自适应跳变）。 */
    private fun lockSize(w: Int, h: Int) {
        val p = params ?: return
        val frame = root ?: return
        p.width = w.coerceAtLeast(1)
        p.height = h.coerceAtLeast(1)
        lockedSize = true
        runCatching { wm?.updateViewLayout(frame, p) }
    }

    /** 恢复自适应尺寸（WRAP_CONTENT），内容自己决定窗口大小。 */
    private fun releaseSize() {
        val p = params ?: return
        val frame = root ?: return
        p.width = WindowManager.LayoutParams.WRAP_CONTENT
        p.height = WindowManager.LayoutParams.WRAP_CONTENT
        lockedSize = false
        runCatching { wm?.updateViewLayout(frame, p) }
    }

    /**
     * 触摸接管正在播的补间：把窗口就地落定到"当前语义状态"——收起中被打断就当已收起
     * （条可见、窗隐藏），展开中被打断就当已展开（窗可见、条隐藏），恢复自适应尺寸。
     */
    private fun cancelTween() {
        if (tweenToken == null) return
        tweenToken = null
        dragExpand = false
        val full = fullView
        val bar = barView
        if (collapsed) {
            full?.visibility = View.GONE
            full?.alpha = 1f
            bar?.visibility = View.VISIBLE
            bar?.alpha = 1f
            bar?.scaleY = 1f
        } else {
            bar?.visibility = View.GONE
            bar?.alpha = 1f
            full?.visibility = View.VISIBLE
            full?.alpha = 1f
        }
        if (lockedSize) releaseSize()
    }

    /**
     * Choreographer 帧驱动的窗口补间：宽/高/位置四元同帧更新。
     * （不用 ValueAnimator：覆盖层窗口在部分环境只发首帧即结束——实测 18ms end、t=0。）
     * 也不用回调的 time 算进度：它是 vsync 域的下一帧时间戳，与 uptimeMillis 不同时基
     * （模拟器上首帧即 ≥dur，动画等于没播）。以首帧 uptimeMillis 起算真实流逝。
     */
    private fun tween(
        durMs: Long,
        fromX: Int, toX: Int,
        fromY: Int, toY: Int,
        fromW: Int, toW: Int,
        fromH: Int, toH: Int,
        movePos: Boolean = true,
        onFrame: (eased: Float) -> Unit,
        onEnd: () -> Unit,
    ) {
        val frame = root ?: run { onEnd(); return }
        val p = params ?: run { onEnd(); return }
        val token = Any()
        tweenToken = token
        lockedSize = true
        var startedAt = 0L
        val callback = object : android.view.Choreographer.FrameCallback {
            override fun doFrame(time: Long) {
                if (tweenToken !== token) return  // 被 hide()/触摸接管
                if (startedAt == 0L) startedAt = android.os.SystemClock.uptimeMillis()
                val t = ((android.os.SystemClock.uptimeMillis() - startedAt).toFloat() / durMs).coerceIn(0f, 1f)
                val e = accelerateDecelerate(t)
                p.width = (fromW + (toW - fromW) * e).toInt().coerceAtLeast(1)
                p.height = (fromH + (toH - fromH) * e).toInt().coerceAtLeast(1)
                if (movePos) {
                    p.x = (fromX + (toX - fromX) * e).toInt()
                    p.y = (fromY + (toY - fromY) * e).toInt()
                }
                onFrame(e)
                runCatching { wm?.updateViewLayout(frame, p) }
                if (t >= 1f) {
                    tweenToken = null
                    onEnd()
                } else {
                    android.view.Choreographer.getInstance().postFrameCallback(this)
                }
            }
        }
        android.view.Choreographer.getInstance().postFrameCallback(callback)
    }

    /** AccelerateDecelerate（对称缓入缓出）：首尾都慢、中段快，与系统 Material 动效同族。 */
    private fun accelerateDecelerate(t: Float): Float {
        val tt = t.coerceIn(0f, 1f)
        return (kotlin.math.cos((tt + 1f) * Math.PI.toFloat()) / 2f) + 0.5f
    }

    // ---------- 位置约束 ----------

    private fun clampX(x: Int, frame: FrameLayout): Int {
        val screenW = frame.resources.displayMetrics.widthPixels
        return x.coerceIn(0, (screenW - dp(24)).coerceAtLeast(0))
    }

    private fun clampY(y: Int, frame: FrameLayout): Int {
        val screenH = frame.resources.displayMetrics.heightPixels
        return y.coerceIn(0, (screenH - dp(240)).coerceAtLeast(0))
    }

    // ---------- 数据更新 / 生命周期 ----------

    fun update(newRemainingMs: Long, newTotalMs: Long) {
        remainingMs = newRemainingMs
        totalMs = newTotalMs
        val fraction = if (totalMs > 0) (remainingMs.toFloat() / totalMs).coerceIn(0f, 1f) else 0f
        if (collapsed) {
            barView?.fraction = fraction
        } else {
            previewBar?.fraction = fraction
            timeText?.post { timeText?.text = TimerService.formatMs(remainingMs.coerceAtLeast(0)) }
        }
    }

    fun hide() {
        mainHandler.removeCallbacks(hideBackBtnRunnable)
        tweenToken = null
        val view = root
        runCatching { if (view != null) wm?.removeView(view) }
        root = null
        fullView = null
        previewBar = null
        barView = null
        timeText = null
        markView = null
        closeView = null
        backBtn = null
        params = null
        collapsed = false
        lockedSize = false
        previewActive = false
        paused = false
        dragExpand = false
        dragExpanded = false
        fullWpx = 0
        fullHpx = 0
        barWpx = 0
        barHpx = 0
        wm = null
    }

    // ---------- 纵向进度条：灰底 + 剩余比例方形填充（圆角背景做遮罩） ----------

    /**
     * 填充是**方形色块**，用圆角轮廓裁剪（clipPath）——圆角只来自背景遮罩，
     * 不随填充高度缩小（避免剩余不多时变成"压扁的鸡蛋"）。
     * 填充锚定底部：剩余随时间从上往下减小；颜色随剩余持续渐变 绿→黄→红。
     */
    private class VerticalProgressView(ctx: Context) : View(ctx) {
        var fraction = 1f
            set(v) {
                field = v.coerceIn(0f, 1f)
                invalidate()
            }

        /** 圆角半径（dp）；0 = 宽度一半（胶囊形，贴边条用）。预览条与窗口圆角一致（20dp）。 */
        var cornerRadiusDp: Float = 0f

        private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(0x80, 0x80, 0x80, 0x80)
        }
        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val rect = RectF()
        private val clipPath = Path()

        override fun onDraw(canvas: Canvas) {
            val w = width.toFloat()
            val h = height.toFloat()
            if (w <= 0f || h <= 0f) return
            val r = if (cornerRadiusDp > 0f) cornerRadiusDp * resources.displayMetrics.density else w / 2f
            rect.set(0f, 0f, w, h)
            canvas.drawRoundRect(rect, r, r, bgPaint)
            val fh = h * fraction
            if (fh > 0f) {
                fillPaint.color = progressColor(fraction)
                clipPath.reset()
                clipPath.addRoundRect(0f, 0f, w, h, r, r, Path.Direction.CW)
                canvas.save()
                canvas.clipPath(clipPath)
                // 底部锚定的方形填充：顶边平直，圆角完全交给背景遮罩。
                canvas.drawRect(0f, h - fh, w, h, fillPaint)
                canvas.restore()
            }
        }
    }
}

/** 剩余比例 → 颜色：≥50% 绿→黄线性插值，<50% 黄→红线性插值（随时间连续渐变）。 */
private fun progressColor(fraction: Float): Int {
    val green = 0xFF4CAF50.toInt()
    val yellow = 0xFFFFC107.toInt()
    val red = 0xFFF44336.toInt()
    return if (fraction >= 0.5f) {
        lerpColor(yellow, green, (fraction - 0.5f) * 2f)
    } else {
        lerpColor(red, yellow, fraction * 2f)
    }
}

private fun lerpColor(a: Int, b: Int, t: Float): Int {
    val tt = t.coerceIn(0f, 1f)
    return Color.rgb(
        (Color.red(a) + (Color.red(b) - Color.red(a)) * tt).toInt(),
        (Color.green(a) + (Color.green(b) - Color.green(a)) * tt).toInt(),
        (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * tt).toInt(),
    )
}
