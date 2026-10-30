# test/ — 单元与 golden 测试

| 文件 | 职责 | 影响 |
|------|------|------|
| `timer_controller_test.dart` | 计时/标记数值守恒、暂停禁标、删除序号稳定、**标记改时间（已进行=总时长-剩余重算+历史联动）**、预设（置顶去重无限/DragTarget 语义排序/删除/持久化恢复）、历史（保存→自动追加→覆盖更新改名→重命名→删除；重新开始新建；条目被删后再保存回落新建）、阈值排序 | 改控制器行为须同步此处 |
| `preset_ui_test.dart` | 预设区 UI 回归：长按进入编辑（角标出现）→ 拖动排序生效并持久化（真机"编辑状态拖不动"bug 的回归测试）；拖动悬停实时避让 | 改预设区手势/布局须保持通过 |
| `wheel_preset_test.dart` | 滚轮×预设交互回归（真机"半格状态点预设闪动卡住"bug）：拖住半格点预设 / 惯性滚动中点预设 / 回弹动画中点预设，预设值必胜且滚轮不卡死；**场景D（v3.11）：连拨闪值**——甩惯性→按住→停稳→分步慢拖→松手连三拨，最终值必须是最后一拨的落点（提交回声误判外部设值的回归） | 改 cycling_wheel 滚动/跳转逻辑须保持通过 |
| `v36_fixes_test.dart` | v3.6 三项修复回归：假睡眠层不继承黄色下划线 fallback 样式；已进行=相邻标记间隔（intervalAt + 导出文本）；历史条目内单条标记编辑；预设拖动边界抖动不震荡（迟滞带） | 改假睡眠层/标记口径/预设拖动须保持通过 |
| `exam_mode_test.dart` | **v3.10 考试模式与会话恢复**：考试开关持久化、examRulesFor 节点口径（≥总时长忽略）、暂停/运行快照写入与杀进程后恢复（剩余/标记/已触发节点保留、错过的提醒不补播、已到点丢弃、损坏快照安全回退、结束清快照）、设置页考试开关置灰其余阈值项 | 改快照结构/考试节点/恢复逻辑须同步此处 |
| `clock_style_test.dart` | **v3.11 时钟样式**：设置页顶部切换（默认电子、点圆形立即生效并写入 `clock_style`、切回电子）、持久化加载（analog 恢复 / 非法值兜底 digital）、倒计时进行页按样式渲染（数字↔表盘） | 改 ClockStyle/设置页分段按钮/`_buildCountdown` 分发须同步 |
| `format_test.dart` | 时间格式化 + 时间输入解析断言 | 改 format.dart 须同步 |
| `icon_golden_test.dart` | 用 `AppIcon` 离屏渲染桌面图标各密度 PNG（legacy + adaptive 前景）到 `goldens/icon/`，再拷入 android res | **改图标流程：改 `lib/ui/widgets/app_icon.dart` → `flutter test --update-goldens test/icon_golden_test.dart` → 拷贝 PNG 到 `mipmap-*`** |

运行：`flutter test`（全绿 44 项）。

> widget 测试驱动滚轮的坑（v3.11 定案）：瞬移式单次 moveBy 不产生滚动，须分步 moveBy（10px×N）+pump；慢拖恰好 48px 会停在格边界被吸附弹回，须拖 1.25 格（60px）跨过边界。
