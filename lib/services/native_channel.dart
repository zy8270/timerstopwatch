import 'package:flutter/services.dart';

/// Android 原生能力统一通道（实现在 MainActivity.kt / TimerService.kt 等）。
class NativeChannel {
  static const MethodChannel _ch = MethodChannel('timerstopwatch/app');

  static Future<T?> _inv<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args ?? const {});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  // ---------- 响铃 / 提示音 ----------

  static Future<void> ringStart({String? path, required bool vibrate, required bool dndLift}) =>
      _inv('ringStart', {'path': path, 'vibrate': vibrate, 'dndLift': dndLift});

  static Future<void> ringStop() => _inv('ringStop');

  static Future<void> soundPlay({String? path, required int seconds, required bool vibrate}) =>
      _inv('soundPlay', {'path': path, 'seconds': seconds, 'vibrate': vibrate});

  /// 考试模式音频：把随包 assets 拷贝到私有目录，返回 key(start/mid15/end)→路径。
  static Future<Map<String, String>?> ensureExamAudio() async {
    final raw = await _inv<Map<Object?, Object?>>('ensureExamAudio');
    if (raw == null) return null;
    return raw.map((k, v) => MapEntry(k as String, v as String));
  }

  /// 滚轮每滚过一格：线性马达轻震 + 波轮咔哒声（原生 WheelFeedback）。
  static Future<void> wheelTick() => _inv('wheelTick');

  // ---------- 前台服务 ----------

  static Future<void> serviceStart({
    required int endWallMs,
    required int totalMs,
    required int lastMarkMs,
    String? ringPath,
    required bool vibrate,
    required bool dndLift,
  }) =>
      _inv('serviceStart', {
        'endWallMs': endWallMs,
        'totalMs': totalMs,
        'lastMarkMs': lastMarkMs,
        'ringPath': ringPath,
        'vibrate': vibrate,
        'dndLift': dndLift,
      });

  static Future<void> servicePause(int remainingMs) => _inv('servicePause', {'remainingMs': remainingMs});

  static Future<void> serviceResume(int endWallMs) => _inv('serviceResume', {'endWallMs': endWallMs});

  static Future<void> serviceLastMark(int elapsedMs) => _inv('serviceLastMark', {'elapsedMs': elapsedMs});

  static Future<void> serviceStop() => _inv('serviceStop');

  // ---------- 悬浮窗 ----------

  static Future<void> overlayShow(String text) => _inv('overlayShow', {'text': text});

  static Future<void> overlayHide() => _inv('overlayHide');

  static Future<bool> overlayGranted() async => await _inv<bool>('overlayGranted') ?? false;

  static Future<void> overlayRequest() => _inv('overlayRequest');

  // ---------- 权限 ----------

  static Future<bool> notifGranted() async => await _inv<bool>('notifGranted') ?? true;

  static Future<bool> notifRequest() async => await _inv<bool>('notifRequest') ?? false;

  static Future<bool> exactGranted() async => await _inv<bool>('exactGranted') ?? true;

  static Future<void> exactRequest() => _inv('exactRequest');

  static Future<bool> dndGranted() async => await _inv<bool>('dndGranted') ?? false;

  static Future<void> dndRequest() => _inv('dndRequest');

  // ---------- 勿扰会话 ----------

  static Future<void> dndSessionStart() => _inv('dndSessionStart');

  /// 进程被杀后恢复会话时重新接管勿扰（先复位再开，保证结束时能恢复干净基线）。
  static Future<void> dndSessionRestart() => _inv('dndSessionRestart');

  static Future<void> dndSessionEnd() => _inv('dndSessionEnd');

  // ---------- 假睡眠：窗口亮度 ----------

  static Future<void> brightnessSet(double value) => _inv('brightnessSet', {'value': value});

  static Future<void> brightnessReset() => _inv('brightnessReset');

  // ---------- 音频文件 ----------

  /// 打开系统文件选择器导入音频，返回拷贝到应用私有目录的绝对路径（取消返回 null）。
  static Future<String?> pickAudio() async => await _inv<String>('pickAudio');

  static Future<void> deleteAudio(String path) => _inv('deleteAudio', {'path': path});

  /// 注册原生 → Dart 回调（通知「标记」按钮 / 响铃关闭）。
  static void init({void Function(String method)? onCall}) {
    _ch.setMethodCallHandler((call) async {
      onCall?.call(call.method);
    });
  }
}
