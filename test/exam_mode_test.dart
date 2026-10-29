import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timerstopwatch/controllers/settings_controller.dart';
import 'package:timerstopwatch/controllers/timer_controller.dart';
import 'package:timerstopwatch/models/time_mark.dart';
import 'package:timerstopwatch/services/shared_prefs_provider.dart';
import 'package:timerstopwatch/ui/pages/settings_page.dart';

/// 构造已初始化 mock prefs 的容器；传 [prefs] 时模拟"进程被杀后重启"。
Future<ProviderContainer> _container([SharedPreferences? prefs]) async {
  final p = prefs ?? await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(p)]);
  addTearDown(c.dispose);
  return c;
}

Future<SharedPreferences> _freshPrefs() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('考试模式设置', () {
    test('默认关闭；开启后写入 prefs，重启（重建容器）仍生效', () async {
      final prefs = await _freshPrefs();
      final c = await _container(prefs);
      expect(c.read(settingsProvider).examModeEnabled, false);

      await c.read(settingsProvider.notifier).setExamModeEnabled(true);
      expect(c.read(settingsProvider).examModeEnabled, true);

      // 模拟杀进程后重开：同一 prefs、新容器。
      final c2 = await _container(prefs);
      expect(c2.read(settingsProvider).examModeEnabled, true);
    });

    test('examRulesFor：>15 分钟为 [900,10]；10 秒 < 总时长 ≤ 15 分为 [10]；≤10 秒为空', () {
      expect(examRulesFor(const Duration(minutes: 20)), const [900, 10]);
      expect(examRulesFor(const Duration(minutes: 16)), const [900, 10]);
      expect(examRulesFor(const Duration(minutes: 15)), const [10], reason: '15 分钟节点不小于总时长，忽略');
      expect(examRulesFor(const Duration(seconds: 11)), const [10]);
      expect(examRulesFor(const Duration(seconds: 10)), const [], reason: '结束音频节点不小于总时长，忽略');
      expect(examRulesFor(const Duration(seconds: 5)), const []);
    });
  });

  group('会话快照：暂停后杀进程恢复', () {
    test('暂停写入快照；新容器恢复暂停状态（时长/剩余/标记保留）', () async {
      final prefs = await _freshPrefs();
      final c = await _container(prefs);
      final timer = c.read(timerProvider.notifier);
      timer.setTotal(const Duration(minutes: 10));
      timer.start();
      timer.addMark();
      timer.pause();

      final raw = prefs.getString('timer_session_v1');
      expect(raw, isNotNull, reason: '暂停时应写入快照');
      final j = jsonDecode(raw!) as Map<String, dynamic>;
      expect(j['status'], 'paused');
      expect(j['totalMs'], const Duration(minutes: 10).inMilliseconds);
      expect((j['remainingMs'] as num) > const Duration(minutes: 9).inMilliseconds, true);
      expect((j['marks'] as List).length, 1);
      expect(j['exam'], false);

      // 模拟杀进程后重开。
      final c2 = await _container(prefs);
      final restored = c2.read(timerProvider);
      expect(restored.status, TimerStatus.paused);
      expect(restored.total, const Duration(minutes: 10));
      expect(restored.remaining, greaterThan(const Duration(minutes: 9)));
      expect(restored.marks.length, 1);
      expect(restored.marks.single.seq, 1);

      // 恢复后可继续：继续 → 运行中，取消 → 回未开始并清快照。
      c2.read(timerProvider.notifier).resume();
      expect(c2.read(timerProvider).status, TimerStatus.running);
      c2.read(timerProvider.notifier).cancel();
      expect(prefs.getString('timer_session_v1'), isNull);
    });

    test('标记增删后快照同步更新（恢复后标记与内存一致）', () async {
      final prefs = await _freshPrefs();
      final c = await _container(prefs);
      final timer = c.read(timerProvider.notifier);
      timer.setTotal(const Duration(minutes: 10));
      timer.start();
      timer.addMark();
      timer.addMark();
      timer.pause();
      timer.updateMark(1, note: '第一节点');

      final c2 = await _container(prefs);
      final marks = c2.read(timerProvider).marks;
      expect(marks.length, 2);
      expect(marks.first.note, '第一节点');
      // 快照按毫秒存整，剩余+已进行与总时长允许 ±2ms 取整误差。
      expect(
        (marks.first.elapsed + marks.first.remaining - const Duration(minutes: 10)).abs(),
        lessThanOrEqualTo(const Duration(milliseconds: 2)),
      );
    });

    test('运行中快照：结束时刻在未来 → 恢复运行；错过的提醒节点不补播', () async {
      final prefs = await _freshPrefs();
      final now = DateTime.now().millisecondsSinceEpoch;
      // 20 分钟考试会话，进行到剩 5 分钟时被杀（15 分钟节点已错过）。
      await prefs.setString('timer_session_v1', jsonEncode({
        'status': 'running',
        'totalMs': const Duration(minutes: 20).inMilliseconds,
        'endWallMs': now + const Duration(minutes: 5).inMilliseconds,
        'marks': [
          TimeMark(seq: 1, remaining: const Duration(minutes: 18), elapsed: const Duration(minutes: 2)).toJson(),
        ],
        'fired': <int>[],
        'exam': true,
      }));

      final c = await _container(prefs);
      final timer2 = c.read(timerProvider.notifier);
      final restored = c.read(timerProvider);
      expect(restored.status, TimerStatus.running);
      expect(restored.total, const Duration(minutes: 20));
      expect(restored.remaining, lessThanOrEqualTo(const Duration(minutes: 5)));
      expect(restored.remaining, greaterThan(const Duration(minutes: 4, seconds: 55)));
      expect(restored.marks.single.seq, 1);
      expect(timer2.firedThresholdsForTest, containsAll(const [900]), reason: '15 分钟节点已错过，应记为已触发');
      expect(timer2.firedThresholdsForTest, isNot(contains(10)), reason: '10 秒节点未到，应仍可触发');

      timer2.cancel();
      expect(prefs.getString('timer_session_v1'), isNull);
    });

    test('运行中快照：被杀期间已到点 → 回到未开始并清快照（响铃由精确闹铃兜底）', () async {
      final prefs = await _freshPrefs();
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setString('timer_session_v1', jsonEncode({
        'status': 'running',
        'totalMs': const Duration(minutes: 3).inMilliseconds,
        'endWallMs': now - 1000,
        'marks': const <dynamic>[],
        'fired': const <dynamic>[],
        'exam': false,
      }));

      final c = await _container(prefs);
      expect(c.read(timerProvider).status, TimerStatus.idle);
      expect(prefs.getString('timer_session_v1'), isNull);
    });

    test('到点结束自动清快照', () async {
      final prefs = await _freshPrefs();
      final c = await _container(prefs);
      final timer = c.read(timerProvider.notifier);
      timer.setTotal(const Duration(milliseconds: 300));
      timer.start();
      expect(prefs.getString('timer_session_v1'), isNotNull);

      await Future.delayed(const Duration(milliseconds: 1600));
      expect(c.read(timerProvider).status, TimerStatus.finished);
      expect(prefs.getString('timer_session_v1'), isNull, reason: '结束后快照应清除，避免下次启动误恢复');
    });

    test('快照数据损坏 → 安全回退未开始', () async {
      final prefs = await _freshPrefs();
      await prefs.setString('timer_session_v1', '{not-json');
      final c = await _container(prefs);
      expect(c.read(timerProvider).status, TimerStatus.idle);
      expect(prefs.getString('timer_session_v1'), isNull);
    });
  });

  group('设置页：考试模式开关', () {
    testWidgets('开启后其余阈值项置灰禁用，关闭后恢复可用', (tester) async {
      final prefs = await _freshPrefs();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      ListTile addTile() =>
          tester.widget<ListTile>(find.widgetWithText(ListTile, '添加提醒阈值'));
      expect(addTile().enabled, isTrue, reason: '考试模式关闭时阈值项可用');

      await tester.tap(find.widgetWithText(SwitchListTile, '考试模式'));
      await tester.pumpAndSettle();
      expect(prefs.getBool('exam_mode_enabled'), true);
      expect(addTile().enabled, isFalse, reason: '考试模式开启时阈值项应禁用置灰');

      await tester.tap(find.widgetWithText(SwitchListTile, '考试模式'));
      await tester.pumpAndSettle();
      expect(prefs.getBool('exam_mode_enabled'), false);
      expect(addTile().enabled, isTrue);
    });
  });
}
