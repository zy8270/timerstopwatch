// 生成滚轮逐格音效 wheel_tick.wav（短促"咔哒"声，约 28ms）。
// 输出：android/app/src/main/res/raw/wheel_tick.wav（PCM16 单声道 44.1kHz）。
// 用法：dart run tool/gen_tick.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

void main() {
  const rate = 44100;
  const durSec = 0.028;
  final n = (rate * durSec).toInt();
  final samples = List<int>.generate(n, (i) {
    final t = i / rate;
    // 快速衰减包络 + 基频/倍频，模拟机械波轮咔哒声。
    final env = math.exp(-t * 260);
    final v =
        math.sin(2 * math.pi * 1900 * t) * 0.68 +
        math.sin(2 * math.pi * 4200 * t) * 0.24;
    return (v * env * 32767 * 0.6).round().clamp(-32768, 32767);
  });

  final data = BytesBuilder();
  final size = n * 2;
  // RIFF 头
  data.add('RIFF'.codeUnits);
  _u32(data, 36 + size);
  data.add('WAVE'.codeUnits);
  data.add('fmt '.codeUnits);
  _u32(data, 16); // PCM chunk size
  _u16(data, 1); // PCM
  _u16(data, 1); // mono
  _u32(data, rate);
  _u32(data, rate * 2); // byte rate
  _u16(data, 2); // block align
  _u16(data, 16); // bits
  data.add('data'.codeUnits);
  _u32(data, size);
  final bytes = samples.map((s) => [s & 0xFF, (s >> 8) & 0xFF]).expand((b) => b).toList();
  data.add(bytes);

  final out = File('android/app/src/main/res/raw/wheel_tick.wav');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(data.toBytes());
  stdout.writeln('written ${out.path} (${data.toBytes().length} bytes)');
}

void _u32(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
void _u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
