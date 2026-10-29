# lib/ — 应用源码总览

倒计时计时器 App 的全部 Dart 源码。分层结构（依赖方向：ui → controllers → models/services）：

| 目录 | 职责 | 影响 |
|------|------|------|
| `main.dart` | 入口：竖屏锁定、SharedPreferences 初始化、注入 ProviderScope | 改动会影响全局启动流程 |
| `app.dart` | MaterialApp 主题/中文本地化；`NavShell` 底部导航（历史 \| 计时 \| 设置，默认计时居中）；切换页签会退出预设编辑模式（`presetEditingProvider`）；承载原生回调（通知标记/响铃关闭）、首启权限引导、前后台悬浮窗联动、空闲检测与假睡眠 | 导航顺序、权限引导、假睡眠的"总开关"都在这里 |
| `controllers/` | Riverpod 状态机（计时/标记/历史/预设/设置/假睡眠） | 业务核心；UI 全部只读 provider |
| `models/` | 纯数据模型（标记、历史条目） | 变更字段需同步 JSON 序列化与测试 |
| `services/` | 原生通道封装、SharedPreferences 注入 | 与 Android 原生能力的唯一边界 |
| `core/` | 时间格式化等纯函数 | 显示格式一处定义处处生效 |
| `ui/` | 页面与组件 | 见 `ui/README.md` |

> 维护约定：新增/移动文件时同步更新本文件与各子目录 README。
