import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/time_mark.dart';
import '../services/native_channel.dart';
import '../services/shared_prefs_provider.dart';
import 'fake_sleep_controller.dart';
import 'history_controller.dart';
import 'settings_controller.dart';

void _log(String msg) => debugPrint('[timer] $msg');

/// 平台通道不可用（单元测试等）时静默降级。
void _setWakelock(bool on) {
  (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((Object _) {});
}

/// 考试模式：剩余 15 分钟提醒节点。
const int _kExamMidSec = 15 * 60;

/// 考试模式：结束音频长 10 秒，提前 10 秒（剩余 10 秒节点）播放。
const int _kExamEndAheadSec = 10;

/// 考试模式的固定提醒节点：总时长不大于节点时该节点忽略（与普通阈值口径一致）。
@visibleForTesting
List<int> examRulesFor(Duration total) {
  final t = total.inSeconds;
  return [
    if (_kExamMidSec < t) _kExamMidSec,
    if (_kExamEndAheadSec < t) _kExamEndAheadSec,
  ];
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

  /// 本会话是否为考试模式（开始时快照设置值，整场生效，中途改设置只影响下一场）。
  bool _examSession = false;

  /// 仅供测试：当前已触发的提醒节点（考试模式为 900/10）。
  @visibleForTesting
  Set<int> get firedThresholdsForTest => Set.of(_firedThresholds);

  /// 考试音频路径（start/mid15/end → 私有目录），首次使用时由原生侧从 assets 拷出。
  Map<String, String>? _examAudio;

  /// 本会话已保存到历史记录的条目 id：
  /// 非空时，后续所有标记的增删改自动同步进该条目，直到会话重置（取消/重新开始/新开始）。
  String? _sessionHistoryId;

  @override
  TimerState build() {
    ref.onDispose(_stopTicking);
    // 进程被杀后重启：恢复上次的运行/暂停会话（无快照则回到未开始）。
    return _restoreSession() ??
        TimerState(
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
    _examSession = ref.read(settingsProvider).examModeEnabled;
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
    _persistSession();
    if (_examSession) {
      // 开始考试：音频拷出后播放（拷贝失败回退系统提示音）。
      _prepareExamAudio().then((_) {
        if (state.status != TimerStatus.running) return;
        NativeChannel.soundPlay(path: _examAudio?['start'], seconds: 60, vibrate: false);
      });
    }
  }

  void pause() {
    if (state.status != TimerStatus.running) return;
    _log('pause');
    _accumulated += _sw?.elapsed ?? Duration.zero;
    _sw?.stop();
    _stopTicking();
    state = state.copyWith(status: TimerStatus.paused, remaining: state.total - _accumulated);
    NativeChannel.servicePause(state.remaining.inMilliseconds);
    _persistSession();
  }

  void resume() {
    if (state.status != TimerStatus.paused) return;
    _log('resume');
    _sw = Stopwatch()..start();
    state = state.copyWith(status: TimerStatus.running);
    _startTicking();
    _syncServiceResume();
    _persistSession();
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
    _clearSessionSnapshot(); // 会话结束：丢弃恢复快照
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
    _persistSession();
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
    _persistSession();
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
    _persistSession();
  }

  /// 删除某条标记（其余序号保持不变）。
  void removeMark(int seq) {
    state = state.copyWith(marks: state.marks.where((m) => m.seq != seq).toList());
    _syncHistory();
    _persistSession();
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
    _clearSessionSnapshot(); // 会话结束：丢弃恢复快照
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
    if (_examSession) {
      // 考试模式：只播考试音频（开始/剩15分/最后10秒），普通阈值整场停用。
      for (final rule in examRulesFor(state.total)) {
        if (_firedThresholds.contains(rule)) continue;
        if (remSec <= rule) {
          _firedThresholds.add(rule);
          _log('exam audio fire at remaining=$remSec rule=${rule}s');
          _persistSession();
          final isEnd = rule == _kExamEndAheadSec;
          NativeChannel.soundPlay(
            path: _examAudioPath(isEnd ? 'end' : 'mid15'),
            // 结束音频长 10 秒，留 2 秒余量避免尾音被截断。
            seconds: isEnd ? 12 : 60,
            vibrate: false,
          );
          _showBanner(isEnd ? '最后 10 秒 · 考试提醒' : '剩余 15 分钟 · 考试提醒');
        }
      }
      return;
    }
    for (final rule in s.thresholds) {
      if (rule.seconds <= 0 || rule.seconds >= totalSec) continue;
      if (_firedThresholds.contains(rule.seconds)) continue;
      if (remSec <= rule.seconds) {
        _firedThresholds.add(rule.seconds);
        _log('reminder fire at remaining=$remSec rule=${rule.seconds}s');
        _persistSession();
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

  // ---------- 会话快照：退出被杀后恢复 ----------

  static const String _kSessionSnapshot = 'timer_session_v1';

  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  /// 当前真实剩余（不依赖 200ms 一次的 UI 刷新值）。
  Duration get _liveRemaining =>
      state.total - (_accumulated + (_sw?.elapsed ?? Duration.zero));

  /// 把会话快照写入 prefs（运行中存结束时刻，暂停存剩余；被杀后据此恢复）。
  void _persistSession() {
    if (!state.isSessionActive) return;
    final remaining = _liveRemaining;
    _prefs.setString(
      _kSessionSnapshot,
      jsonEncode({
        'status': state.status == TimerStatus.running ? 'running' : 'paused',
        'totalMs': state.total.inMilliseconds,
        if (state.status == TimerStatus.running)
          'endWallMs': DateTime.now().millisecondsSinceEpoch + remaining.inMilliseconds
        else
          'remainingMs': remaining.inMilliseconds,
        'marks': [for (final m in state.marks) m.toJson()],
        'fired': _firedThresholds.toList(),
        if (_sessionHistoryId != null) 'historyId': _sessionHistoryId,
        'exam': _examSession,
      }),
    );
  }

  void _clearSessionSnapshot() {
    _prefs.remove(_kSessionSnapshot);
  }

  /// 启动时恢复被杀前的会话；无快照/已到点/数据损坏返回 null（回到未开始）。
  ///
  /// 注意：本方法运行于 build 阶段，禁止读写 [state]，副作用只经由
  /// 原生通道与定时器在 build 结束后生效。
  TimerState? _restoreSession() {
    final raw = _prefs.getString(_kSessionSnapshot);
    if (raw == null) return null;
    Map<String, dynamic> j;
    try {
      j = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      _clearSessionSnapshot();
      return null;
    }
    final total = Duration(milliseconds: (j['totalMs'] as num?)?.toInt() ?? 0);
    if (total <= Duration.zero) {
      _clearSessionSnapshot();
      return null;
    }
    List<TimeMark> marks;
    Set<int> fired;
    try {
      marks = [
        for (final e in (j['marks'] as List? ?? [])) TimeMark.fromJson((e as Map).cast<String, dynamic>()),
      ];
      fired = {
        for (final e in (j['fired'] as List? ?? const [])) (e as num).toInt(),
      };
    } catch (_) {
      _clearSessionSnapshot();
      return null;
    }
    final historyId = j['historyId'] as String?;
    final exam = (j['exam'] as bool?) ?? false;
    final status = j['status'] as String?;

    if (status == 'paused') {
      final remaining = Duration(milliseconds: (j['remainingMs'] as num?)?.toInt() ?? 0);
      if (remaining <= Duration.zero || remaining > total) {
        _clearSessionSnapshot();
        return null;
      }
      _log('restore paused total=$total remaining=$remaining marks=${marks.length} exam=$exam');
      _accumulated = total - remaining;
      _firedThresholds
        ..clear()
        ..addAll(fired);
      _sessionHistoryId = historyId;
      _examSession = exam;
      if (exam) _prepareExamAudio();
      _resyncNativeAfterRestore(remaining: remaining, total: total, marks: marks, paused: true);
      _scheduleBannerClear('已恢复上次暂停的计时');
      return TimerState(
        status: TimerStatus.paused,
        total: total,
        remaining: remaining,
        marks: marks,
        reminderBanner: '已恢复上次暂停的计时',
      );
    }

    if (status == 'running') {
      final endWall = (j['endWallMs'] as num?)?.toInt() ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (endWall <= now) {
        // 被杀期间已到点：响铃由精确闹铃兜底，Dart 侧回到未开始。
        _log('restore: already ended while dead, drop');
        _clearSessionSnapshot();
        return null;
      }
      final remaining = Duration(milliseconds: endWall - now);
      _log('restore running total=$total remaining=$remaining marks=${marks.length} exam=$exam');
      _accumulated = total - remaining;
      _firedThresholds
        ..clear()
        ..addAll(fired)
        // 被杀期间错过的提醒节点不补播，直接记为已触发。
        ..addAll(_missedRuleSeconds(total: total, remaining: remaining, exam: exam));
      _sessionHistoryId = historyId;
      _examSession = exam;
      if (exam) _prepareExamAudio();
      _sw = Stopwatch()..start();
      _startTicking();
      _resyncNativeAfterRestore(remaining: remaining, total: total, marks: marks, paused: false);
      _scheduleBannerClear('已恢复上次进行中的计时');
      return TimerState(
        status: TimerStatus.running,
        total: total,
        remaining: remaining,
        marks: marks,
        reminderBanner: '已恢复上次进行中的计时',
      );
    }

    _clearSessionSnapshot();
    return null;
  }

  /// 恢复时已错过、应记为已触发的提醒节点（剩余 ≤ 节点 < 总时长）。
  Iterable<int> _missedRuleSeconds({
    required Duration total,
    required Duration remaining,
    required bool exam,
  }) {
    final secs = exam ? examRulesFor(total) : ref.read(settingsProvider).thresholds.map((r) => r.seconds);
    final totalSec = total.inSeconds;
    final remSec = remaining.inSeconds;
    return secs.where((sec) => sec > 0 && sec < totalSec && sec >= remSec);
  }

  /// 恢复后重建原生侧联动：前台服务（暂停态通知/精确闹铃）、勿扰、常亮。
  void _resyncNativeAfterRestore({
    required Duration remaining,
    required Duration total,
    required List<TimeMark> marks,
    required bool paused,
  }) {
    final s = ref.read(settingsProvider);
    NativeChannel.serviceStart(
      endWallMs: DateTime.now().millisecondsSinceEpoch + remaining.inMilliseconds,
      totalMs: total.inMilliseconds,
      lastMarkMs: marks.isEmpty ? -1 : marks.last.elapsed.inMilliseconds,
      ringPath: s.ringAudioPath,
      vibrate: s.ringVibrate,
      dndLift: s.dndEnabled && s.dndLiftOnRing,
    );
    if (paused) NativeChannel.servicePause(remaining.inMilliseconds);
    if (s.dndEnabled) {
      _dndSession = true;
      // 进程死亡时勿扰可能还开着：先复位再接管，保证会话结束能恢复干净基线。
      NativeChannel.dndSessionRestart();
    }
    _setWakelock(true);
  }

  void _scheduleBannerClear(String text) {
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 10), () {
      if (state.reminderBanner == text) {
        state = state.copyWith(clearBanner: true);
      }
    });
  }

  /// 首次使用时把考试音频从 assets 拷到私有目录并缓存路径。
  Future<void> _prepareExamAudio() async {
    if (_examAudio != null) return;
    _examAudio = await NativeChannel.ensureExamAudio() ?? {};
  }

  String? _examAudioPath(String key) => _examAudio?[key];

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
