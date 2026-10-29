# integration_test/ — 端到端冒烟

| 文件 | 职责 | 影响 |
|------|------|------|
| `app_e2e.dart` | 模拟器全流程：预设 → 开始 → 标记 → 暂停/继续 → 假睡眠（3 秒无操作）→ 阈值提醒 → 结束 → **保存到历史（默认名弹窗）** → 关铃声 → 返回修改 → 取消二次确认 → **历史页展开查看** | UI 结构/文案变更须同步断言（如预设键 `preset_list_seconds_v2`） |

运行：`flutter test integration_test/app_e2e.dart -d emulator-5554`（需模拟器在线；live 帧率模式，禁用 pumpAndSettle）。
