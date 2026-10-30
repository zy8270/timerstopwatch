import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timerstopwatch/controllers/settings_controller.dart';
import 'package:timerstopwatch/controllers/timer_controller.dart';
import 'package:timerstopwatch/services/shared_prefs_provider.dart';
import 'package:timerstopwatch/ui/pages/settings_page.dart';
import 'package:timerstopwatch/ui/pages/timer_page.dart';
import 'package:timerstopwatch/ui/widgets/analog_clock.dart';

/// 时钟样式（圆形/电子时钟）回归：
/// 设置页顶部切换 + 持久化加载 + 倒计时进行页按样式渲染。
void main() {
  Future<ProviderContainer> boot({String? initialStyle}) async {
    SharedPreferences.setMockInitialValues(
      initialStyle == null ? <String, Object>{} : <String, Object>{'clock_style': initialStyle},
    );
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    return c;
  }

  testWidgets('设置页顶部有时钟样式切换，默认电子时钟，切换后立即生效并持久化', (tester) async {
    final c = await boot();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: SettingsPage()),
    ));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).clockStyle, ClockStyle.digital, reason: '默认电子时钟');

    await tester.tap(find.text('圆形时钟'));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).clockStyle, ClockStyle.analog, reason: '点击后样式立即切换');
    expect(
      (c.read(sharedPrefsProvider).getString('clock_style')),
      ClockStyle.analog.name,
      reason: '样式应写入 prefs 持久化',
    );

    // 切回电子时钟。
    await tester.tap(find.text('电子时钟'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).clockStyle, ClockStyle.digital);
  });

  testWidgets('重启后按持久化的样式加载（analog）', (tester) async {
    final c = await boot(initialStyle: 'analog');
    expect(c.read(settingsProvider).clockStyle, ClockStyle.analog, reason: 'prefs 中的样式应被加载');
    // 非法/未知值兜底为电子时钟。
    final c2 = await boot(initialStyle: 'nonsense');
    expect(c2.read(settingsProvider).clockStyle, ClockStyle.digital);
  });

  testWidgets('倒计时进行页按样式渲染：默认数字，圆形样式出表盘', (tester) async {
    final c = await boot();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: TimerPage()),
    ));
    await tester.pump();

    final timer = c.read(timerProvider.notifier);
    timer.setTotal(const Duration(hours: 1, minutes: 30));
    timer.start();
    await tester.pump();

    expect(find.byType(AnalogClock), findsNothing, reason: '默认电子时钟：无表盘');
    expect(find.text('1:30:00'), findsOneWidget);

    await c.read(settingsProvider.notifier).setClockStyle(ClockStyle.analog);
    await tester.pump();

    expect(find.byType(AnalogClock), findsOneWidget, reason: '圆形样式：进行页显示表盘');
    // 表盘中心保留剩余时间数字（指针看趋势、数字读秒）。
    expect(find.text('1:30:00'), findsOneWidget);

    // 收尾：停掉计时器的周期 ticker（避免测试结束时仍有 pending timer）。
    c.read(timerProvider.notifier).cancel();
    await tester.pump();
  });
}
