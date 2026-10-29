import 'package:flutter/foundation.dart';

/// 一条时间段标记：记录标记时刻的剩余时间节点与自开始的间隔时长。
@immutable
class TimeMark {
  const TimeMark({
    required this.seq,
    required this.remaining,
    required this.elapsed,
    this.note = '',
  });

  final int seq;

  /// 标记时刻的剩余倒计时（时间节点）。
  final Duration remaining;

  /// 从倒计时开始到该节点的间隔时长（有效计时，不含暂停）。
  ///
  /// 存储口径保持"自开始"的绝对值（剩余 + 已进行 = 总时长恒成立）；
  /// **展示口径**（v3.6 起）改为与上一条标记的间隔，见 [intervalAt]。
  final Duration elapsed;

  final String note;

  TimeMark copyWith({Duration? remaining, Duration? elapsed, String? note}) {
    return TimeMark(
      seq: seq,
      remaining: remaining ?? this.remaining,
      elapsed: elapsed ?? this.elapsed,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'remainingMs': remaining.inMilliseconds,
        'elapsedMs': elapsed.inMilliseconds,
        'note': note,
      };

  factory TimeMark.fromJson(Map<String, dynamic> json) => TimeMark(
        seq: (json['seq'] as num).toInt(),
        remaining: Duration(milliseconds: (json['remainingMs'] as num).toInt()),
        elapsed: Duration(milliseconds: (json['elapsedMs'] as num).toInt()),
        note: json['note'] as String? ?? '',
      );
}

/// 展示口径的"已进行"：第 1 条 = 自开始；第 2 条起 = 与上一条标记的间隔
/// （两次标记之间的差值）。列表中途删除标记后，间隔按现存相邻两条重算。
Duration intervalAt(List<TimeMark> marks, int i) {
  if (i <= 0) return marks.first.elapsed;
  return marks[i].elapsed - marks[i - 1].elapsed;
}
