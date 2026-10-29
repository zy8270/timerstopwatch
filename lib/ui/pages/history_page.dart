import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/history_controller.dart';
import '../../core/format.dart';
import '../../models/history_entry.dart';
import '../../models/time_mark.dart';
import '../widgets/mark_edit_dialog.dart';

/// 历史记录页：单列纵向列表。
/// - 点击条目展开：第一行倒计时总时间，随后为 序号/剩余/已进行/备注 标记表，
///   展开区底部单行右对齐三个操作按钮（重命名/复制/删除）。
/// - 展开区内**每条标记行可点击进入编辑**：修改剩余时间与备注、删除该条（v3.6）。
/// - 长按进入多选：右上角出现红色「删除」按钮，每项右侧出现重命名图标。
/// - "已进行"列与计时页同口径：第 1 条 = 自开始，之后 = 与上一条标记的间隔。
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final Set<String> _selected = {};
  bool _multiSelect = false;
  String? _expandedId;

  void _enterMultiSelect(String id) {
    setState(() {
      _multiSelect = true;
      _selected
        ..clear()
        ..add(id);
    });
  }

  void _exitMultiSelect() {
    setState(() {
      _multiSelect = false;
      _selected.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
      if (_selected.isEmpty) _multiSelect = false;
    });
  }

  // ---------- 命名对话框（保存/重命名共用：光标在末尾 + 激活输入法） ----------

  Future<String?> _askName(String title, String initial) async {
    final controller = TextEditingController(text: initial)
      ..selection = TextSelection.collapsed(offset: initial.length);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: '记录名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('确定')),
        ],
      ),
    );
  }

  Future<void> _rename(String id, String current) async {
    final name = await _askName('重命名历史记录', current);
    final n = name?.trim();
    if (n == null || n.isEmpty) return;
    await ref.read(historyProvider.notifier).rename(id, n);
  }

  Future<void> _deleteMany(Set<String> ids) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除历史记录？'),
        content: Text('将删除选中的 ${ids.length} 条记录，删除后不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(historyProvider.notifier).deleteMany(ids);
    if (!mounted) return;
    setState(() {
      if (ids.contains(_expandedId)) _expandedId = null;
    });
    _exitMultiSelect();
  }

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_multiSelect ? '已选 ${_selected.length} 项' : '历史记录'),
        leading: _multiSelect
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _exitMultiSelect,
                tooltip: '退出多选',
              )
            : null,
        actions: [
          if (_multiSelect)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: _selected.isEmpty ? null : () => _deleteMany({..._selected}),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('删除'),
            ),
        ],
      ),
      body: history.isEmpty
          ? Center(
              child: Text(
                '暂无历史记录\n计时页点「保存」即可把标记记录存到这里',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: history.length,
              itemBuilder: (context, i) => _buildEntry(theme, history[i]),
            ),
    );
  }

  Widget _buildEntry(ThemeData theme, HistoryEntry entry) {
    final expanded = _expandedId == entry.id;
    final checked = _selected.contains(entry.id);
    final savedAt = DateTime.fromMillisecondsSinceEpoch(entry.savedAtMs);
    final savedLabel =
        '${savedAt.year}-${twoDigits(savedAt.month)}-${twoDigits(savedAt.day)} ${twoDigits(savedAt.hour)}:${twoDigits(savedAt.minute)}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            onLongPress: () => _enterMultiSelect(entry.id),
            onTap: () {
              if (_multiSelect) {
                _toggleSelected(entry.id);
              } else {
                setState(() => _expandedId = expanded ? null : entry.id);
              }
            },
            title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
            subtitle: Text('总时长 ${formatClockFull(entry.total)} · ${entry.marks.length} 条标记 · $savedLabel'),
            trailing: _multiSelect
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.drive_file_rename_outline_rounded),
                        tooltip: '重命名',
                        onPressed: () => _rename(entry.id, entry.name),
                      ),
                      Checkbox(value: checked, onChanged: (_) => _toggleSelected(entry.id)),
                    ],
                  )
                : Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
          ),
          if (expanded && !_multiSelect) _buildExpanded(theme, entry),
        ],
      ),
    );
  }

  // ---------- 展开区：总时间 + 标记表 + 底部操作行 ----------

  Widget _markHeader(ThemeData theme) {
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    Widget col(String text, [double? width]) => SizedBox(width: width, child: Text(text, style: style));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          col('序号', 32),
          col('剩余', 104),
          col('已进行', 104),
          const Expanded(child: SizedBox()),
          col('备注'),
        ],
      ),
    );
  }

  Widget _markRow(ThemeData theme, HistoryEntry entry, TimeMark m, Duration interval) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _editMark(entry, m, interval),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                m.seq.toString().padLeft(2, '0'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            SizedBox(
              width: 104,
              child: Text(
                formatClockFull(m.remaining),
                style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            SizedBox(
              width: 104,
              child: Text(
                formatClockFull(interval),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: Text(
                m.note.isEmpty ? '—' : m.note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editMark(HistoryEntry entry, TimeMark m, Duration interval) async {
    final result = await showMarkEditDialog(
      context,
      mark: m,
      total: entry.total,
      interval: interval,
    );
    if (result == null) return;
    final controller = ref.read(historyProvider.notifier);
    if (result.delete) {
      await controller.removeMark(entry.id, m.seq);
    } else {
      await controller.updateMark(entry.id, m.seq, remaining: result.remaining, note: result.note);
    }
  }

  Widget _buildExpanded(ThemeData theme, HistoryEntry entry) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 8),
          // 第一行：倒计时总时间
          Text.rich(
            TextSpan(
              text: '倒计时总时间  ',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              children: [
                TextSpan(
                  text: formatClockFull(entry.total),
                  style: theme.textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _markHeader(theme),
          for (var i = 0; i < entry.marks.length; i++)
            _markRow(theme, entry, entry.marks[i], intervalAt(entry.marks, i)),
          const SizedBox(height: 8),
          // 底部操作行：单排右对齐，重命名 / 复制 / 删除（红色）
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => _rename(entry.id, entry.name),
                icon: const Icon(Icons.drive_file_rename_outline_rounded, size: 18),
                label: const Text('重命名'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: entry.toExportText()));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 2)),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('复制'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: () => _deleteMany({entry.id}),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
