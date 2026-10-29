import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timerstopwatch/controllers/history_controller.dart';
import 'package:timerstopwatch/controllers/presets_controller.dart';
import 'package:timerstopwatch/controllers/settings_controller.dart';
import 'package:timerstopwatch/controllers/timer_controller.dart';
import 'package:timerstopwatch/services/shared_prefs_provider.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TimerController 标记逻辑', () {
    test('标记的剩余 + 已进行 = 总时长，且随时间增长', () async {
      final c = await _container();
      final controller = c.read(timerProvider.notifier);
      controller.setTotal(const Duration(seconds: 10));
      controller.start();
      expect(c.read(timerProvider).status, TimerStatus.running);

      await Future.delayed(const Duration(milliseconds: 1200));
      controller.addMark();
      var mark = c.read(timerProvider).marks.single;
      expect(mark.seq, 1);
      expect(mark.elapsed.inMilliseconds, greaterThan(1000));
      expect(mark.remaining + mark.elapsed, const Duration(seconds: 10));

      await Future.delayed(const Duration(milliseconds: 600));
      controller.addMark();
      final second = c.read(timerProvider).marks.last;
      expect(second.seq, 2);
      expect(second.elapsed, greaterThan(mark.elapsed));
      expect(second.remaining + second.elapsed, const Duration(seconds: 10));

      // 撤销移除最后一条
      controller.undoMark();
      final marks = c.read(timerProvider).marks;
      expect(marks.length, 1);
      expect(marks.single.seq, 1);

      controller.cancel();
      expect(c.read(timerProvider).status, TimerStatus.idle);
    });

    test('暂停时不可标记；恢复后可继续', () async {
      final c = await _container();
      final controller = c.read(timerProvider.notifier);
      controller.setTotal(const Duration(seconds: 30));
      controller.start();
      controller.pause();
      expect(c.read(timerProvider).status, TimerStatus.paused);
      controller.addMark();
      expect(c.read(timerProvider).marks, isEmpty);

      controller.resume();
      controller.addMark();
      expect(c.read(timerProvider).marks.length, 1);
      controller.cancel();
    });

    test('删除标记后其余序号不变，备注可更新', () async {
      final c = await _container();
      final controller = c.read(timerProvider.notifier);
      controller.setTotal(const Duration(seconds: 60));
      controller.start();
      controller.addMark();
      controller.addMark();
      controller.addMark();
      controller.updateMark(2, note: '资料分析');
      expect(c.read(timerProvider).marks[1].note, '资料分析');

      controller.removeMark(1);
      final marks = c.read(timerProvider).marks;
      expect(marks.map((m) => m.seq), [2, 3]);
      expect(marks[0].note, '资料分析');
      controller.cancel();
    });

    test('修改剩余时间：已进行按 总时长-剩余 重算（含历史联动）', () async {
      final c = await _container();
      final timer = c.read(timerProvider.notifier);
      timer.setTotal(const Duration(minutes: 10));
      timer.start();
      timer.addMark(); // seq 1
      timer.updateMark(1, remaining: const Duration(minutes: 8), note: '改');
      final m = c.read(timerProvider).marks.single;
      expect(m.remaining, const Duration(minutes: 8));
      expect(m.elapsed, const Duration(minutes: 2), reason: '已进行应=总时长-剩余');
      expect(m.note, '改');

      await timer.saveToHistory('联动');
      timer.updateMark(1, remaining: const Duration(minutes: 5));
      final saved = c.read(historyProvider).single.marks.single;
      expect(saved.remaining, const Duration(minutes: 5));
      expect(saved.elapsed, const Duration(minutes: 5));
      timer.cancel();
    });
  });

  group('PresetsController 无限预设', () {
    test('开始使用/设置添加均置顶去重，数量不限（出厂默认保留）', () async {
      final c = await _container();
      final controller = c.read(presetsProvider.notifier);
      for (var i = 1; i <= 8; i++) {
        await controller.recordUse(Duration(minutes: i));
      }
      // 8 条使用记录 + 3 条出厂默认（10/25/60 分钟），不截断。
      expect(c.read(presetsProvider).length, 11);
      await controller.recordUse(const Duration(minutes: 3)); // 去重置顶
      final list = c.read(presetsProvider);
      expect(list.first, const Duration(minutes: 3));
      expect(list.where((d) => d == const Duration(minutes: 3)).length, 1);

      await controller.addPreset(const Duration(hours: 2)); // 设置添加置前
      expect(c.read(presetsProvider).first, const Duration(hours: 2));
    });

    test('拖动排序与删除（DragTarget 语义：拖到目标格、其余顺延）', () async {
      final c = await _container();
      final controller = c.read(presetsProvider.notifier);
      await controller.recordUse(const Duration(minutes: 1));
      await controller.recordUse(const Duration(minutes: 2));
      await controller.recordUse(const Duration(minutes: 3));
      // [3, 2, 1, 默认…]：把第 0 项（3 分）拖到"1 分"格上（index 2）→ [2, 1, 3, …]
      await controller.reorder(0, 2);
      expect(
        c.read(presetsProvider).take(3),
        const [Duration(minutes: 2), Duration(minutes: 1), Duration(minutes: 3)],
      );
      // 把第 2 项（3 分）拖回最前（index 0）
      await controller.reorder(2, 0);
      expect(c.read(presetsProvider).first, const Duration(minutes: 3));
      await controller.removeAt(0);
      expect(c.read(presetsProvider).first, const Duration(minutes: 2));
    });

    test('启动时从持久化恢复（v2 键）', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('preset_list_seconds_v2', ['600', '1500']);
      final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      expect(c.read(presetsProvider), const [Duration(minutes: 10), Duration(minutes: 25)]);
    });
  });

  group('历史记录与会话联动', () {
    test('保存 → 后续标记自动追加 → 覆盖更新 → 重命名 → 删除', () async {
      final c = await _container();
      final timer = c.read(timerProvider.notifier);
      timer.setTotal(const Duration(seconds: 10));
      timer.start();
      timer.addMark();

      await timer.saveToHistory('测试记录');
      var history = c.read(historyProvider);
      expect(history.length, 1);
      expect(history.single.name, '测试记录');
      expect(history.single.marks.length, 1);

      // 同会话再标记：自动追加到同一条
      timer.addMark();
      history = c.read(historyProvider);
      expect(history.single.marks.length, 2);

      // 同会话再点保存：覆盖更新而非新建
      await timer.saveToHistory('改名');
      expect(c.read(historyProvider).length, 1);
      expect(c.read(historyProvider).single.name, '改名');
      expect(c.read(historyProvider).single.marks.length, 2);

      // 会话结束后标记不再联动
      timer.cancel();
      expect(c.read(historyProvider).single.marks.length, 2);

      final id = history.single.id;
      await c.read(historyProvider.notifier).rename(id, '新名字');
      expect(c.read(historyProvider).single.name, '新名字');
      await c.read(historyProvider.notifier).deleteMany({id});
      expect(c.read(historyProvider), isEmpty);
    });

    test('重新开始后保存会新建条目', () async {
      final c = await _container();
      final timer = c.read(timerProvider.notifier);
      timer.setTotal(const Duration(seconds: 10));
      timer.start();
      timer.addMark();
      await timer.saveToHistory('第一次');

      timer.cancel();
      timer.setTotal(const Duration(seconds: 20));
      timer.start();
      timer.addMark();
      await timer.saveToHistory('第二次');
      expect(c.read(historyProvider).length, 2);
      expect(c.read(historyProvider).first.name, '第二次');
      expect(c.read(historyProvider).first.total, const Duration(seconds: 20));
      timer.cancel();
    });

    test('历史条目被删除后再保存：回落新建（bug 回归）', () async {
      final c = await _container();
      final timer = c.read(timerProvider.notifier);
      timer.setTotal(const Duration(seconds: 10));
      timer.start();
      timer.addMark();
      await timer.saveToHistory('被删的');
      final id = c.read(historyProvider).single.id;

      // 用户在历史页删除了联动条目（计时未停）
      await c.read(historyProvider.notifier).deleteMany({id});
      expect(c.read(historyProvider), isEmpty);

      // 再点保存：应新建条目，且后续标记继续自动追加
      timer.addMark();
      await timer.saveToHistory('重新保存');
      var history = c.read(historyProvider);
      expect(history.length, 1);
      expect(history.single.name, '重新保存');

      timer.addMark();
      history = c.read(historyProvider);
      expect(history.single.marks.length, 3, reason: '新建后自动追加应恢复');
      timer.cancel();
    });
  });

  group('SettingsController 持久化', () {
    test('出厂默认阈值 30/10 分；用户删空后保持为空', () async {
      final c = await _container();
      expect(c.read(settingsProvider).thresholds.map((r) => r.seconds), [1800, 600]);
      await c.read(settingsProvider.notifier).removeThreshold(1800);
      await c.read(settingsProvider.notifier).removeThreshold(600);
      expect(c.read(settingsProvider).thresholds, isEmpty, reason: '主动删空后默认值不应再冒出');
    });

    test('阈值排序（含默认值）', () async {
      final c = await _container();
      final controller = c.read(settingsProvider.notifier);
      await controller.addThreshold(10, null);
      await controller.addThreshold(30, null);
      final thresholds = c.read(settingsProvider).thresholds;
      expect(thresholds.map((r) => r.seconds).toList(), [1800, 600, 30, 10]);
    });
  });
}
