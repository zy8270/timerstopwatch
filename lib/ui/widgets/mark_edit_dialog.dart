import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/time_mark.dart';

/// 标记编辑对话框结果。
class MarkEditResult {
  const MarkEditResult({required this.delete, this.remaining, this.note});

  final bool delete;
  final Duration? remaining;
  final String? note;
}

/// 编辑一条标记：修改剩余时间节点与备注，或删除该条。
/// 计时页与历史记录页共用（v3.6：历史展开的每一项都可点击进入编辑）。
///
/// 修改剩余时间时，已进行（自开始）时长按 总时长 - 剩余 重算，
/// 保证 剩余 + 已进行 = 总时长 的存储口径恒成立；展示的"间隔"随之自然更新。
Future<MarkEditResult?> showMarkEditDialog(
  BuildContext context, {
  required TimeMark mark,
  required Duration total,
  required Duration interval,
}) {
  final timeCtrl = TextEditingController(text: formatClockFull(mark.remaining));
  final noteCtrl = TextEditingController(text: mark.note);
  final errorColor = Theme.of(context).colorScheme.error;

  return showDialog<MarkEditResult>(
    context: context,
    builder: (dialogContext) {
      String? timeError;
      return StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text('标记 ${mark.seq.toString().padLeft(2, '0')} · 间隔 ${formatClockFull(interval)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: timeCtrl,
                autofocus: true,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  labelText: '剩余时间',
                  hintText: '如 00:58:00 或 58:00',
                  errorText: timeError,
                ),
              ),
              TextField(
                controller: noteCtrl,
                maxLength: 30,
                decoration: const InputDecoration(labelText: '备注', hintText: '如：资料分析'),
              ),
              Text(
                '总时长 ${formatClockFull(total)}，剩余修改后已进行将自动重算',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: errorColor),
              onPressed: () => Navigator.pop(
                dialogContext,
                const MarkEditResult(delete: true),
              ),
              child: const Text('删除'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = parseClockInput(timeCtrl.text);
                if (parsed == null) {
                  setState(() => timeError = '时间格式：h:mm:ss / mm:ss / 秒数');
                  return;
                }
                if (parsed > total) {
                  setState(() => timeError = '不能超过总时长 ${formatClockFull(total)}');
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  MarkEditResult(delete: false, remaining: parsed, note: noteCtrl.text.trim()),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
    },
  );
}
