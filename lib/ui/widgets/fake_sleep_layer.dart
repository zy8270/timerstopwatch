import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/fake_sleep_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/timer_controller.dart';
import '../../core/format.dart';
import 'analog_clock.dart';

/// 假睡眠覆盖层：纯黑全屏 + 调暗的倒计时时间，位置定期跳变防烧屏；
/// 点击任意处：时间先以非线性动画回到原位，然后退出假睡眠。
///
/// 黄线根因（v3.6 定案）：本层挂在 NavShell 的 Stack 里、在 Scaffold 之外，
/// 不在任何 Material 下——MaterialApp 会给无 Material 祖先的 Text 注入
/// fallback 错误样式（material/app.dart `_errorTextStyle`：黄色双下划线、
/// monospace），显式样式没写 decoration 时黄色装饰线就会被合并进来
/// （真机表现：紧贴时间下方、全亮黄色、时间调暗时线反而更亮）。
/// 修复：①外层包 Material（type: transparency）；②文字样式显式
/// decoration: TextDecoration.none 双保险。v3.3~v3.5 的"OLED 拖影"结论作废。
class FakeSleepLayer extends ConsumerStatefulWidget {
  const FakeSleepLayer({super.key});

  @override
  ConsumerState<FakeSleepLayer> createState() => _FakeSleepLayerState();
}

class _FakeSleepLayerState extends ConsumerState<FakeSleepLayer> {
  static const _driftEvery = Duration(seconds: 45);
  static const _returnDuration = Duration(milliseconds: 1600);

  Timer? _driftTimer;
  double _dy = 0; // 相对屏幕中心的垂直偏移（0 = 原位）
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _driftTimer = Timer.periodic(_driftEvery, (_) => _drift());
  }

  @override
  void dispose() {
    _driftTimer?.cancel();
    super.dispose();
  }

  void _drift() {
    if (_exiting) return;
    final screenH = MediaQuery.of(context).size.height;
    // 幅度 10%~20% 屏高，随机上下。位置直接跳变（见类注释：慢动画会拖出残影带）。
    final range = screenH * 0.15;
    setState(() => _dy = (Random().nextDouble() * 2 - 1) * range);
  }

  Future<void> _onTap() async {
    if (_exiting) return;
    _exiting = true;
    _driftTimer?.cancel();
    // 时间以非线性动画移回原位，随后退出假睡眠。
    setState(() => _dy = 0);
    await Future.delayed(_returnDuration);
    if (mounted) ref.read(fakeSleepProvider.notifier).exit();
  }

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(timerProvider);
    final size = MediaQuery.of(context).size;
    final paused = timer.status == TimerStatus.paused;
    final analog =
        ref.watch(settingsProvider.select((s) => s.clockStyle)) == ClockStyle.analog;

    // 圆形时钟跟随时钟样式；全白 50% 调暗（弧底稍暗作层次）。
    // 中心数字样式显式 decoration: none——本层无 Material 祖先语境（v3.6 黄线定案）。
    final Widget content;
    final double contentHeight;
    if (analog) {
      const clockSize = 280.0;
      contentHeight = clockSize;
      content = SizedBox(
        width: clockSize,
        height: clockSize,
        child: AnalogClock(
          remaining: timer.remaining,
          total: timer.total,
          foregroundColor: Colors.white.withValues(alpha: 0.5),
          trackColor: Colors.white.withValues(alpha: 0.14),
          progressColor: Colors.white.withValues(alpha: 0.5),
          timeStyle: TextStyle(
            fontSize: clockSize / 10,
            fontWeight: FontWeight.w300,
            color: Colors.white.withValues(alpha: 0.5),
            fontFeatures: const [FontFeature.tabularFigures()],
            decoration: TextDecoration.none,
          ),
        ),
      );
    } else {
      contentHeight = 160; // 数字块（68px 文字 + 暂停标签）的近似高度
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatClock(timer.remaining),
            key: const Key('fakeSleepTime'),
            style: TextStyle(
              fontSize: 68,
              fontWeight: FontWeight.w300,
              color: Colors.white.withValues(alpha: 0.5),
              fontFeatures: const [FontFeature.tabularFigures()],
              // 显式去掉装饰线：防止无 Material 祖先时 fallback 黄色双下划线合并进来。
              decoration: TextDecoration.none,
            ),
          ),
          if (paused)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '已暂停',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 15,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
        ],
      );
    }

    return Positioned.fill(
      child: GestureDetector(
        onTap: _onTap,
        child: Material(
          // 透明 Material：提供正常 DefaultTextStyle（bodyMedium），杜绝 fallback 错误样式。
          type: MaterialType.transparency,
          child: Container(
            color: Colors.black,
            child: Stack(
              children: [
                // 漂移 = 跳变（duration 0）；仅点击退出时的"回原位"用慢动画。
                AnimatedPositioned(
                  duration: _exiting ? _returnDuration : Duration.zero,
                  curve: Curves.easeInOutCubic,
                  left: 0,
                  right: 0,
                  top: size.height / 2 - contentHeight / 2 + _dy,
                  child: Center(child: content),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
