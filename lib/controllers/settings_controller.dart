import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/shared_prefs_provider.dart';

// 简单日志出口（避免在纯逻辑层引入 flutter 依赖）。
void debugLog(String msg) {
  // ignore: avoid_print
  print(msg);
}

/// 剩余时间提醒阈值：剩余 [seconds] 秒时提示一次，[audioPath] 为空表示系统提示音。
class ReminderRule {
  const ReminderRule({required this.seconds, this.audioPath});

  final int seconds;
  final String? audioPath;

  Map<String, dynamic> toJson() => {'s': seconds, 'a': audioPath};

  factory ReminderRule.fromJson(Map<String, dynamic> json) => ReminderRule(
        seconds: (json['s'] as num).toInt(),
        audioPath: json['a'] as String?,
      );
}

class SettingsState {
  const SettingsState({
    this.ringAudioPath,
    this.ringVibrate = true,
    this.reminderVibrate = true,
    this.dndEnabled = false,
    this.dndLiftOnRing = false,
    this.fakeSleepEnabled = true,
    this.idleTimeoutSec = 60,
    this.thresholds = const [],
    this.examModeEnabled = false,
    this.notifGuideDone = false,
    this.overlayGuideDone = false,
  });

  /// 结束铃声：null = 系统闹钟声；否则为应用私有目录的音频文件路径。
  final String? ringAudioPath;
  final bool ringVibrate;
  final bool reminderVibrate;
  final bool dndEnabled;
  final bool dndLiftOnRing;
  final bool fakeSleepEnabled;
  final int idleTimeoutSec;
  final List<ReminderRule> thresholds;

  /// 考试模式：开始/剩余15分/最后10秒播放专用音频，普通阈值提醒停用。
  final bool examModeEnabled;
  final bool notifGuideDone;
  final bool overlayGuideDone;

  /// 同步从已初始化的 prefs 构造（main 中保证 SharedPreferences 已就绪）。
  factory SettingsState.load(SharedPreferences prefs) {
    final thresholdsRaw = prefs.getString(_kThresholds);
    List<ReminderRule> thresholds = const [];
    if (thresholdsRaw != null) {
      thresholds = (jsonDecode(thresholdsRaw) as List)
          .map((e) => ReminderRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      // 出厂默认阈值：剩余 30 分 / 10 分各提醒一次（用户主动删空后不会再冒出）。
      thresholds = const [
        ReminderRule(seconds: 30 * 60),
        ReminderRule(seconds: 10 * 60),
      ];
    }
    return SettingsState(
      ringAudioPath: prefs.getString(_kRingAudio),
      ringVibrate: prefs.getBool(_kRingVibrate) ?? true,
      reminderVibrate: prefs.getBool(_kReminderVibrate) ?? true,
      dndEnabled: prefs.getBool(_kDnd) ?? false,
      dndLiftOnRing: prefs.getBool(_kDndLift) ?? false,
      fakeSleepEnabled: prefs.getBool(_kFakeSleep) ?? true,
      idleTimeoutSec: prefs.getInt(_kIdleTimeout) ?? 60,
      thresholds: thresholds,
      examModeEnabled: prefs.getBool(_kExamMode) ?? false,
      notifGuideDone: prefs.getBool(_kGuideNotif) ?? false,
      overlayGuideDone: prefs.getBool(_kGuideOverlay) ?? false,
    );
  }

  SettingsState copyWith({
    String? ringAudioPath,
    bool? ringVibrate,
    bool? reminderVibrate,
    bool? dndEnabled,
    bool? dndLiftOnRing,
    bool? fakeSleepEnabled,
    int? idleTimeoutSec,
    List<ReminderRule>? thresholds,
    bool? examModeEnabled,
    bool? notifGuideDone,
    bool? overlayGuideDone,
  }) {
    return SettingsState(
      ringAudioPath: ringAudioPath ?? this.ringAudioPath,
      ringVibrate: ringVibrate ?? this.ringVibrate,
      reminderVibrate: reminderVibrate ?? this.reminderVibrate,
      dndEnabled: dndEnabled ?? this.dndEnabled,
      dndLiftOnRing: dndLiftOnRing ?? this.dndLiftOnRing,
      fakeSleepEnabled: fakeSleepEnabled ?? this.fakeSleepEnabled,
      idleTimeoutSec: idleTimeoutSec ?? this.idleTimeoutSec,
      thresholds: thresholds ?? this.thresholds,
      examModeEnabled: examModeEnabled ?? this.examModeEnabled,
      notifGuideDone: notifGuideDone ?? this.notifGuideDone,
      overlayGuideDone: overlayGuideDone ?? this.overlayGuideDone,
    );
  }
}

class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    // 同步读取：main 已完成 SharedPreferences 初始化。
    return SettingsState.load(ref.read(sharedPrefsProvider));
  }

  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  Future<void> setRingAudio(String? path) async {
    state = state.copyWith(ringAudioPath: path);
    if (path == null) {
      await _prefs.remove(_kRingAudio);
    } else {
      await _prefs.setString(_kRingAudio, path);
    }
  }

  Future<void> setRingVibrate(bool v) async {
    state = state.copyWith(ringVibrate: v);
    await _prefs.setBool(_kRingVibrate, v);
  }

  Future<void> setReminderVibrate(bool v) async {
    state = state.copyWith(reminderVibrate: v);
    await _prefs.setBool(_kReminderVibrate, v);
  }

  Future<void> setDndEnabled(bool v) async {
    state = state.copyWith(dndEnabled: v);
    await _prefs.setBool(_kDnd, v);
  }

  Future<void> setDndLiftOnRing(bool v) async {
    state = state.copyWith(dndLiftOnRing: v);
    await _prefs.setBool(_kDndLift, v);
  }

  Future<void> setFakeSleepEnabled(bool v) async {
    state = state.copyWith(fakeSleepEnabled: v);
    await _prefs.setBool(_kFakeSleep, v);
  }

  Future<void> setIdleTimeoutSec(int v) async {
    state = state.copyWith(idleTimeoutSec: v);
    await _prefs.setInt(_kIdleTimeout, v);
  }

  Future<void> addThreshold(int seconds, String? audioPath) async {
    final next = [...state.thresholds, ReminderRule(seconds: seconds, audioPath: audioPath)]
      ..sort((a, b) => b.seconds.compareTo(a.seconds));
    state = state.copyWith(thresholds: next);
    await _prefs.setString(_kThresholds, jsonEncode(next.map((r) => r.toJson()).toList()));
  }

  Future<void> removeThreshold(int seconds) async {
    final next = state.thresholds.where((r) => r.seconds != seconds).toList();
    state = state.copyWith(thresholds: next);
    await _prefs.setString(_kThresholds, jsonEncode(next.map((r) => r.toJson()).toList()));
  }

  Future<void> setExamModeEnabled(bool v) async {
    state = state.copyWith(examModeEnabled: v);
    await _prefs.setBool(_kExamMode, v);
  }

  Future<void> markNotifGuideDone() async {
    state = state.copyWith(notifGuideDone: true);
    await _prefs.setBool(_kGuideNotif, true);
  }

  Future<void> markOverlayGuideDone() async {
    state = state.copyWith(overlayGuideDone: true);
    await _prefs.setBool(_kGuideOverlay, true);
  }
}

const String _kRingAudio = 'ring_audio';
const String _kRingVibrate = 'ring_vibrate';
const String _kReminderVibrate = 'reminder_vibrate';
const String _kDnd = 'dnd_enabled';
const String _kDndLift = 'dnd_lift_on_ring';
const String _kFakeSleep = 'fake_sleep_enabled';
const String _kIdleTimeout = 'idle_timeout_sec';
const String _kThresholds = 'reminder_thresholds';
const String _kExamMode = 'exam_mode_enabled';
const String _kGuideNotif = 'guide_notif_done';
const String _kGuideOverlay = 'guide_overlay_done';

final settingsProvider = NotifierProvider<SettingsController, SettingsState>(SettingsController.new);
