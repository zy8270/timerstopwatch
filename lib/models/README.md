# models/ — 纯数据模型

| 文件 | 职责 | 影响 |
|------|------|------|
| `time_mark.dart` | 一条时间段标记：`序号 seq / 标记时刻剩余 remaining / 自开始间隔 elapsed / 备注 note`；含 JSON 序列化（历史记录存储用） | 标记数值守恒（剩余+已进行=总时长）依赖此处不变式 |
| `history_entry.dart` | 一条历史记录：`id / 名称 name / 保存时刻 savedAtMs / 倒计时总时长 total / 标记列表 marks`；含 JSON 序列化与 TSV 导出文本 `toExportText`（复制到剪贴板格式） | 字段变更需同步 history_controller 持久化与历史页展示 |
