# controllers/ — Riverpod 状态与业务逻辑

| 文件 | 职责 | 影响 |
|------|------|------|
| `timer_controller.dart` | 计时核心状态机（未开始/进行/暂停/结束）：单调时钟推算剩余、标记（增删改/撤销/通知标记）、暂停冻结、结束响铃触发、DND 会话、wakelock；**保存到历史 + 会话内自动追加**（`saveToHistory`/`_syncHistory`，条目 id 存 `_sessionHistoryId`，会话重置即断开联动）。取消时先停铃声（结束界面"返回修改时长"bug 修复）。**v3.10：考试模式**（`_examSession` 开始时快照设置，节点 900/10 秒走考试音频、普通阈值整场停用）与**会话快照恢复**（键 `timer_session_v1`，开始/暂停/继续/标记变更/阈值触发时写入；`build()` 启动恢复：暂停态恢复暂停、运行态按 endWall 折算、已到点丢弃、错过的提醒不补播；恢复时重建前台服务+勿扰 sessionRestart+常亮） | 全部计时行为的数据源；前台服务/勿扰/常亮的同步点 |
| `history_controller.dart` | 历史记录列表：create/syncSession（覆盖更新含改名）/rename/deleteMany；SharedPreferences JSON 持久化，按保存时间倒序、数量不限 | 历史页与计时页"保存"按钮的数据源 |
| `presets_controller.dart` | 快捷预设：**单一有序列表、无限缓存**（v2 键 `preset_list_seconds_v2`）；开始使用与设置添加均置顶去重；`reorder` 为 **DragTarget 语义**（目标格索引直接插入，勿再 -1——真机拖动无效 bug 的教训）；`movePresetTo` 供拖动**悬停实时排序**（拖影跟随手指、其余格避让动画）；`presetEditingProvider` 为预设编辑模式全局状态（切页签/点预设外退出）；自动迁移 v1 旧数据（最近使用 + 自定义） | 计时页预设区与设置页"快捷预设"共用 |
| `settings_controller.dart` | 设置项（铃声/震动/勿扰/假睡眠/阈值提醒/**考试模式**/**时钟样式 `ClockStyle`（analog/digital，键 `clock_style`，未知值兜底 digital）——v3.11**/**主题配色 `AppPalette` 与日夜间 `AppThemeMode`（键 `theme_palette`/`theme_mode`，未知值兜底 浅紫/跟随系统）——v3.12**）+ JSON 持久化；含首启引导标记 | 设置页数据源；计时控制器读取阈值/铃声/考试模式配置；计时页与假睡眠层读取时钟样式；app.dart 读配色/模式生成主题 |
| `fake_sleep_controller.dart` | 假睡眠状态机：进入（沉浸全屏；**不调窗口亮度**，v3.5 定性黄线为 OLED 低灰阶拖影：v3.3 压亮度有效灰阶≈29、v3.4 暗字≈89 都在拖影区，对策=文字灰阶 0.5 + 漂移改跳变）/退出（恢复系统栏）；阈值提醒触发的 30 秒短唤醒 | 伪熄屏观感由 fake_sleep_layer 的暗文字承担 |

> 约定：控制器不 import 任何 `ui/`；平台调用统一走 `services/native_channel.dart`（单测中静默降级）。
