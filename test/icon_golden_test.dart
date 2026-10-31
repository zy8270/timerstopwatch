import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timerstopwatch/models/app_palette.dart';
import 'package:timerstopwatch/ui/widgets/app_icon.dart';

/// 离屏渲染桌面图标资源（PNG）：
/// - legacy 各密度 `ic_launcher_<palette>`（带渐变底，每套主题配色一套）
/// - adaptive 前景各密度 `ic_launcher_foreground`（透明底，图形落在 66/108 安全区；
///   白色秒表与配色无关，各配色共用一份）
/// 运行：flutter test --update-goldens test/icon_golden_test.dart
/// 产物在 test/goldens/icon/，拷入 android res（键名 = `AppPalette.name`）：
///   `launcher-<key>-<dpi>.png` → `mipmap-<dpi>/ic_launcher_<key>.png`
///   （基础 ic_launcher.png 取默认配色 lightpurple 那套）
Future<void> _render(
  WidgetTester tester,
  String name,
  double px, {
  AppPalette palette = AppPalette.deepPurple,
  bool background = true,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(px, px);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Align(
        alignment: Alignment.topLeft,
        child: AppIcon(
          size: px,
          palette: palette,
          showBackground: background,
          glyphScale: background ? 0.60 : 0.56,
        ),
      ),
    ),
  );
  await expectLater(find.byType(AppIcon), matchesGoldenFile('goldens/icon/$name.png'));
}

void main() {
  // legacy ic_launcher（全彩，每套主题配色一套，alias 图标用）
  testWidgets('legacy ic_launcher 各密度 × 各配色', (tester) async {
    const densities = [('mdpi', 48.0), ('hdpi', 72.0), ('xhdpi', 96.0), ('xxhdpi', 144.0), ('xxxhdpi', 192.0)];
    for (final palette in AppPalette.values) {
      for (final (name, px) in densities) {
        await _render(tester, 'launcher-${palette.name}-$name', px, palette: palette);
      }
    }
  });

  // adaptive 前景（透明底；白色图形与配色无关，共用一份）
  testWidgets('adaptive 前景各密度', (tester) async {
    await _render(tester, 'fg-mdpi-108', 108, background: false);
    await _render(tester, 'fg-hdpi-162', 162, background: false);
    await _render(tester, 'fg-xhdpi-216', 216, background: false);
    await _render(tester, 'fg-xxhdpi-324', 324, background: false);
    await _render(tester, 'fg-xxxhdpi-432', 432, background: false);
  });
}
