import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/time_mark.dart';
import '../services/native_channel.dart';
import 'fake_sleep_controller.dart';
import 'history_controller.dart';
import 'settings_controller.dart';

void _log(String msg) => debugPrint('[timer] $msg');

/// 平台通道不可用（单元测试等）时静默降级。
void _setWakelock(bool on) {
  (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((Object _) {});
}

enum TimerStatus { idle, running, paused, finished }

/// 计时会话状态。剩余时间一律由状态机按单调时钟推算，UI 只读 [remaining]。
class TimerState {
  const TimerState({
    required this.status,
    required this.total,
    this.remaining = Duration.zero,
    this.marks = const [],
    this.reminderBanner,
  });

  final TimerStatus status;

  /// 本次会话的总时长（结束界面"重新开始"沿用）。
  final Duration total;

  /// 当前剩余时间（运行中由 ticker 刷新）。
  final Duration remaining;

  /// 时间段标记（按先后排序）。
  final List<TimeMark> marks;

  /// 当前阈值提醒横幅文案（自动消失）。
  final String? reminderBanner;

  bool get isSessionActive => status == TimerStatus.running || status == TimerStatus.paused;

  TimerState copyWith({
    TimerStatus? status,
    Duration? total,
    Duration? remaining,
    List<TimeMark>? marks,
    String? reminderBanner,
    bool clearBanner = false,
  }) {
    return TimerState(
      status: status ?? this.status,
      total: total ?? this.total,
      remaining: remaining ?? this.remaining,
      marks: marks ?? this.marks,
      reminderBanner: clearBanner ? null : (reminderBanner ?? this.reminderBanner),
    );
  }
}

/// 计时核心：开始/暂停/继续/取消/标记。
///
/// - 时间口径：[Stopwatch]（单调时钟）差值推算，暂停即冻结累计值，
///   不受手动修改系统时间影响；周期 ticker 只驱动刷新与到点判定。
/// - 前台服务与勿扰由本控制器在状态切换时同步到原生侧。
class TimerController extends Notifier<TimerState> {
  Stopwatch? _sw;
  Duration _accumulated = Duration.zero;
  Timer? _ticker;
  Timer? _bannerTimer;
  final Set<int> _firedThresholds = {};
  bool _dndSession = false;

  /// 本会话已保存到历史记录的条目 id：
  /// 非空时，后续所有标记的增删改自动同步进该条目，直到会话重置（取消/重新开始/新开始）。
  String? _sessionHistoryId;

  @override
  TimerState build() {
    ref.onDispose(_stopTicking);
    return TimerState(
      status: TimerStatus.idle,
      total: const Duration(hours: 1),
      remaining: const Duration(hours: 1),
    );
  }

  // ---------- 会话控制 ----------

  /// 未开始时由滚轮/预设设置时长。
  void setTotal(Duration d) {
    if (state.status != TimerStatus.idle || d <= Duration.zero) return;
    _log('setTotal $d');
    state = TimerState(status: TimerStatus.idle, total: d, remaining: d);
  }

  void start() {
    if (state.total <= Duration.zero) return;
    _log('start total=${state.total}');
    _accumulated = Duration.zero;
    _firedThresholds.clear();
    _sessionHistoryId = null;
    _sw = Stopwatch()..start();
    state = TimerState(status: TimerStatus.running, total: state.total, remaining: state.total);
    _startTicking();
    _syncServiceStart();
    _startDndIfEnabled();
    // 常亮：整个倒计时会话期间（进行中或暂停）保持屏幕常亮。
    _setWakelock(true);
  }

  void pause() {
    if (state.status != TimerStatus.running) return;
    _log('pause');
    _accumulated += _sw?.elapsed ?? Duration.zero;
    _sw?.stop();
    _stopTicking();
    state = state.copyWith(status: TimerStatus.paused, remaining: state.total - _accumulated);
    NativeChannel.servicePause(state.remaining.inMilliseconds);
  }

  void resume() {
    if (state.status != TimerStatus.paused) return;
    _log('resume');
    _sw = Stopwatch()..start();
    state = state.copyWith(status: TimerStatus.running);
    _startTicking();
    _syncServiceResume();
  }

  /// 取消本次倒计时，回到未开始（保留当前所选总时长）。
  void cancel() {
    _log('cancel');
    // 结束界面"返回修改时长"走这里：必须先停掉闹铃（此前漏停导致返回后铃声继续）。
    NativeChannel.ringStop();
    _stopTicking();
    _sw?.stop();
    _sw = null;
    _accumulated = Duration.zero;
    _sessionHistoryId = null; // 会话结束：历史条目保留，后续标记不再追加
    state = TimerState(status: TimerStatus.idle, total: state.total, remaining: state.total);
    NativeChannel.serviceStop();
    _endDnd();
    _setWakelock(false);
  }

  /// 关闭结束铃声（App 内按钮）。
  void silenceRing() {
    NativeChannel.ringStop();
    NativeChannel.serviceStop();
    _endDnd();
    _setWakelock(false);
  }

  /// 结束界面"重新开始"：沿用同一总时长。
  void restart() {
    silenceRing();
    start();
  }

  // ---------- 标记 ----------

  /// 运行中标记一个时间节点（不打断计时）。暂停状态不可标记。
  void addMark() {
    if (state.status != TimerStatus.running) return;
    final elapsed = _accumulated + (_sw?.elapsed ?? Duration.zero);
    final remaining = state.total - elapsed;
    _log('mark seq=${state.marks.length + 1} remaining=$remaining elapsed=$elapsed');
    final mark = TimeMark(
      seq: state.marks.length + 1,
      remaining: remaining,
      elapsed: elapsed,
    );
    state = state.copyWith(marks: [...state.marks, mark]);
    NativeChannel.serviceLastMark(elapsed.inMilliseconds);
    _syncHistory();
  }

  /// 通知「标记」按钮回调。
  void onNotificationMark() => addMark();

  /// 撤销最近一条标记。
  void undoMark() {
    if (state.marks.isEmpty) return;
    final next = [...state.marks]..removeLast();
    state = state.copyWith(marks: next);
    final lastElapsed = next.isEmpty ? -1 : next.last.elapsed.inMilliseconds;
    NativeChannel.serviceLastMark(lastElapsed);
    _syncHistory();
  }

  /// 编辑某条标记：可修改剩余时间节点（已进行按 总时长-剩余 自动重算）与备注。
  void updateMark(int seq, {Duration? remaining, String? note}) {
    state = state.copyWith(marks: [
      for (final m in state.marks)
        if (m.seq == seq)
          m.copyWith(
            remaining: remaining,
            elapsed: remaining == null ? null : state.total - remaining,
            note: note,
          )
        else
          m,
    ]);
    _syncHistory();
  }

  /// 删除某条标记（其余序号保持不变）。
  void removeMark(int seq) {
    state = state.copyWith(marks: state.marks.where((m) => m.seq != seq).toList());
    _syncHistory();
  }

  // ---------- 保存到历史记录 ----------

  /// 是否已在本会话保存过（决定再点「保存」是覆盖更新还是新建）。
  String? get sessionHistoryId => _sessionHistoryId;

  /// 「保存」按钮：首次创建历史条目；已保存过则覆盖更新（含改名），并开启后续自动追加。
  /// 若联动条目已被用户在历史页删除（bug 修复），回落为新建，之后联动恢复。
  Future<void> saveToHistory(String name) async {
    if (state.marks.isEmpty) return;
    final id = _sessionHistoryId;
    if (id != null) {
      final ok = await ref.read(historyProvider.notifier).syncSession(
            id,
            total: state.total,
            marks: state.marks,
            name: name,
          );
      if (ok) return;
      _log('history entry $id gone, recreate');
    }
    _sessionHistoryId = await ref.read(historyProvider.notifier).create(
          name: name,
          total: state.total,
          marks: state.marks,
        );
    _log('history saved id=$_sessionHistoryId');
  }

  /// 会话内标记发生变化 → 自动同步到已保存的历史条目。
  void _syncHistory() {
    final id = _sessionHistoryId;
    if (id == null) return;
    ref.read(historyProvider.notifier).syncSession(
          id,
          total: state.total,
          marks: state.marks,
        );
  }

  // ---------- 原生事件回调 ----------

  /// 响铃通知上的「关闭铃声」被点击。
  void onRingStoppedExternally() {
    // 原生侧已停声、停服务、恢复勿扰；这里只兜底清状态。
    _endDnd();
    _setWakelock(false);
  }

  // ---------- 内部 ----------

  void _startTicking() {
    _stopTicking();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _onTick());
  }

  void _stopTicking() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _onTick() {
    if (state.status != TimerStatus.running) return;
    final elapsed = _accumulated + (_sw?.elapsed ?? Duration.zero);
    final remaining = state.total - elapsed;
    if (remaining <= Duration.zero) {
      _finish();
    } else {
      state = state.copyWith(remaining: remaining);
      _checkThresholds(remaining);
    }
  }

  void _finish() {
    _log('finish');
    _stopTicking();
    _sw?.stop();
    _sw = null;
    _accumulated = Duration.zero;
    state = state.copyWith(status: TimerStatus.finished, remaining: Duration.zero);
    final s = ref.read(settingsProvider);
    // 假睡眠中到点：先恢复亮度与系统栏再响铃（计划 Q3/Q5 决议）。
    ref.read(fakeSleepProvider.notifier).exit();
    // 前台路径响铃；后台/被杀路径由前台服务的原生 tick 与精确闹铃兜底。
    NativeChannel.ringStart(
      path: s.ringAudioPath,
      vibrate: s.ringVibrate,
      dndLift: s.dndEnabled && s.dndLiftOnRing,
    );
  }

  void _checkThresholds(Duration remaining) {
    final s = ref.read(settingsProvider);
    final totalSec = state.total.inSeconds;
    final remSec = remaining.inSeconds;
    for (final rule in s.thresholds) {
      if (rule.seconds <= 0 || rule.seconds >= totalSec) continue;
      if (_firedThresholds.contains(rule.seconds)) continue;
      if (remSec <= rule.seconds) {
        _firedThresholds.add(rule.seconds);
        _log('reminder fire at remaining=$remSec rule=${rule.seconds}s');
        NativeChannel.soundPlay(path: rule.audioPath, seconds: 5, vibrate: s.reminderVibrate);
        _showBanner('剩余 ${_fmtShort(Duration(seconds: rule.seconds))} 提醒');
      }
    }
  }

  void _showBanner(String text) {
    _bannerTimer?.cancel();
    // 假睡眠中触发阈值提醒：先唤醒（恢复亮屏），30 秒无操作后回到假睡眠（计划默认规则 4）。
    final fake = ref.read(fakeSleepProvider);
    if (fake.active) {
      ref.read(fakeSleepProvider.notifier).exit(reEntrySec: 30);
    }
    state = state.copyWith(reminderBanner: text);
    _bannerTimer = Timer(const Duration(seconds: 10), () {
      if (state.reminderBanner == text) {
        state = state.copyWith(clearBanner: true);
      }
    });
  }

  String _fmtShort(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '$h小时$m分';
    if (m > 0) return '$m分${s.toString().padLeft(2, '0')}秒';
    return '$s秒';
  }

  // ---------- 原生同步 ----------

  void _syncServiceStart() {
    final s = ref.read(settingsProvider);
    final endWall = DateTime.now().millisecondsSinceEpoch + state.total.inMilliseconds;
    _log('serviceStart endWallDelta=${state.total.inMilliseconds}ms dnd=${s.dndEnabled}');
    NativeChannel.serviceStart(
      endWallMs: endWall,
      totalMs: state.total.inMilliseconds,
      lastMarkMs: -1,
      ringPath: s.ringAudioPath,
      vibrate: s.ringVibrate,
      dndLift: s.dndEnabled && s.dndLiftOnRing,
    );
  }

  void _syncServiceResume() {
    final endWall = DateTime.now().millisecondsSinceEpoch + state.remaining.inMilliseconds;
    NativeChannel.serviceResume(endWall);
  }

  Future<void> _startDndIfEnabled() async {
    final s = ref.read(settingsProvider);
    if (!s.dndEnabled) return;
    if (!await NativeChannel.dndGranted()) return;
    await NativeChannel.dndSessionStart();
    _dndSession = true;
  }

  Future<void> _endDnd() async {
    if (!_dndSession) return;
    _dndSession = false;
    await NativeChannel.dndSessionEnd();
  }
}

final timerProvider = NotifierProvider<TimerController, TimerState>(TimerController.new);
