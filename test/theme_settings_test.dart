import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timerstopwatch/app.dart';
import 'package:timerstopwatch/controllers/settings_controller.dart';
import 'package:timerstopwatch/models/app_palette.dart';
import 'package:timerstopwatch/services/shared_prefs_provider.dart';
import 'package:timerstopwatch/ui/pages/settings_page.dart';
import 'package:timerstopwatch/ui/widgets/app_icon.dart';

/// 主题定制（v3.12）：配色选择（图标弹窗）+ 日/夜间模式 + 持久化 + App 主题联动。
void main() {
  Future<ProviderContainer> boot({Map<String, Object> initial = const {}}) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    return c;
  }

  testWidgets('默认：浅紫配色 + 跟随系统；未知持久化值兜底默认', (tester) async {
    final c = await boot();
    final s = c.read(settingsProvider);
    expect(s.palette, AppPalette.lightPurple, reason: '默认浅紫');
    expect(s.themeMode, AppThemeMode.system, reason: '默认跟随系统');

    final c2 = await boot(initial: {'theme_palette': 'nonsense', 'theme_mode': 'nonsense'});
    expect(c2.read(settingsProvider).palette, AppPalette.lightPurple);
    expect(c2.read(settingsProvider).themeMode, AppThemeMode.system);
  });

  testWidgets('配置色弹窗：7 套配色各带图标选项，点选立即生效并持久化', (tester) async {
    final c = await boot();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: SettingsPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('主题色'));
    await tester.pumpAndSettle();

    expect(find.byType(AppIcon), findsNWidgets(AppPalette.values.length + 1),
        reason: '弹窗内 7 个配色图标 + 设置页 leading 图标');

    await tester.tap(find.text('粉红').last);
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).palette, AppPalette.pink, reason: '点选后立即切换');
    expect(c.read(sharedPrefsProvider).getString('theme_palette'), 'pink', reason: '写入 prefs');

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).palette, AppPalette.pink, reason: '关闭弹窗后保持');
  });

  testWidgets('日/夜间模式：设置页切换持久化', (tester) async {
    final c = await boot();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: SettingsPage()),
    ));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).themeMode, AppThemeMode.system);

    await tester.tap(find.text('夜间'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).themeMode, AppThemeMode.dark);
    expect(c.read(sharedPrefsProvider).getString('theme_mode'), 'dark');

    await tester.tap(find.text('日间'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).themeMode, AppThemeMode.light);
    expect(c.read(sharedPrefsProvider).getString('theme_mode'), 'light');
  });

  testWidgets('配色弹窗：日/夜间选择器与配色网格同宽（左右边缘对齐首/末按钮）', (tester) async {
    final c = await boot();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: SettingsPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('主题色'));
    await tester.pumpAndSettle();

    // 800 宽测试窗口下项宽触到 104 上限：网格 3×104+2×12=336，
    // 弹窗内容收敛为网格宽，模式选择器应与之同宽（v3.14 真机反馈回归）。
    // SegmentedButton 是泛型组件，byType 匹配不到实例，须用谓词。
    final segmentedFinder = find.byWidgetPredicate((w) => w is SegmentedButton);
    final grid = tester.getRect(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(Wrap)).first,
    );
    final mode = tester.getRect(
      find.descendant(of: find.byType(AlertDialog), matching: segmentedFinder).first,
    );
    expect(mode.width, grid.width, reason: '模式选择器应与配色网格同宽');
    expect(mode.left, grid.left, reason: '左边缘对齐第一个配色按钮');
    expect(mode.right, grid.right, reason: '右边缘对齐第三个配色按钮');
  });

  testWidgets('TimerApp：themeMode 与配色主题随设置联动', (tester) async {
    final c = await boot(initial: {'theme_mode': 'dark', 'theme_palette': 'cyan'});
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const TimerApp()));
    await tester.pumpAndSettle();

    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app().themeMode, ThemeMode.dark, reason: '持久化的夜间模式生效');
    final cyanLight = app().theme!.colorScheme.primary;
    final cyanDark = app().darkTheme!.colorScheme.primary;

    // 切换配色：深浅两套主题的 primary 均随新种子变化。
    await c.read(settingsProvider.notifier).setPalette(AppPalette.pink);
    await tester.pumpAndSettle();
    expect(app().theme!.colorScheme.primary, isNot(cyanLight), reason: '日间主题色随配色变化');
    expect(app().darkTheme!.colorScheme.primary, isNot(cyanDark), reason: '夜间主题色随配色变化');

    // 切换回跟随系统。
    await c.read(settingsProvider.notifier).setThemeMode(AppThemeMode.system);
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.system);
  });
}
