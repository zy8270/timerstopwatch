import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timerstopwatch/ui/widgets/app_icon.dart';

/// 离屏渲染桌面图标资源（PNG）：
/// - legacy 各密度 ic_launcher（带渐变底）
/// - adaptive 前景各密度 ic_launcher_foreground（透明底，图形落在 66/108 安全区）
/// 运行：flutter test --update-goldens test/icon_golden_test.dart
/// 产物在 test/goldens/icon/，由 tool/copy_icon_assets 脚本/命令拷入 android res。
Future<void> _render(WidgetTester tester, String name, double px, {bool background = true}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(px, px);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Align(
        alignment: Alignment.topLeft,
        child: AppIcon(size: px, showBackground: background, glyphScale: background ? 0.60 : 0.56),
      ),
    ),
  );
  await expectLater(find.byType(AppIcon), matchesGoldenFile('goldens/icon/$name.png'));
}

void main() {
  // legacy ic_launcher（全彩）
  testWidgets('legacy ic_launcher 各密度', (tester) async {
    await _render(tester, 'launcher-mdpi-48', 48);
    await _render(tester, 'launcher-hdpi-72', 72);
    await _render(tester, 'launcher-xhdpi-96', 96);
    await _render(tester, 'launcher-xxhdpi-144', 144);
    await _render(tester, 'launcher-xxxhdpi-192', 192);
  });

  // adaptive 前景（透明底）
  testWidgets('adaptive 前景各密度', (tester) async {
    await _render(tester, 'fg-mdpi-108', 108, background: false);
    await _render(tester, 'fg-hdpi-162', 162, background: false);
    await _render(tester, 'fg-xhdpi-216', 216, background: false);
    await _render(tester, 'fg-xxhdpi-324', 324, background: false);
    await _render(tester, 'fg-xxxhdpi-432', 432, background: false);
  });
}
