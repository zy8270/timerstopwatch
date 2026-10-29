import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timerstopwatch/controllers/timer_controller.dart';
import 'package:timerstopwatch/services/shared_prefs_provider.dart';
import 'package:timerstopwatch/ui/pages/timer_page.dart';
import 'package:timerstopwatch/ui/widgets/cycling_wheel.dart';

/// 滚轮 bug 回归（真机反馈：滚轮停在两个数字中间时点预设，该滚轮来回闪动数字并卡住）。
/// 可观测量：点预设后 timerProvider.total 应立即等于预设值且保持不变；
/// 之后滚轮仍可正常滚动并提交值（不卡死）。
void main() {
  Future<ProviderContainer> boot() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('preset_list_seconds_v2', ['600', '120']);
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> pumpPage(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MaterialApp(home: TimerPage())),
    );
    await tester.pump();
  }

  /// 秒轮（第三个滚轮）。初始总时长 1h，预设 10:00 / 02:00。
  final Finder secondsWheel = find.byType(CyclingWheel).at(2);

  /// 滚动后再拖一格，验证滚轮未卡死、值提交正常（预设后总时长 2:00 → 拨一格 = 2:01）。
  Future<void> expectWheelStillAlive(WidgetTester tester, ProviderContainer c) async {
    await tester.drag(secondsWheel, const Offset(0, -48));
    await tester.pumpAndSettle();
    expect(c.read(timerProvider).total, const Duration(minutes: 2, seconds: 1),
        reason: '滚轮应仍可滚动并提交（未卡死）');
  }

  testWidgets('场景A：手指按住滚轮停在半格时点预设，预设应立即生效', (tester) async {
    final c = await boot();
    await pumpPage(tester, c);

    // 手指按住秒轮并拖到两数字中间（半格），保持按住不松
    final gesture = await tester.startGesture(tester.getCenter(secondsWheel));
    await gesture.moveBy(const Offset(0, 26)); // 0.5 格多一点
    await tester.pump(const Duration(milliseconds: 50));

    // 另一只手点预设 02:00
    await tester.tap(find.text('02:00'));
    await tester.pump(const Duration(milliseconds: 50));

    // 预设生效期间值应保持稳定（bug 时会被滚轮的旧值回调拉回去）
    expect(c.read(timerProvider).total, const Duration(minutes: 2),
        reason: '点预设后应立即应用到总时长');

    await gesture.up();
    await tester.pumpAndSettle();

    expect(c.read(timerProvider).total, const Duration(minutes: 2),
        reason: '松手后预设值不应被滚轮的滞留值覆盖');

    await expectWheelStillAlive(tester, c);
  });

  testWidgets('场景B：惯性滚动进行中点预设，预设应立即生效', (tester) async {
    final c = await boot();
    await pumpPage(tester, c);

    // 甩动秒轮产生惯性滚动
    await tester.fling(secondsWheel, const Offset(0, -120), 2000);
    await tester.pump(const Duration(milliseconds: 30)); // 滚动进行中

    await tester.tap(find.text('02:00'));
    await tester.pumpAndSettle();

    expect(c.read(timerProvider).total, const Duration(minutes: 2),
        reason: '惯性滚动中点预设，最终值应为预设');
    await expectWheelStillAlive(tester, c);
  });

  testWidgets('场景C：半格松手回弹动画中点预设，预设应立即生效', (tester) async {
    final c = await boot();
    await pumpPage(tester, c);

    // 拖到半格后松手（回弹/吸附动画进行中），立刻点预设
    await tester.drag(secondsWheel, const Offset(0, 26));
    await tester.pump(const Duration(milliseconds: 16)); // 吸附动画中

    await tester.tap(find.text('02:00'));
    await tester.pumpAndSettle();

    expect(c.read(timerProvider).total, const Duration(minutes: 2),
        reason: '吸附动画中点预设，最终值应为预设');
    await expectWheelStillAlive(tester, c);
  });
}
