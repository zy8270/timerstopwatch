/// 时长/时间格式化工具。
library;

String twoDigits(int v) => v.toString().padLeft(2, '0');

/// 倒计时显示：≥1 小时用 h:mm:ss，否则 mm:ss。
String formatClock(Duration d) {
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  return h > 0 ? '$h:${twoDigits(m)}:${twoDigits(s)}' : '${twoDigits(m)}:${twoDigits(s)}';
}

/// 固定 h:mm:ss 格式（用于标记列表等需要列对齐的场景）。
String formatClockFull(Duration d) {
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  return '${twoDigits(h)}:${twoDigits(m)}:${twoDigits(s)}';
}

/// 解析用户输入的时间：接受 h:mm:ss / mm:ss / m:ss / 纯秒数。
/// mm:ss 中的 mm 允许 ≥60（如 90:30 = 1:30:30）；秒必须 <60。
/// 解析失败或为负返回 null（编辑标记时间用）。
Duration? parseClockInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final parts = text.split(':');
  if (parts.length > 3) return null;
  final nums = <int>[];
  for (final p in parts) {
    if (p.isEmpty) return null;
    final v = int.tryParse(p);
    if (v == null || v < 0) return null;
    nums.add(v);
  }
  int h = 0, m = 0, s = 0;
  if (nums.length == 3) {
    h = nums[0];
    m = nums[1];
    s = nums[2];
    if (m >= 60 || s >= 60) return null;
  } else if (nums.length == 2) {
    m = nums[0];
    s = nums[1];
    if (s >= 60) return null;
  } else {
    // 纯数字 = 总秒数，可超过 60（如 300 = 5 分钟）。
    s = nums[0];
  }
  return Duration(hours: h, minutes: m, seconds: s);
}
