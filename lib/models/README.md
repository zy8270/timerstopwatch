# models/ — 纯数据模型

| 文件 | 职责 | 影响 |
|------|------|------|
| `time_mark.dart` | 一条时间段标记：`序号 seq / 标记时刻剩余 remaining / 自开始间隔 elapsed / 备注 note`；含 JSON 序列化（历史记录存储用） | 标记数值守恒（剩余+已进行=总时长）依赖此处不变式 |
| `app_palette.dart` | 主题配色方案（v3.12）：`AppPalette` 七套（浅紫/深紫/青/黄/浅蓝/粉红/浅绿），每套 = ColorScheme 种子色 + 图标渐变两端色；`name` 同时是 prefs 键值、原生 `alias_<key>` 键与图标资源名 `ic_launcher_<key>`。`AppThemeMode`（跟随系统/日间/夜间） | 增删配色需同步：Android 清单 alias、`ic_launcher_bg_*` 渐变 drawable、golden 导出的 PNG 与 MainActivity `ICON_KEYS` |
| `history_entry.dart` | 一条历史记录：`id / 名称 name / 保存时刻 savedAtMs / 倒计时总时长 total / 标记列表 marks`；含 JSON 序列化与 TSV 导出文本 `toExportText`（复制到剪贴板格式） | 字段变更需同步 history_controller 持久化与历史页展示 |
