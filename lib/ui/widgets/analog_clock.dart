import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';

/// 圆形时钟：倒计时的模拟表盘样式（设置页「时钟样式」）。
///
/// 表盘语义——指针是"剩余时长的表盘读数"：剩余 1:30:00 时针分针指向
/// 4:30 的位置，随倒计时回退，归零时三针全部指向 12；外圈弧为剩余比例
/// （从 12 点起顺时针覆盖，随倒计时消耗）。中心保留剩余时间数字：
/// 指针看趋势、数字读秒，两者互补。
///
/// 假睡眠层复用本组件的暗色形态（[timeStyle] 传入显式 decoration: none
/// 的样式，避免无 Material 祖先时 fallback 黄色双下划线混入，见 v3.6 定案）。
class AnalogClock extends StatelessWidget {
  const AnalogClock({
    super.key,
    required this.remaining,
    required this.total,
    this.size = 260,
    this.foregroundColor,
    this.trackColor,
    this.progressColor,
    this.timeStyle,
  });

  final Duration remaining;
  final Duration total;
  final double size;

  /// 刻度与时针/分针颜色（默认取主题 onSurface）。
  final Color? foregroundColor;

  /// 剩余弧底色（默认 surfaceContainerHighest）。
  final Color? trackColor;

  /// 剩余弧与秒针颜色（默认 primary）。
  final Color? progressColor;

  /// 中心剩余时间文字样式（默认主题 bodyLarge 派生）。
  final TextStyle? timeStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = foregroundColor ?? scheme.onSurface;
    final track = trackColor ?? scheme.surfaceContainerHighest;
    final progress = progressColor ?? scheme.primary;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _AnalogDialPainter(
              remaining: remaining,
              total: total,
              foreground: foreground,
              track: track,
              progress: progress,
            ),
          ),
          Padding(
            // 中心数字下沉：让出表盘中心与指针轴，落在下半盘。
            padding: EdgeInsets.only(top: size * 0.30),
            child: Text(
              formatClock(remaining),
              style: timeStyle ??
                  Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: size / 10,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalogDialPainter extends CustomPainter {
  _AnalogDialPainter({
    required this.remaining,
    required this.total,
    required this.foreground,
    required this.track,
    required this.progress,
  });

  final Duration remaining;
  final Duration total;
  final Color foreground;
  final Color track;
  final Color progress;

  static const double _pi2 = math.pi * 2;

  /// 12 点方向起、顺时针为正的角度（弧度）。
  static double _angle(double fraction) => -math.pi / 2 + _pi2 * fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;

    // ---- 外圈：剩余比例弧 ----
    final ringWidth = radius * 0.055;
    final ringRadius = radius - ringWidth / 2 - 2;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..color = track;
    canvas.drawCircle(center, ringRadius, ringPaint);

    final fraction = total.inMilliseconds > 0
        ? (remaining.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    if (fraction > 0) {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..strokeCap = StrokeCap.round
        ..color = progress;
      canvas.drawArc(Rect.fromCircle(center: center, radius: ringRadius), _angle(0),
          _pi2 * fraction, false, arcPaint);
    }

    // ---- 刻度：60 格，每 5 格主刻度 ----
    final tickOuter = ringRadius - ringWidth / 2 - radius * 0.03;
    final minorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.012
      ..color = foreground.withValues(alpha: 0.45);
    final majorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.022
      ..color = foreground.withValues(alpha: 0.85);
    for (int i = 0; i < 60; i++) {
      final major = i % 5 == 0;
      final a = _angle(i / 60);
      final inner = tickOuter - (major ? radius * 0.07 : radius * 0.04);
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * inner,
        center + Offset(math.cos(a), math.sin(a)) * tickOuter,
        major ? majorPaint : minorPaint,
      );
    }

    // ---- 指针：剩余时长的表盘读数，随倒计时回退 ----
    final secs = remaining.inSeconds;
    final s = secs % 60;
    final m = (secs ~/ 60) % 60;
    final h = (secs ~/ 3600) % 12;

    void hand(double fraction, double length, double width, Color color) {
      final a = _angle(fraction);
      final tip = center + Offset(math.cos(a), math.sin(a)) * length;
      final tail = center - Offset(math.cos(a), math.sin(a)) * radius * 0.08;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawLine(tail, tip, paint);
    }

    hand(((h + m / 60) % 12) / 12, radius * 0.38, radius * 0.030, foreground);
    hand(((m + s / 60) % 60) / 60, radius * 0.56, radius * 0.022, foreground);
    hand(s / 60, radius * 0.66, radius * 0.011, progress);

    // 指针轴心。
    canvas.drawCircle(center, radius * 0.028, Paint()..color = progress);
    canvas.drawCircle(
        center, radius * 0.013, Paint()..color = track);
  }

  @override
  bool shouldRepaint(_AnalogDialPainter old) =>
      old.remaining != remaining ||
      old.total != total ||
      old.foreground != foreground ||
      old.track != track ||
      old.progress != progress;
}
