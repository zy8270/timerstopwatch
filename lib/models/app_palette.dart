import 'package:flutter/material.dart';

/// 主题配色方案：一套配色 = 一个 ColorScheme 种子（App 内日/夜间主题）+
/// 图标渐变两端色（桌面图标联动，键名与 Android activity-alias 后缀一致）。
///
/// [key] 同时用于：
/// - prefs 持久化（存枚举 name，与 ClockStyle 同口径）；
/// - 原生侧 alias 名（`alias_<key>`）与图标资源名（`ic_launcher_<key>`）。
enum AppPalette {
  lightPurple('浅紫', seed: Color(0xFF8B5CF6), iconStart: Color(0xFF6D28D9), iconEnd: Color(0xFFA78BFA)),
  deepPurple('深紫', seed: Color(0xFF6D28D9), iconStart: Color(0xFF4A0E9B), iconEnd: Color(0xFFA855F7)),
  cyan('青色', seed: Color(0xFF0891B2), iconStart: Color(0xFF155E75), iconEnd: Color(0xFF22D3EE)),
  yellow('黄色', seed: Color(0xFFD97706), iconStart: Color(0xFF92400E), iconEnd: Color(0xFFFBBF24)),
  lightBlue('浅蓝', seed: Color(0xFF3F6DF5), iconStart: Color(0xFF1D4ED8), iconEnd: Color(0xFF60A5FA)),
  pink('粉红', seed: Color(0xFFDB2777), iconStart: Color(0xFF831843), iconEnd: Color(0xFFF472B6)),
  green('浅绿', seed: Color(0xFF22C55E), iconStart: Color(0xFF166534), iconEnd: Color(0xFF4ADE80));

  const AppPalette(this.label, {required this.seed, required this.iconStart, required this.iconEnd});

  final String label;

  /// Material 3 ColorScheme 种子色（日/夜间各自由种子推导）。
  final Color seed;

  /// 图标渐变起点（左上深色端）。
  final Color iconStart;

  /// 图标渐变终点（右下亮色端）。
  final Color iconEnd;

  static AppPalette fromName(String? name) =>
      AppPalette.values.where((p) => p.name == name).firstOrNull ?? AppPalette.lightPurple;
}

/// 日/夜间模式：跟随系统 / 日间 / 夜间。
enum AppThemeMode {
  system('系统'),
  light('日间'),
  dark('夜间');

  const AppThemeMode(this.label);

  final String label;

  ThemeMode get themeMode =>
      this == AppThemeMode.light ? ThemeMode.light : (this == AppThemeMode.dark ? ThemeMode.dark : ThemeMode.system);

  static AppThemeMode fromName(String? name) =>
      AppThemeMode.values.where((m) => m.name == name).firstOrNull ?? AppThemeMode.system;
}
