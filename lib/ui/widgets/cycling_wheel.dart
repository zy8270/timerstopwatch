import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/native_channel.dart';

/// 可循环滚动的数字滚轮（模仿系统计时器的 时/分/秒 选择）。
///
/// 交互口径（保证跟手不卡顿、外部设值必胜）：
/// - 滚动过程中**零重建**：每滚过一格只做 震动+咔哒声（[NativeChannel.wheelTick]），
///   并同步内部基准 `_base`；不向父级回调、不 setState。
/// - 值提交发生在滚动停止（ScrollEnd）：`onChanged(norm)` 是唯一对外回调点；
///   程序化跳转（应用预设/回中）派发的滚动通知一律不处理——`jumpTo` 内部
///   `goIdle()` 与跳转本身各派发一条结束通知，若不拦截会把跳转前的滞留值提交出去，
///   覆盖刚应用的预设（真机 bug：滚轮停在两数字中间时点预设）。
/// - 外部设值（应用预设）通过 [syncGen] 整组通知：即使本滚轮的值没变，
///   滚动中的滚轮也要归位；手指按住时等松手再应用，惯性滚动中立即跳转。
/// - 自己提交的回声不算外部设值（按"最近同步给父级的值"识别）：
///   连续拨动时提交回声常在手指已再次按下时到达，误判会让滚轮在下一次
///   停止时闪回上一拨的落点（真机 bug）。
class CyclingWheel extends StatefulWidget {
  const CyclingWheel({
    super.key,
    required this.count,
    required this.value,
    required this.onChanged,
    required this.syncGen,
    this.itemExtent = 48,
    this.width = 72,
    this.textStyle,
  });

  /// 一圈的取值个数（时=24，分/秒=60）。
  final int count;
  final int value;
  final ValueChanged<int> onChanged;

  /// 外部设值代数：父级每次整组设值（应用预设）时 +1。
  final int syncGen;

  final double itemExtent;
  final double width;
  final TextStyle? textStyle;

  @override
  State<CyclingWheel> createState() => _CyclingWheelState();
}

class _CyclingWheelState extends State<CyclingWheel> {
  /// 用足够的圈数让用户滚不到尽头；靠近边界时无感回中。
  static const int _loops = 64;

  late FixedExtentScrollController _controller;

  /// 当前选中项所在的"圈基"（ selectedItem - norm ）。
  /// 注意圈基只能从 `_controller.selectedItem`（原始圈位）同步：
  /// 当前 SDK 的 onSelectedItemChanged 对循环列表回调的是归一化序号（raw % count），
  /// 用回调值反推会把圈基摧毁为 0，导致预设跳转目标错乱。
  late int _base;

  /// 程序化跳转进行中：跳转触发的滚轮反馈与滚动通知全部忽略。
  bool _programmatic = false;

  /// 外部待应用的值（应用预设时置入；滚动结束或下一帧强制归位后清空）。
  /// 非空期间滚轮不提交滞留值，保证外部设值不被旧值覆盖。
  int? _pendingExternal;

  /// 最近一次同步给父级的取值（自己提交的、或已应用的外部值）。
  /// 父级把刚提交的值原样传回来只是回声，不算外部设值——否则连续拨动时
  /// （惯性滑行中手指已再次按下，提交回声在 pointers>0 时到达），上一甩的
  /// 落点会被挂成待应用外部值，下一甩停止时强制跳回 → 真机闪值 bug。
  /// 预设归位不受影响：整组设值有 syncGen 护送，值相同也照样归位。
  late int _syncedValue;

  /// 手指按在本滚轮上的指针数：>0 时外部值等松手再应用，避免与拖拽拉扯。
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    _base = _loops ~/ 2 * widget.count;
    _syncedValue = widget.value;
    _controller = FixedExtentScrollController(initialItem: _base + widget.value);
  }

  @override
  void didUpdateWidget(CyclingWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只认"非自己刚提交的"变化为外部设值；syncGen 变化整组都算（预设值
    // 恰好等于当前显示值时也要归位）。
    final external = widget.syncGen != oldWidget.syncGen || widget.value != _syncedValue;
    if (!external) return;
    _pendingExternal = widget.value;
    if (_pointers > 0) return; // 手指仍按在滚轮上：ScrollEnd（松手后停止）时应用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final v = _pendingExternal;
      if (v == null) return; // 已在滚动结束路径应用
      _pendingExternal = null;
      _syncedValue = v;
      final target = _base + v;
      if (_controller.selectedItem != target) _jumpSilently(target);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _jumpSilently(int item) {
    final norm = item % widget.count;
    _base = item - norm;
    _programmatic = true;
    _controller.jumpToItem(item);
    _programmatic = false;
  }

  /// 用户每滚过一格（数字变一下）：同步圈基 + 震一下 + 响一下。不对外回调。
  void _onSelectedItemChanged(int _) {
    if (_programmatic) return;
    final raw = _controller.selectedItem;
    _base = raw - raw % widget.count;
    NativeChannel.wheelTick();
  }

  /// 滚动停止：先兑现挂起的外部值（预设），否则才提交用户选中的值；远离中点时无感回中。
  void _onScrollEnd() {
    if (_programmatic) return;
    final pending = _pendingExternal;
    if (pending != null) {
      _pendingExternal = null;
      _syncedValue = pending;
      final target = _base + pending;
      if (_controller.selectedItem != target) _jumpSilently(target);
      // 跳转期间的通知已被 _programmatic 拦截；跳转后 norm == value，无需提交。
      return;
    }
    final item = _controller.selectedItem;
    final norm = item % widget.count;
    _syncedValue = norm; // 先记录：onChanged 触发的父级回声不能算外部设值
    if (norm != widget.value) widget.onChanged(norm);
    final mid = _loops ~/ 2 * widget.count;
    if ((item - mid).abs() > mid ~/ 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpSilently(mid + norm);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.textStyle ??
        TextStyle(fontSize: 28, fontFeatures: const [FontFeature.tabularFigures()], color: Theme.of(context).colorScheme.onSurface);
    return Listener(
      onPointerDown: (_) => _pointers++,
      onPointerUp: (_) => _pointers = math.max(0, _pointers - 1),
      onPointerCancel: (_) => _pointers = math.max(0, _pointers - 1),
      child: SizedBox(
        width: widget.width,
        height: widget.itemExtent * 3,
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            _onScrollEnd();
            return false;
          },
          child: ListWheelScrollView.useDelegate(
            controller: _controller,
            itemExtent: widget.itemExtent,
            diameterRatio: 1.6,
            perspective: 0.004,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: _onSelectedItemChanged,
            childDelegate: ListWheelChildLoopingListDelegate(
              children: List.generate(
                widget.count,
                (i) => Center(child: Text(i.toString().padLeft(2, '0'), style: style)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
