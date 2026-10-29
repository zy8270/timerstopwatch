# core/ — 纯函数工具

| 文件 | 职责 | 影响 |
|------|------|------|
| `format.dart` | `formatClock`（≥1 小时 h:mm:ss，否则 mm:ss）、`formatClockFull`（恒 h:mm:ss）、`twoDigits` | 全部时间显示/预设文案的格式基准；改格式会波及 E2E 断言文本 |
