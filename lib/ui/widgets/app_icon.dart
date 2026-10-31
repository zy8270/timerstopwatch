import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/app_palette.dart';

/// App 图标绘制：配色深→亮对角渐变底（**圆角矩形**，半径为边长的 20%，
/// 与桌面圆角图标观感一致——部分桌面不按 adaptive 遮罩渲染、直接取位图，
/// 位图必须自带圆角）+ 白色扁平秒表（表盘 + 顶部小按钮 + 表盘内斜放沙漏）。
/// 图形整体按包围盒垂直居中（表盘圆心略下移，补偿顶部按钮占的高度）。
///
/// 本类同时是桌面图标的"源文件"：test/icon_golden_test.dart 用它离屏渲染
/// 出各密度的 PNG（legacy ic_launcher 与 adaptive 前景层），不依赖外部图片。
/// 渐变颜色取 [palette]（主题配色联动），默认深紫（v3.3 定案的原始配色）。
class AppIcon extends StatelessWidget {
  const AppIcon({
    super.key,
    required this.size,
    this.showBackground = true,
    this.glyphScale = 0.60,
    this.palette = AppPalette.deepPurple,
    this.cornerRadiusRatio = 0.20,
  });

  /// 逻辑边长。
  final double size;

  /// 是否绘制渐变背景（adaptive 前景层只需透明底 + 图形）。
  final bool showBackground;

  /// 秒表图形占画布的比例（adaptive 前景须落在 66/108 安全区内）。
  final double glyphScale;

  /// 配色（渐变两端色）。
  final AppPalette palette;

  /// 背景圆角半径占边长的比例（仅 showBackground 时生效；adaptive 前景透明无圆角）。
  final double cornerRadiusRatio;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AppIconPainter(
          showBackground: showBackground,
          glyphScale: glyphScale,
          gradientStart: palette.iconStart,
          gradientEnd: palette.iconEnd,
          cornerRadiusRatio: cornerRadiusRatio,
        ),
      ),
    );
  }
}

class _AppIconPainter extends CustomPainter {
  _AppIconPainter({
    required this.showBackground,
    required this.glyphScale,
    required this.gradientStart,
    required this.gradientEnd,
    required this.cornerRadiusRatio,
  });

  final bool showBackground;
  final double glyphScale;
  final Color gradientStart;
  final Color gradientEnd;
  final double cornerRadiusRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;

    if (showBackground) {
      final rect = Offset.zero & size;
      final bg = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientStart, gradientEnd],
        ).createShader(rect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(s * cornerRadiusRatio)),
        bg,
      );
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
      old.showBackground != showBackground ||
      old.glyphScale != glyphScale ||
      old.gradientStart != gradientStart ||
      old.gradientEnd != gradientEnd ||
      old.cornerRadiusRatio != cornerRadiusRatio;
}
