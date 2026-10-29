# ui/widgets/ — 复用组件

| 文件 | 职责 | 影响 |
|------|------|------|
| `cycling_wheel.dart` | 循环数字滚轮（`ListWheelChildLoopingListDelegate`，远离中点无感回中）。**每滚过一格：`onSelectedItemChanged` → 原生 `wheelTick` 并同步圈基；滚动中零重建**；值提交只在滚动停止（ScrollEnd）的 `onChanged`。v3.6 两处关键口径：①SDK 对循环列表的 `onSelectedItemChanged` 回调**归一化序号**（raw%count），圈基必须从 `controller.selectedItem`（原始圈位）同步；②程序化跳转（应用预设/回中）期间（`_programmatic`）派发的滚动通知一律不处理——`jumpTo` 内部 `goIdle()` 会先派发一条携带滞留位置的结束通知，不拦会把旧值提交回去覆盖预设。外部设值走 `syncGen` 整组代数：值没变的滚轮（可能在惯性滚动中）也要归位；手指按住时等松手再应用 | 计时页时长选择的唯一输入件；单位小字"时/分/秒"由 timer_page 排在轮间并与中行对齐 |
| `fake_sleep_layer.dart` | 伪熄屏覆盖层：纯黑全屏 + 时间文字（alpha 0.5）+ 暂停小字；每 45 秒随机**跳变**防烧屏；点击后非线性动画回位再退出。**必须在 Material 祖先下渲染**（本组件自带透明 Material + 显式 `decoration: TextDecoration.none`）：v3.6 定案黄线根因是本层原挂在 Scaffold 之外、无 Material 祖先时被 MaterialApp 注入黄色双下划线 fallback 样式，与 OLED 无关 | 黑底 OLED 不发光，暗字即可营造伪熄屏；若嫌暗/亮改文字 alpha 一处 |
| `mark_edit_dialog.dart` | 标记编辑对话框（v3.6 新增）：修改剩余时间节点（`parseClockInput` 解析 h:mm:ss / mm:ss / 秒数，校验 ≤ 总时长）与备注、删除该条。计时页与历史页共用；改剩余时间后已进行按 总时长-剩余 重算 | 标记"时间+备注"编辑的单一入口，两页行为天然一致 |
| `app_icon.dart` | App 图标绘制源：深紫→亮紫对角渐变 + 白色扁平秒表（表盘+顶帽+斜放沙漏，**按包围盒视觉居中**）。`test/icon_golden_test.dart` 用它渲染各密度 PNG 资源 | 改图标只改这里然后重新导出，不要手改 res 下的 PNG |
