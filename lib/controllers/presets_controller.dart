import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/shared_prefs_provider.dart';

const List<Duration> _defaultPresets = [
  Duration(minutes: 10),
  Duration(minutes: 25),
  Duration(hours: 1),
];

/// 预设列表持久化键（v2：单一有序列表，数量不限）。
const String _presetKey = 'preset_list_seconds_v2';

/// 旧版键（v1：最近使用 5 条 + 自定义分存两处），仅用于一次性迁移。
const String _legacyRecentKey = 'recent_presets_seconds';
const String _legacyCustomKey = 'custom_presets_sec';

/// 快捷预设：单一有序列表，无限缓存。
/// - 开始倒计时 → 所用时长移到最前（最近使用置顶）。
/// - 设置页添加 → 插入到最前。
/// - 计时页长按拖动可手动排序，点角标删除。
class PresetsController extends Notifier<List<Duration>> {
  @override
  List<Duration> build() {
    final prefs = ref.read(sharedPrefsProvider);
    final raw = prefs.getStringList(_presetKey);
    if (raw != null) {
      final restored = raw
          .map(int.tryParse)
          .whereType<int>()
          .map((s) => Duration(seconds: s))
          .where((d) => d > Duration.zero)
          .toList();
      if (restored.isNotEmpty) return restored;
    }
    final migrated = _migrateLegacy(prefs);
    return migrated.isEmpty ? _defaultPresets : migrated;
  }

  /// v1 → v2 迁移：旧"最近使用"在前 + 旧"自定义预设"在后，去重。
  List<Duration> _migrateLegacy(SharedPreferences prefs) {
    final recents = (prefs.getStringList(_legacyRecentKey) ?? const [])
        .map(int.tryParse)
        .whereType<int>()
        .map((s) => Duration(seconds: s))
        .where((d) => d > Duration.zero);
    final customs = (prefs.getStringList(_legacyCustomKey) ?? const [])
        .map(int.tryParse)
        .whereType<int>()
        .map((s) => Duration(seconds: s))
        .where((d) => d > Duration.zero);
    final merged = <Duration>[];
    for (final d in [...recents, ...customs]) {
      if (!merged.contains(d)) merged.add(d);
    }
    return merged;
  }

  Future<void> _persist() async {
    await ref
        .read(sharedPrefsProvider)
        .setStringList(_presetKey, state.map((e) => e.inSeconds.toString()).toList());
  }

  /// 开始倒计时时记录：移到最前并去重（数量不限）。
  Future<void> recordUse(Duration d) => _moveToFront(d);

  /// 设置页添加固定预设：同样插入到最前（用户要求新增置前）。
  Future<void> addPreset(Duration d) => _moveToFront(d);

  Future<void> _moveToFront(Duration d) async {
    if (d <= Duration.zero) return;
    state = [d, ...state.where((x) => x != d)];
    await _persist();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= state.length) return;
    final next = [...state]..removeAt(index);
    state = next;
    await _persist();
  }

  /// 长按拖动排序（DragTarget 语义）：[newIndex] 是"目标格"在原列表中的位置，
  /// 即把 [oldIndex] 的预设放到目标格上、其余顺延（如 [A,B] 把 A 拖到 B 上 → [B,A]）。
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= state.length) return;
    final next = [...state];
    final item = next.removeAt(oldIndex);
    next.insert(newIndex.clamp(0, next.length), item);
    state = next;
    await _persist();
  }

  /// 拖动悬停过程的实时排序（拖影跟随手指、其余格避让）：
  /// 把预设 [d] 移到当前列表第 [targetIndex] 格。与落点提交语义一致，
  /// 每次悬停即提交，松手时无需再落盘。
  Future<void> movePresetTo(Duration d, int targetIndex) async {
    final old = state.indexOf(d);
    if (old < 0 || old == targetIndex) return;
    if (targetIndex < 0 || targetIndex >= state.length) return;
    await reorder(old, targetIndex);
  }
}

final presetsProvider = NotifierProvider<PresetsController, List<Duration>>(PresetsController.new);

/// 预设编辑模式（计时页长按预设激活）。
/// 放在全局 provider 上：NavShell 切换底部页签时也能把编辑状态退出（真机反馈）。
final presetEditingProvider = StateProvider<bool>((ref) => false);
