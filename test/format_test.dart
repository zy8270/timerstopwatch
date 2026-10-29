import 'package:flutter_test/flutter_test.dart';
import 'package:timerstopwatch/core/format.dart';

void main() {
  group('formatClock', () {
    test('不足 1 小时显示 mm:ss', () {
      expect(formatClock(const Duration(seconds: 5)), '00:05');
      expect(formatClock(const Duration(minutes: 1, seconds: 1)), '01:01');
      expect(formatClock(const Duration(minutes: 59, seconds: 59)), '59:59');
    });

    test('满 1 小时显示 h:mm:ss', () {
      expect(formatClock(const Duration(hours: 1)), '1:00:00');
      expect(formatClock(const Duration(hours: 23, minutes: 59, seconds: 59)), '23:59:59');
    });

    test('formatClockFull 恒为 h:mm:ss', () {
      expect(formatClockFull(const Duration(seconds: 5)), '00:00:05');
      expect(formatClockFull(const Duration(hours: 1, minutes: 2, seconds: 3)), '01:02:03');
    });
  });

  group('parseClockInput（编辑标记时间）', () {
    test('h:mm:ss / mm:ss / 纯秒数 / 90 分钟', () {
      expect(parseClockInput('1:30:05'), const Duration(hours: 1, minutes: 30, seconds: 5));
      expect(parseClockInput('58:00'), const Duration(minutes: 58));
      expect(parseClockInput('90:30'), const Duration(hours: 1, minutes: 30, seconds: 30));
      expect(parseClockInput(' 300 '), const Duration(minutes: 5));
      expect(parseClockInput('00:00:00'), Duration.zero);
    });

    test('非法输入返回 null', () {
      expect(parseClockInput(''), isNull);
      expect(parseClockInput('abc'), isNull);
      expect(parseClockInput('1:2:3:4'), isNull);
      expect(parseClockInput('1:99:00'), isNull);
      expect(parseClockInput('10:75'), isNull);
      expect(parseClockInput('-5'), isNull);
    });
  });
}
