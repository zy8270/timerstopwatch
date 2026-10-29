import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timerstopwatch/main.dart' as app;
import 'package:timerstopwatch/ui/widgets/fake_sleep_layer.dart';

/// 端到端冒烟：预设 → 开始 → 标记 → 暂停/继续 → 阈值提醒 → 结束 → 关闭铃声 → 返回 → 取消二次确认。
/// 倒计时界面持续刷新，不能用 pumpAndSettle，统一用轮询 + 固定 pump。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('核心流程端到端', (tester) async {
    Future<void> pumpMs(int ms) async {
      await tester.pump(Duration(milliseconds: ms));
    }

    /// 轮询等待用真实时间（live 模式下 pump 的时长参数不保证真实流逝）。
    Future<void> waitMs(int ms) async {
      await Future.delayed(Duration(milliseconds: ms));
      await tester.pump();
    }

    // 测试自足准备：清掉上次运行残留（历史记录等持久化数据跨运行保留），
    // 再写入：预设（20 秒）、提醒阈值（剩余 5 秒，即第 15 秒）、假睡眠空闲 3 秒进入。
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setStringList('preset_list_seconds_v2', ['20']);
    await prefs.setString('reminder_thresholds', '[{"s":5,"a":null}]');
    await prefs.setInt('idle_timeout_sec', 3);

    app.main();

    // 冷启动轮询等待首页
    var booted = false;
    for (var i = 0; i < 60; i++) {
      await waitMs(500);
      if (find.text('开始').evaluate().isNotEmpty) {
        booted = true;
        break;
      }
    }
    expect(booted, isTrue, reason: 'App 首页未出现');

    // 预设 Wrap 自动换行，无需横向滚动
    expect(find.text('00:20'), findsOneWidget, reason: '预设 00:20 未显示');
    await tester.tap(find.text('00:20'));
    await pumpMs(300);
    await tester.tap(find.text('开始'));
    for (var i = 0; i < 30; i++) {
      await waitMs(300);
      if (find.widgetWithText(FilledButton, '暂停').evaluate().isNotEmpty) break;
    }
    expect(find.widgetWithText(FilledButton, '暂停'), findsOneWidget, reason: '未进入运行界面');

    // ---- 标记 ----
    await tester.tap(find.widgetWithText(OutlinedButton, '标记'));
    await pumpMs(500);
    expect(find.text('01'), findsOneWidget, reason: '标记后列表无 01');

    // ---- 暂停 / 继续 ----
    await tester.tap(find.widgetWithText(FilledButton, '暂停'));
    await pumpMs(500);
    expect(find.text('已暂停'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await pumpMs(500);

    // ---- 假睡眠：无操作 3 秒自动进入 ----
    var sleepShown = false;
    for (var i = 0; i < 25; i++) {
      await waitMs(400);
      final byKey = find.byKey(const Key('fakeSleepTime')).evaluate().length;
      final byType = find.byType(FakeSleepLayer).evaluate().length;
      if (i % 4 == 0) {
        // ignore: avoid_print
        print('E2E sleep poll i=$i byKey=$byKey byType=$byType');
      }
      if (byKey > 0) {
        sleepShown = true;
        break;
      }
    }
    expect(sleepShown, isTrue, reason: '无操作 3 秒未进入假睡眠');

    // ---- 等待阈值提醒（剩 5 秒）与结束（20 秒）----
    var finished = false;
    for (var i = 0; i < 80; i++) {
      await waitMs(300);
      if (find.text('倒计时结束').evaluate().isNotEmpty) {
        finished = true;
        break;
      }
    }
    expect(finished, isTrue, reason: '20 秒倒计时未结束');
    expect(find.text('01'), findsOneWidget, reason: '结束界面标记丢失');
    expect(find.byKey(const Key('fakeSleepTime')), findsNothing, reason: '结束后未退出假睡眠');

    // ---- 保存到历史记录：默认名（日期+时间）→ 确定 ----
    await tester.tap(find.text('保存'));
    await pumpMs(500);
    expect(find.text('保存到历史记录'), findsOneWidget, reason: '保存命名窗口未弹出');
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await pumpMs(300);
    expect(find.text('已保存到历史记录，后续标记将自动追加'), findsOneWidget, reason: '保存后无提示');
    // 等 SnackBar（2 秒）消失，避免遮挡底部按钮
    await waitMs(2500);

    // ---- 关闭铃声 / 返回 ----
    await tester.tap(find.widgetWithText(FilledButton, '关闭铃声'));
    await pumpMs(500);
    await tester.tap(find.widgetWithText(OutlinedButton, '返回修改时长'));
    for (var i = 0; i < 30; i++) {
      await waitMs(300);
      if (find.text('开始').evaluate().isNotEmpty) break;
    }
    expect(find.text('开始'), findsOneWidget, reason: '未返回时长选择');

    // ---- 取消需二次确认（有标记时）----
    await tester.tap(find.text('00:20'));
    await pumpMs(300);
    await tester.tap(find.text('开始'));
    for (var i = 0; i < 30; i++) {
      await waitMs(300);
      if (find.widgetWithText(FilledButton, '暂停').evaluate().isNotEmpty) break;
    }
    await tester.tap(find.widgetWithText(OutlinedButton, '标记'));
    await pumpMs(500);
    await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
    await pumpMs(500);
    expect(find.text('取消倒计时？'), findsOneWidget, reason: '有标记时取消未弹确认');
    await tester.tap(find.text('继续计时'));
    await pumpMs(500);
    expect(find.widgetWithText(FilledButton, '暂停'), findsOneWidget, reason: '继续计时后未恢复运行');
    await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
    await pumpMs(500);
    await tester.tap(find.text('确认取消'));
    for (var i = 0; i < 30; i++) {
      await waitMs(300);
      if (find.text('开始').evaluate().isNotEmpty) break;
    }
    expect(find.text('开始'), findsOneWidget, reason: '确认取消后未回到未开始');

    // ---- 历史记录页：刚保存的条目可展开查看 ----
    await tester.tap(find.text('历史'));
    await pumpMs(500);
    final tile = find.textContaining('总时长 00:00:20 · 1 条标记');
    expect(tile, findsOneWidget, reason: '历史页无刚保存的记录');
    await tester.tap(tile);
    await pumpMs(500);
    expect(find.textContaining('倒计时总时间'), findsOneWidget, reason: '展开后无总时间行');
    expect(find.text('01'), findsOneWidget, reason: '展开后无标记行');
  });
}
