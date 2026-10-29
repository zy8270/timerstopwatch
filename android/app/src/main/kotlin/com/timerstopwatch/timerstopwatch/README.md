# kotlin/com.timerstopwatch.timerstopwatch/ — Android 原生实现

| 文件 | 职责 | 影响 |
|------|------|------|
| `MainActivity.kt` | MethodChannel `timerstopwatch/app` 的注册中心：响铃/提示音/考试音频 ensureExamAudio/滚轮反馈/前台服务/悬浮窗/权限/勿扰/亮度/音频导入全部在此分发；持有 `dartChannel` 供广播回调反向调 Dart | 新增原生方法在这里加 case；音频导入拷贝到应用私有目录 |
| `TimerService.kt` | 前台服务：运行模式常驻通知（剩余 + 距上次标记 + 「标记」action，每秒刷新）+ AlarmManager.setAlarmClock 精确兜底；响铃模式（结束/被杀拉起）全屏通知；结束/销毁时隐藏悬浮窗；**通知小图标 = `ic_notification`（白色秒表剪影，与 App 图标同造型）** | 后台/锁屏/杀进程三条响铃路径的枢纽 |
| `AlarmRing.kt` | MediaPlayer 循环响铃（USAGE_ALARM 声道，勿扰下可响）+ 波形震动；一次性提示音（阈值提醒） | 铃声行为的唯一实现 |
| `OverlayWindow.kt` | 后台倒计时悬浮窗：半透明黑圆角、大号时间（26sp）、**「标记」按钮（广播→MarkActionReceiver→Dart）**、✕ 关闭、可拖动；留白收紧 | 需要 SYSTEM_ALERT_WINDOW；未授权时 Dart 侧不调用 |
| `WheelFeedback.kt` | **滚轮逐格反馈**：线性马达 `VibrationEffect.EFFECT_TICK`（API 29+，低版本弱震动兜底）+ SoundPool 播放 `res/raw/wheel_tick.wav`（USAGE_ASSISTANCE_SONIFICATION 跟随系统音量） | 音效文件由 `tool/gen_tick.dart` 生成，勿手改二进制 |
| `DndHelper.kt` | 勿扰：会话开始保存原状态并开优先级勿扰、响铃前临时解除开关、**会话恢复重启（`sessionRestart`：先复位"全部"再接管，防杀进程后勿扰卡死）**、结束恢复 | 依赖清单里的 ACCESS_NOTIFICATION_POLICY 声明（缺声明则系统勿扰列表不显示本应用，Android 16 实机验证） |
| `ExamAudio.kt` | **考试模式音频（v3.10）**：随包 Flutter assets（`audio/*.m4a`）经 `getLookupKeyForAsset` 拷到私有目录（固定名覆盖写，换包自动更新），返回 key(start/mid15/end)→路径 | 考试三个音频的唯一来源；改文件名须同步 pubspec assets 与 Dart 侧 key |
| `Receivers.kt` | 三个广播接收器：精确闹铃到点拉起响铃服务；通知「标记」转发 Dart；通知「关闭铃声」停声停服 | 通知按钮与悬浮窗标记共用 MarkActionReceiver |

> 资源：`res/raw/wheel_tick.wav` 滚轮音效；`res/drawable/ic_notification.xml` 通知小图标（白色秒表剪影，与 App 图标同造型）；`res/mipmap-*` 图标（由 golden 测试导出）；`res/drawable/ic_launcher_background.xml` 渐变底；`AndroidManifest.xml` 权限与服务/接收器注册。
