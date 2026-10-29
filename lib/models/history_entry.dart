import 'package:flutter/foundation.dart';

import 'time_mark.dart';
/// 一条历史记录：某次倒计时会话通过「保存」落盘的完整标记数据。
/// 同一会话内首次保存创建条目；之后该会话的标记增删改会自动同步更新（见 TimerController）。
@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.name,
    required this.savedAtMs,
    required this.total,
    this.marks = const [],
  });

  final String id;

  /// 用户命名（默认为保存时刻的 日期+时间）。
  final String name;

  /// 首次保存的时刻（毫秒时间戳）。
  final int savedAtMs;

  /// 该次倒计时的总时长。
  final Duration total;

  final List<TimeMark> marks;

  HistoryEntry copyWith({String? name, Duration? total, List<TimeMark>? marks}) {
    return HistoryEntry(
      id: id,
      name: name ?? this.name,
      savedAtMs: savedAtMs,
      total: total ?? this.total,
      marks: marks ?? this.marks,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'savedAtMs': savedAtMs,
        'totalMs': total.inMilliseconds,
        'marks': marks.map((m) => m.toJson()).toList(),
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        savedAtMs: (json['savedAtMs'] as num?)?.toInt() ?? 0,
        total: Duration(milliseconds: (json['totalMs'] as num?)?.toInt() ?? 0),
        marks: (json['marks'] as List? ?? [])
            .map((e) => TimeMark.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// 复制导出（纯文本 TSV）：名称 + 总时长 + 标记表。
  /// "已进行"列与界面同口径：第 1 条 = 自开始，之后 = 与上一条的间隔。
  String toExportText() {
    final buf = StringBuffer('$name\t总时长 ${_fmt(total)}');
    buf.writeln();
    buf.write('序号\t剩余\t已进行\t备注');
    for (var i = 0; i < marks.length; i++) {
      final m = marks[i];
      buf.writeln();
      buf.write('${m.seq.toString().padLeft(2, '0')}\t${_fmt(m.remaining)}\t${_fmt(intervalAt(marks, i))}\t${m.note}');
    }
    return buf.toString();
  }

  static String _fmt(Duration d) {
    final total = d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
