import 'dart:math' as math;

import 'package:flutter/material.dart';

/// App 图标绘制：深紫→亮紫对角渐变底 + 白色扁平秒表（表盘 + 顶部小按钮 + 表盘内斜放沙漏）。
/// 图形整体按包围盒垂直居中（表盘圆心略下移，补偿顶部按钮占的高度）。
///
/// 本类同时是桌面图标的"源文件"：test/icon_golden_test.dart 用它离屏渲染
/// 出各密度的 PNG（legacy ic_launcher 与 adaptive 前景层），不依赖外部图片。
class AppIcon extends StatelessWidget {
  const AppIcon({
    super.key,
    required this.size,
    this.showBackground = true,
    this.glyphScale = 0.60,
  });

  /// 逻辑边长。
  final double size;

  /// 是否绘制渐变背景（adaptive 前景层只需透明底 + 图形）。
  final bool showBackground;

  /// 秒表图形占画布的比例（adaptive 前景须落在 66/108 安全区内）。
  final double glyphScale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AppIconPainter(showBackground: showBackground, glyphScale: glyphScale),
      ),
    );
  }
}

const Color _deepPurple = Color(0xFF4A0E9B);
const Color _brightPurple = Color(0xFFA855F7);

class _AppIconPainter extends CustomPainter {
  _AppIconPainter({required this.showBackground, required this.glyphScale});

  final bool showBackground;
  final double glyphScale;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;

    if (showBackground) {
      final rect = Offset.zero & size;
      final bg = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [_deepPurple, _brightPurple],
        ).createShader(rect);
      canvas.drawRect(rect, bg);
    }

    final g = s * glyphScale; // 秒表图形的基准边长

    // 几何（占 g 比例）：表盘半径、顶部按钮、留隙
    final r = g * 0.30;
    final capH = g * 0.065; // 顶部按钮高
    final capGap = g * 0.025; // 按钮与表盘的间隙
    // 包围盒：顶 = -(r + capGap + capH)，底 = +r → 圆心下移使包围盒居中
    final top = r + capGap + capH;
    final c = Offset(size.width / 2, size.height / 2 + (top - r) / 2);

    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = g * 0.05
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // 顶部按钮（圆角短横帽）
    final cap = Rect.fromCenter(
      center: Offset(c.dx, c.dy - r - capGap - capH / 2),
      width: g * 0.13,
      height: capH,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(cap, Radius.circular(g * 0.025)), stroke);

    // 表盘
    canvas.drawCircle(c, r, stroke);

    // 表盘内斜放的沙漏（旋转 -30°，扁平填充 + 上下端帽）
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-30 * math.pi / 180);
    final w = g * 0.105, h = g * 0.14, waist = g * 0.022;
    final glass = Path()
      ..moveTo(-w, -h)
      ..lineTo(w, -h)
      ..lineTo(waist, 0)
      ..lineTo(w, h)
      ..lineTo(-w, h)
      ..lineTo(-waist, 0)
      ..close();
    canvas.drawPath(glass, fill);
    canvas.drawLine(Offset(-w, -h - g * 0.03), Offset(w, -h - g * 0.03), stroke..strokeWidth = g * 0.045);
    canvas.drawLine(Offset(-w, h + g * 0.03), Offset(w, h + g * 0.03), stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AppIconPainter old) =>
      old.showBackground != showBackground || old.glyphScale != glyphScale;
}
