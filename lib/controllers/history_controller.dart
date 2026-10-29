import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/history_entry.dart';
import '../models/time_mark.dart';
import '../services/shared_prefs_provider.dart';

const String _kHistory = 'history_entries_json';

/// 历史记录：保存自计时页「保存」按钮；同会话自动追加由 TimerController 调用 [syncSession]。
/// 存储用 SharedPreferences JSON（条目数量不限，按保存时间倒序）。
class HistoryController extends Notifier<List<HistoryEntry>> {
  @override
  List<HistoryEntry> build() {
    final prefs = ref.read(sharedPrefsProvider);
    final raw = prefs.getString(_kHistory);
    if (raw == null || raw.isEmpty) return const [];
    final restored = (jsonDecode(raw) as List)
        .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    restored.sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
    return restored;
  }

  Future<void> _persist() async {
    await ref
        .read(sharedPrefsProvider)
        .setString(_kHistory, jsonEncode(state.map((e) => e.toJson()).toList()));
  }

  /// 首次保存（返回新条目 id）；同会话后续保存/追加走 [syncSession]。
  Future<String> create({required String name, required Duration total, required List<TimeMark> marks}) async {
    final entry = HistoryEntry(
      id: 'h${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      savedAtMs: DateTime.now().millisecondsSinceEpoch,
      total: total,
      marks: marks,
    );
    state = [entry, ...state];
    await _persist();
    return entry.id;
  }

  /// 会话内标记变化后同步到已保存的条目（覆盖更新，直到会话重置）；
  /// 再次点「保存」时同时更新名称。返回 false 表示条目已被用户删除。
  Future<bool> syncSession(String id, {required Duration total, required List<TimeMark> marks, String? name}) async {
    var found = false;
    final next = <HistoryEntry>[];
    for (final e in state) {
      if (e.id == id) {
        found = true;
        next.add(e.copyWith(name: name, total: total, marks: marks));
      } else {
        next.add(e);
      }
    }
    if (!found) return false;
    state = next;
    await _persist();
    return true;
  }

  Future<void> rename(String id, String name) async {
    state = [for (final e in state) if (e.id == id) e.copyWith(name: name) else e];
    await _persist();
  }

  /// 编辑历史条目内某条标记（v3.6：展开后每项可点击编辑）：
  /// 修改剩余时间节点（已进行按 总时长-剩余 重算）与备注。
  Future<void> updateMark(String id, int seq, {Duration? remaining, String? note}) async {
    Duration? recompute(Duration total) => remaining == null ? null : total - remaining;
    state = [
      for (final e in state)
        if (e.id == id)
          e.copyWith(marks: [
            for (final m in e.marks)
              if (m.seq == seq)
                m.copyWith(remaining: remaining, elapsed: recompute(e.total), note: note)
              else
                m,
          ])
        else
          e,
    ];
    await _persist();
  }

  /// 删除历史条目内某条标记（其余序号保持不变）。
  Future<void> removeMark(String id, int seq) async {
    state = [
      for (final e in state)
        if (e.id == id)
          e.copyWith(marks: e.marks.where((m) => m.seq != seq).toList())
        else
          e,
    ];
    await _persist();
  }

  Future<void> deleteMany(Set<String> ids) async {
    state = state.where((e) => !ids.contains(e.id)).toList();
    await _persist();
  }
}

final historyProvider = NotifierProvider<HistoryController, List<HistoryEntry>>(HistoryController.new);
