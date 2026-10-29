# services/ — 平台服务封装

| 文件 | 职责 | 影响 |
|------|------|------|
| `native_channel.dart` | Android 原生能力唯一通道（`timerstopwatch/app` MethodChannel）：响铃/提示音、**考试音频 ensureExamAudio（v3.10）**、**滚轮逐格反馈 wheelTick**、前台服务启停、悬浮窗、权限查询/请求、勿扰会话（含恢复用 dndSessionRestart）、窗口亮度、音频导入、原生→Dart 回调注册。平台异常统一吞掉返回 null（单测可跑） | 新增原生能力先在此加方法，再到 MainActivity.kt 注册 |
| `shared_prefs_provider.dart` | 注入已初始化的 SharedPreferences（main 中 override） | 所有持久化控制器的共同依赖 |
