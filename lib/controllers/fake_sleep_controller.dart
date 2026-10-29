import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_controller.dart';
import 'timer_controller.dart';

class FakeSleepState {
  const FakeSleepState({this.active = false, this.reEntrySec});

  final bool active;

  /// 非空时，本次唤醒后的重新进入时长（阈值提醒触发的短唤醒用 30 秒）。
  final int? reEntrySec;
}

/// 假睡眠常亮模式：仅倒计时状态生效；进入 = 全屏沉浸 + 纯黑底暗字；退出 = 恢复系统栏。
/// （v3.6 定案：此前的"黄线"并非 OLED 低亮度串扰，而是覆盖层无 Material 祖先时
/// MaterialApp 注入的黄色双下划线 fallback 样式——修复见 fake_sleep_layer.dart。）
class FakeSleepController extends Notifier<FakeSleepState> {
  @override
  FakeSleepState build() {
    return const FakeSleepState();
  }

  Future<void> enter() async {
    if (state.active) return;
    final timer = ref.read(timerProvider);
    final settings = ref.read(settingsProvider);
    if (!timer.isSessionActive || !settings.fakeSleepEnabled) return;
    debugLog('[fakeSleep] enter');
    state = const FakeSleepState(active: true);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // 不再压窗口亮度：vivo OLED 低亮度时亮字下方会出现黄绿串扰线（实机截图定位：
    // 线紧贴文字底缘、比文字宽、下方立即纯黑）。改为纯黑底 + 暗文字（OLED 黑像素
    // 不发光，观感与耗电不受系统亮度影响），面板始终工作在正常亮度档位。
  }

  Future<void> exit({int? reEntrySec}) async {
    if (!state.active) return;
    debugLog('[fakeSleep] exit reEntry=$reEntrySec');
    state = FakeSleepState(active: false, reEntrySec: reEntrySec);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// 用户正常操作退出后清除短唤醒标记。
  void clearReEntry() {
    if (state.reEntrySec != null) state = const FakeSleepState(active: false);
  }
}

final fakeSleepProvider = NotifierProvider<FakeSleepController, FakeSleepState>(FakeSleepController.new);
