import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timerstopwatch/controllers/fake_sleep_controller.dart';
import 'package:timerstopwatch/controllers/history_controller.dart';
import 'package:timerstopwatch/controllers/presets_controller.dart';
import 'package:timerstopwatch/controllers/timer_controller.dart';
import 'package:timerstopwatch/models/history_entry.dart';
import 'package:timerstopwatch/models/time_mark.dart';
import 'package:timerstopwatch/services/shared_prefs_provider.dart';
import 'package:timerstopwatch/ui/pages/timer_page.dart';
import 'package:timerstopwatch/ui/widgets/fake_sleep_layer.dart';

/// v3.6 三项真机反馈修复的回归：
/// 1) 假睡眠黄线 = 无 Material 祖先时 MaterialApp 注入的黄色双下划线 fallback 样式；
/// 2) "已进行"展示口径改为与上一条标记的间隔；
/// 3) 历史条目内每条标记可编辑（改剩余时间自动重算已进行、改备注、删除）。
void main() {
  testWidgets('假睡眠层文字不继承黄色下划线 fallback 样式（黄线根因回归）', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    c.read(timerProvider.notifier).setTotal(const Duration(minutes: 10));
    c.read(timerProvider.notifier).start();
    // 不 await：state 同步置位即可，SystemChrome 调用在纯 widget 测试里不可达。
    c.read(fakeSleepProvider.notifier).enter().catchError((_) {});
    expect(c.read(fakeSleepProvider).active, isTrue, reason: '前置：假睡眠已激活');

    // 关键：FakeSleepLayer 在 Scaffold 之外（与 NavShell 中同构的 Stack 摆放）。
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Stack(
            children: const [Scaffold(body: SizedBox()), FakeSleepLayer()],
          ),
        ),
      ),
    );
    await tester.pump();

    final ctx = tester.element(find.byKey(const Key('fakeSleepTime')));
    final inherited = DefaultTextStyle.of(ctx).style;
    expect(
      inherited.decoration == null || inherited.decoration == TextDecoration.none,
      isTrue,
      reason: '假睡眠层不在 Material 下时会继承 MaterialApp 的 fallback 样式（黄色双下划线），'
          '修复后应被透明 Material 拦截',
    );

    final text = tester.widget<Text>(find.byKey(const Key('fakeSleepTime')));
    expect(text.style?.decoration, TextDecoration.none, reason: '文字自身样式应显式声明无装饰线');

    // 清理：退出假睡眠（卸掉漂移 Timer）并结束会话（停 200ms ticker），否则
    // "Timer is still pending" 会判失败。
    c.read(fakeSleepProvider.notifier).exit().catchError((_) {});
    c.read(timerProvider.notifier).cancel();
    await tester.pump();
  });

  group('已进行 = 与上一条标记的间隔（展示口径）', () {
    test('intervalAt：第 1 条自开始，其后为相邻差值；中途删除后按现存相邻重算', () {
      final marks = [
        const TimeMark(seq: 1, remaining: Duration(minutes: 9), elapsed: Duration(minutes: 1)),
        const TimeMark(seq: 2, remaining: Duration(minutes: 7), elapsed: Duration(minutes: 3)),
        const TimeMark(seq: 3, remaining: Duration(minutes: 4), elapsed: Duration(minutes: 6)),
      ];
      expect(intervalAt(marks, 0), const Duration(minutes: 1));
      expect(intervalAt(marks, 1), const Duration(minutes: 2), reason: '第 2 条 = 与第 1 条的差值');
      expect(intervalAt(marks, 2), const Duration(minutes: 3), reason: '第 3 条 = 与第 2 条的差值');

      final afterDelete = marks.sublist(0, 2);
      expect(intervalAt(afterDelete, 1), const Duration(minutes: 2));
    });

    test('历史导出文本的已进行列为间隔口径', () {
      final entry = HistoryEntry(
        id: 't',
        name: '测试',
        savedAtMs: 0,
        total: const Duration(minutes: 10),
        marks: const [
          TimeMark(seq: 1, remaining: Duration(minutes: 9), elapsed: Duration(minutes: 1)),
          TimeMark(seq: 2, remaining: Duration(minutes: 7), elapsed: Duration(minutes: 3)),
        ],
      );
      final text = entry.toExportText();
      expect(text.contains('00:09:00\t00:01:00\t'), isTrue, reason: '第 1 条：自开始 1 分钟');
      expect(text.contains('00:07:00\t00:02:00\t'), isTrue, reason: '第 2 条：间隔 2 分钟（非自开始 3 分钟）');
    });
  });

  group('预设拖动避让防抖（临界位置不抽搐）', () {
    Future<ProviderContainer> bootPreset(List<String> secs) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('preset_list_seconds_v2', secs);
      final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      return c;
    }

    testWidgets('拖到两格边界来回小幅抖动：顺序稳定不震荡；到目标格中心才换位', (tester) async {
      final c = await bootPreset(['60', '120', '180']);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const MaterialApp(home: TimerPage())),
      );
      await tester.pump();

      final chip1 = find.text('01:00');
      final chip2 = find.text('02:00');
      final chip3 = find.text('03:00');
      final c1 = tester.getCenter(chip1);
      final c2 = tester.getCenter(chip2);
      final c3 = tester.getCenter(chip3);
      final boundary = (c2.dx + c3.dx) / 2; // chip2 与 chip3 的列边界

      final gesture = await tester.startGesture(c1);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));

      // 指针在 chip2/chip3 边界两侧来回 ±3px 抖动（临界位置抽搐场景）。
      // 注意：从 chip1 移向边界会路过 chip2 中心，触发一次合理换位 [120,60,180]；
      // 之后的边界抖动不应再引发 chip2/chip3 之间的翻转。
      for (var i = 0; i < 4; i++) {
        await gesture.moveTo(Offset(boundary - 3, c2.dy));
        await tester.pump(const Duration(milliseconds: 30));
        await gesture.moveTo(Offset(boundary + 3, c2.dy));
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(
        c.read(presetsProvider),
        const [Duration(minutes: 2), Duration(minutes: 1), Duration(minutes: 3)],
        reason: '边界迟滞带内小幅抖动不应触发 60↔180 的排序翻转（抽搐）',
      );

      // 稳定移到 chip3 中心：实时换位生效（当前 [120,60,180]，60 移到 slot2 → [120,180,60]）
      await gesture.moveTo(c3);
      await tester.pump(const Duration(milliseconds: 30));
      expect(
        c.read(presetsProvider),
        const [Duration(minutes: 2), Duration(minutes: 3), Duration(minutes: 1)],
        reason: '到目标格中心应实时排序',
      );
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('历史条目内单条标记编辑', () {
    Future<ProviderContainer> boot() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      await c.read(historyProvider.notifier).create(
            name: '一条历史',
            total: const Duration(minutes: 10),
            marks: const [
              TimeMark(seq: 1, remaining: Duration(minutes: 9), elapsed: Duration(minutes: 1), note: '第一段'),
              TimeMark(seq: 2, remaining: Duration(minutes: 7), elapsed: Duration(minutes: 3)),
            ],
          );
      return c;
    }

    test('修改剩余时间：已进行自动重算，间隔随之更新', () async {
      final c = await boot();
      final id = c.read(historyProvider).single.id;
      await c.read(historyProvider.notifier).updateMark(
            id,
            2,
            remaining: const Duration(minutes: 4),
          );
      final entry = c.read(historyProvider).single;
      final m = entry.marks[1];
      expect(m.remaining, const Duration(minutes: 4));
      expect(m.elapsed, const Duration(minutes: 6), reason: '已进行 = 总时长 - 剩余');
      expect(intervalAt(entry.marks, 1), const Duration(minutes: 5), reason: '展示间隔 = 6-1 分钟');
    });

    test('修改备注与删除', () async {
      final c = await boot();
      final id = c.read(historyProvider).single.id;
      await c.read(historyProvider.notifier).updateMark(id, 2, note: '资料分析');
      var entry = c.read(historyProvider).single;
      expect(entry.marks[1].note, '资料分析');

      await c.read(historyProvider.notifier).removeMark(id, 1);
      entry = c.read(historyProvider).single;
      expect(entry.marks.map((m) => m.seq), [2], reason: '删除后其余序号保持不变');
    });
  });
}
