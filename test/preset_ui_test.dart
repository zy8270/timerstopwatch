import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timerstopwatch/controllers/presets_controller.dart';
import 'package:timerstopwatch/services/shared_prefs_provider.dart';
import 'package:timerstopwatch/ui/pages/timer_page.dart';

/// 预设区交互回归（真机报过"编辑状态不能拖动排序"）：
/// 长按拖动一个预设到另一个之上 → 顺序变化、持久化；编辑角标随长按出现。
void main() {
  testWidgets('长按拖动预设可排序且进入编辑模式', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('preset_list_seconds_v2', ['60', '120']);
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TimerPage()),
      ),
    );
    await tester.pump();

    final chip1 = find.text('01:00'); // 60s
    final chip2 = find.text('02:00'); // 120s
    expect(chip1, findsOneWidget, reason: '预设 01:00 未显示');
    expect(chip2, findsOneWidget, reason: '预设 02:00 未显示');
    expect(find.byIcon(Icons.do_not_disturb_on), findsNothing, reason: '初始不应有删除角标');

    // 长按 chip1（600ms 激活拖动）→ 拖到 chip2 中心 → 松手
    final start = tester.getCenter(chip1);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));
    // 长按激活进入编辑模式：角标出现
    expect(find.byIcon(Icons.do_not_disturb_on), findsWidgets, reason: '长按后未进入编辑模式');

    final delta = tester.getCenter(chip2) - start;
    // 分小步拖动，保证途经的 DragTarget 都收到 move 事件
    for (var i = 1; i <= 5; i++) {
      await gesture.moveBy(delta / 5);
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      container.read(presetsProvider).first,
      const Duration(minutes: 2),
      reason: '拖动后 02:00 应排到最前',
    );
    expect(prefs.getStringList('preset_list_seconds_v2')!.first, '120', reason: '排序未持久化');

    // 点预设区域外（标题栏）应退出编辑：角标消失。
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    expect(find.byIcon(Icons.do_not_disturb_on), findsNothing, reason: '点预设外未退出编辑');
  });

  testWidgets('长按拖动中其他格实时避让（悬停即排序）', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('preset_list_seconds_v2', ['60', '120', '180']);
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TimerPage()),
      ),
    );
    await tester.pump();

    final chip1 = find.text('01:00');
    final chip2 = find.text('02:00');
    // 拖动开始后 chip 文本会同时出现在原位/拖影/残位三处，坐标须先取好。
    final c1 = tester.getCenter(chip1);
    final c2 = tester.getCenter(chip2);
    final gesture = await tester.startGesture(c1);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));

    // 拖到 chip2 中心但先不松手：顺序应已实时变化（避让生效）。
    final delta = c2 - c1;
    for (var i = 1; i <= 5; i++) {
      await gesture.moveBy(delta / 5);
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(
      container.read(presetsProvider).first,
      const Duration(minutes: 2),
      reason: '悬停过程中未实时排序',
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
  });

  test('movePresetTo 双向语义：落在悬停格、其余顺延', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('preset_list_seconds_v2', ['60', '120', '180']);
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);

    // 60s（index 0）拖到 index 2 → [120, 180, 60]
    await container.read(presetsProvider.notifier).movePresetTo(const Duration(seconds: 60), 2);
    expect(container.read(presetsProvider), [120, 180, 60].map((s) => Duration(seconds: s)).toList());

    // 60s（index 2）拖回 index 0 → [60, 120, 180]
    await container.read(presetsProvider.notifier).movePresetTo(const Duration(seconds: 60), 0);
    expect(container.read(presetsProvider), [60, 120, 180].map((s) => Duration(seconds: s)).toList());

    // 悬停自己的格 = 无操作
    await container.read(presetsProvider.notifier).movePresetTo(const Duration(seconds: 120), 1);
    expect(container.read(presetsProvider), [60, 120, 180].map((s) => Duration(seconds: s)).toList());

    expect(prefs.getStringList('preset_list_seconds_v2'), ['60', '120', '180'], reason: '排序未持久化');
  });
}
