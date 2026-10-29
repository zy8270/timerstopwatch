import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 注入已初始化的 SharedPreferences（在 main 中 override）。
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('main 中必须 override sharedPrefsProvider'),
);
