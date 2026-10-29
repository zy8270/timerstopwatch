import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/presets_controller.dart';
import '../../controllers/timer_controller.dart';
import '../../core/format.dart';
import '../../models/time_mark.dart';
import '../../services/native_channel.dart';
import '../widgets/cycling_wheel.dart';
import '../widgets/mark_edit_dialog.dart';

class TimerPage extends ConsumerStatefulWidget {
  const TimerPage({super.key});

  @override
  ConsumerState<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends ConsumerState<TimerPage> {
  int _hours = 1;
  int _minutes = 0;
  int _seconds = 0;

  /// 预设整组设值代数：每次应用预设 +1。滚轮凭此在"值未变"时也能归位
  /// （真机 bug：滚轮停在两数字中间点预设，惯性滞留值把预设覆盖）。
  int _presetGen = 0;

  // 预设编辑模式状态在 presetEditingProvider（presets_controller.dart）：
  // NavShell 切换底部页签时需要退出编辑，所以放在全局而非本页私有。

  Duration get _selected => Duration(hours: _hours, minutes: _minutes, seconds: _seconds);

  void _applyPreset(Duration d) {
    setState(() {
      _hours = d.inHours;
      _minutes = d.inMinutes % 60;
      _seconds = d.inSeconds % 60;
      _presetGen++;
    });
    ref.read(timerProvider.notifier).setTotal(d);
  }

  void _syncSelectedToController() {
    ref.read(timerProvider.notifier).setTotal(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(timerProvider);
    final presets = ref.watch(presetsProvider);
    final theme = Theme.of(context);

    // 预设编辑模式：系统返回 = 退出编辑；点预设区域外任意位置（含标题栏、
    // 滚轮、空白、开始按钮四周）也退出编辑。底部导航栏属于 NavShell，
    // 由其切换页签时重置 presetEditingProvider。
    return Consumer(
      builder: (context, ref, child) {
        final editing = ref.watch(presetEditingProvider);
        return PopScope(
          canPop: !editing,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) ref.read(presetEditingProvider.notifier).state = false;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => ref.read(presetEditingProvider.notifier).state = false,
            child: child,
          ),
        );
      },
      child: Scaffold(
        appBar: AppBar(
          // debug 验证钩子：长按标题弹出悬浮窗（仅 debug 生效）。
          title: kDebugMode
              ? GestureDetector(
                  onLongPress: () {
                    debugPrint('[timer] overlay hook');
                    NativeChannel.overlayShow('00:10 测试');
                  },
                  child: const Text('计时'),
                )
              : const Text('计时'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: switch (timer.status) {
              TimerStatus.idle => _buildIdle(theme, presets, timer),
              TimerStatus.running || TimerStatus.paused => _buildRunning(context, theme, timer),
              TimerStatus.finished => _buildFinished(context, theme, timer),
            },
          ),
        ),
      ),
    );
  }

  // ---------- 未开始：滚轮 + 预设 + 开始 ----------

  Widget _buildIdle(ThemeData theme, List<Duration> presets, TimerState timer) {
    // 退出编辑的点按拦截在 build 里的整页 GestureDetector（Scaffold 级）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: Center(child: _buildPickerRow(theme))),
        // 固定高度占位：编辑提示的显隐不改变布局（避免拖动目标位移）。
        // 高度 30 且文字沉底留 10px：预设首行的删除角标（向上溢出）不会盖住提示文字。
        Consumer(
          builder: (context, ref, _) {
            final editing = ref.watch(presetEditingProvider);
            return SizedBox(
              height: 30,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: editing
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          '拖动排序 · 点击角标删除',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                      )
                    : null,
              ),
            );
          },
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(child: _buildPresetWrap(theme, presets)),
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            padding: const EdgeInsets.symmetric(vertical: 18),
          ),
          onPressed: _selected > Duration.zero
              ? () {
                  _syncSelectedToController();
                  ref.read(timerProvider.notifier).start();
                  ref.read(presetsProvider.notifier).recordUse(_selected);
                  ref.read(presetEditingProvider.notifier).state = false;
                }
              : null,
          child: const Text('开始', style: TextStyle(fontSize: 18)),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPickerRow(ThemeData theme) {
    const extent = 48.0;
    final unitStyle = theme.textTheme.titleSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );

    // 单位小字（时/分/秒）替代冒号：与滚轮中行（当前生效值）垂直对齐。
    Widget unit(String label) => SizedBox(
          height: extent * 3,
          child: Center(child: Text(label, style: unitStyle)),
        );

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CyclingWheel(count: 24, value: _hours, itemExtent: extent, syncGen: _presetGen, onChanged: (v) {
            setState(() => _hours = v);
            _syncSelectedToController();
          }),
          unit('时'),
          CyclingWheel(count: 60, value: _minutes, itemExtent: extent, syncGen: _presetGen, onChanged: (v) {
            setState(() => _minutes = v);
            _syncSelectedToController();
          }),
          unit('分'),
          CyclingWheel(count: 60, value: _seconds, itemExtent: extent, syncGen: _presetGen, onChanged: (v) {
            setState(() => _seconds = v);
            _syncSelectedToController();
          }),
          unit('秒'),
        ],
      ),
    );
  }

  // ---------- 快捷预设：一行最多 3 个、居中换行、可滚动、长按拖动排序、角标删除 ----------

  /// 预设网格：Stack + AnimatedPositioned（按预设值 key 定位）。
  /// 拖动悬停即实时排序：其余格沿新位置滑动"避让"，拖影（ghost）跟随手指。
  ///
  /// 防抖（v3.6，真机反馈"临界位置抽搐"）：排序判定不再依赖逐格 DragTarget 的
  /// 命中测试——格子自身在动画中、命中矩形随之移动，指针在两格边界时会与
  /// 排序结果互相激发形成震荡。改为整个网格一个 DragTarget，onMove 里按
  /// 指针坐标对**静态**槽位几何求格（行/列迟滞带内的边界区域不判定），
  /// 判定与格子的动画位置完全解耦，边界抖动被迟滞带吸收。
  Widget _buildPresetWrap(ThemeData theme, List<Duration> presets) {
    if (presets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '暂无预设，可在设置中添加固定预设',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final cell = ((maxWidth - 24) / 3).clamp(96.0, 220.0);
        // 与原 Wrap（spacing 12）相同的一行可容纳数（手机上恒为 3）。
        final perRow = (((maxWidth + 12) / (cell + 12)).floor()).clamp(1, presets.length);
        final rows = (presets.length / perRow).ceil();
        const rowH = 50.0, gap = 12.0;

        // 第 row 行的起始横坐标（整行居中，末行可能不满）。
        double rowLeft(int row) {
          final rowCount = (presets.length - row * perRow).clamp(0, perRow);
          final rowWidth = rowCount * cell + (rowCount - 1) * gap;
          return (maxWidth - rowWidth) / 2;
        }

        // 指针 → 槽位（静态几何 + 迟滞带）；边界带内返回 null（维持现状）。
        int? slotOf(Offset local) {
          final rowFrac = local.dy / rowH;
          final row = rowFrac.floor();
          if (row < 0 || row >= rows) return null;
          final inRow = rowFrac - row;
          if (inRow < 0.22 || inRow > 0.78) return null; // 行间 11px 迟滞带
          final colFrac = (local.dx - rowLeft(row)) / (cell + gap);
          if (colFrac < 0.0) return 0; // 左缘外贴到本行第一格
          final col = colFrac.floor();
          final maxCol = (presets.length - row * perRow).clamp(0, perRow) - 1;
          if (col > maxCol) return row * perRow + maxCol;
          final inCell = colFrac - col;
          final margin = 8.0 / (cell + gap); // 列间 8px 迟滞带
          if (inCell < margin || inCell > 1 - margin) return null;
          return row * perRow + col;
        }

        Widget cellAt(int i) {
          final row = i ~/ perRow;
          final col = i % perRow;
          return AnimatedPositioned(
            key: ValueKey(presets[i]),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: rowLeft(row) + col * (cell + gap),
            top: row * rowH,
            width: cell,
            height: 40,
            child: _buildPresetCell(theme, presets, i, cell),
          );
        }

        return SizedBox(
          width: maxWidth,
          height: rows * rowH - 10,
          child: DragTarget<Duration>(
            onWillAcceptWithDetails: (src) => presets.contains(src.data),
            onMove: (details) {
              final box = context.findRenderObject();
              if (box is! RenderBox || !box.attached) return;
              // details.offset 是拖影（feedback）左上角；手指按 dragAnchorStrategy
              // 锚定在拖影中心 (cell/2, 20)，换算成手指位置再做槽位判定。
              final pointer = box.globalToLocal(details.offset + Offset(cell / 2, 20));
              final slot = slotOf(pointer);
              if (slot != null) {
                ref.read(presetsProvider.notifier).movePresetTo(details.data, slot);
              }
            },
            onAcceptWithDetails: (_) {},
            builder: (context, _, _) =>
                Stack(clipBehavior: Clip.none, children: [for (int i = 0; i < presets.length; i++) cellAt(i)]),
          ),
        );
      },
    );
  }

  Widget _buildPresetCell(ThemeData theme, List<Duration> presets, int index, double cell) {
    final d = presets[index];
    final selected = d == _selected;

    final chipContent = SizedBox(
      width: cell,
      height: 40,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        child: Center(
          child: Text(
            formatClock(d),
            style: theme.textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: selected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );

    // chip 行为随编辑状态切换（编辑模式点 chip = 无操作，不退出编辑、不应用预设）。
    // 悬停排序的 DragTarget 在整个网格上（见 _buildPresetWrap），这里只负责拖起。
    final chip = Consumer(
      builder: (context, ref, child) {
        final editing = ref.watch(presetEditingProvider);
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: editing ? () {} : () => _applyPreset(d),
          child: child,
        );
      },
      child: chipContent,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        LongPressDraggable<Duration>(
          data: d,
          onDragStarted: () => ref.read(presetEditingProvider.notifier).state = true,
          // 拖影中心锚定手指（真机反馈：默认策略手指会钉在图标左上角）。
          // 锚点是 feedback 坐标系里的点，feedback 尺寸 = cell × 40，中心即 (cell/2, 20)。
          dragAnchorStrategy: (draggable, context, position) => Offset(cell / 2, 20),
          feedback: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(20),
            color: theme.colorScheme.primaryContainer,
            child: SizedBox(
              width: cell,
              height: 40,
              child: Center(
                child: Text(
                  formatClock(d),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: chip),
          child: chip,
        ),
        // 删除角标（圆形加横杠）：编辑模式专用，局部重建。
        Positioned(
          top: -8,
          right: -4,
          child: Consumer(
            builder: (context, ref, _) {
              final editing = ref.watch(presetEditingProvider);
              return editing
                  ? GestureDetector(
                      onTap: () => ref.read(presetsProvider.notifier).removeAt(index),
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.colorScheme.error, width: 1.5),
                        ),
                        padding: const EdgeInsets.all(1),
                        child: Icon(
                          Icons.do_not_disturb_on,
                          size: 16,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    )
                  : const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  // ---------- 进行中 / 已暂停 ----------

  Widget _buildRunning(BuildContext context, ThemeData theme, TimerState timer) {
    final running = timer.status == TimerStatus.running;
    final controller = ref.read(timerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (timer.reminderBanner != null)
          Material(
            color: theme.colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(timer.reminderBanner!, style: theme.textTheme.bodyMedium),
            ),
          ),
        if (timer.reminderBanner != null) const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
              formatClock(timer.remaining),
              style: theme.textTheme.displayLarge?.copyWith(
                fontSize: 64,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
        ),
        if (!running)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('已暂停', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ),
        Expanded(child: _buildMarksPanel(theme, timer)),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: running ? () => ref.read(timerProvider.notifier).addMark() : null,
              icon: const Icon(Icons.flag_outlined),
              label: const Text('标记'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: running ? controller.pause : controller.resume,
                icon: Icon(running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                label: Text(running ? '暂停' : '继续'),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => _confirmCancel(context, timer),
              icon: const Icon(Icons.close_rounded),
              label: const Text('取消'),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ---------- 倒计时结束 ----------

  Widget _buildFinished(BuildContext context, ThemeData theme, TimerState timer) {
    final controller = ref.read(timerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
              formatClock(timer.remaining),
              style: theme.textTheme.displayLarge?.copyWith(
                fontSize: 64,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w300,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
        Center(child: Text('倒计时结束', style: theme.textTheme.titleMedium)),
        const SizedBox(height: 8),
        Expanded(child: _buildMarksPanel(theme, timer)),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: controller.silenceRing,
          icon: const Icon(Icons.alarm_off_rounded),
          label: const Text('关闭铃声'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: controller.cancel,
                icon: const Icon(Icons.edit_rounded),
                label: const Text('返回修改时长'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: controller.restart,
                icon: const Icon(Icons.replay_rounded),
                label: const Text('重新开始'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ---------- 标记面板 ----------

  /// 表头行：与下方每行标记的列宽一致，像表格表头。
  Widget _marksHeader(ThemeData theme) {
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    Widget col(String text, [double? width]) => SizedBox(
          width: width,
          child: Text(text, style: style),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          col('序号', 32),
          col('标记点', 104),
          col('耗时', 104),
          const Expanded(child: SizedBox()),
          col('备注'),
        ],
      ),
    );
  }

  Widget _buildMarksPanel(ThemeData theme, TimerState timer) {
    final controller = ref.read(timerProvider.notifier);
    if (timer.marks.isEmpty) {
      return Center(
        child: Text(
          timer.status == TimerStatus.finished ? '本次无标记' : '点击「标记」记录时间节点，不打断计时',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 与下方表头/行同样 8px 内边距、按钮去内边距：
        // 左边"标记记录"对齐"序号"，右边"保存"文字对齐"备注"列右缘（同一条基准线）。
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Text('标记记录 · ${timer.marks.length}', style: theme.textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: controller.undoMark,
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('撤销'),
              ),
              const SizedBox(width: 16),
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: timer.marks.isEmpty ? null : () => _saveMarks(timer),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('保存'),
              ),
            ],
          ),
        ),
        _marksHeader(theme),
        Expanded(
          child: ListView.separated(
            itemCount: timer.marks.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, i) {
              final m = timer.marks[i];
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _editMark(context, m, intervalAt(timer.marks, i)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(m.seq.toString().padLeft(2, '0'), style: theme.textTheme.titleMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: theme.colorScheme.primary,
                        )),
                      ),
                      SizedBox(
                        width: 104,
                        child: Text(formatClockFull(m.remaining), style: theme.textTheme.bodyMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                      ),
                      // 已进行 = 与上一条标记的间隔（第 1 条 = 自开始），v3.6 口径。
                      SizedBox(
                        width: 104,
                        child: Text(formatClockFull(intervalAt(timer.marks, i)), style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                      ),
                      Expanded(
                        child: Text(
                          m.note.isEmpty ? '点击添加备注' : m.note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: m.note.isEmpty
                              ? theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)
                              : theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _editMark(BuildContext context, TimeMark mark, Duration interval) async {
    final result = await showMarkEditDialog(
      context,
      mark: mark,
      total: ref.read(timerProvider).total,
      interval: interval,
    );
    if (!mounted || result == null) return;
    if (result.delete) {
      ref.read(timerProvider.notifier).removeMark(mark.seq);
    } else {
      ref.read(timerProvider.notifier).updateMark(
            mark.seq,
            remaining: result.remaining,
            note: result.note,
          );
    }
  }

  // ---------- 保存到历史记录 ----------

  Future<void> _saveMarks(TimerState timer) async {
    final now = DateTime.now();
    final defaultName =
        '${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)} ${twoDigits(now.hour)}:${twoDigits(now.minute)}';
    final controller = TextEditingController(text: defaultName)
      // 光标定位在文字后方。
      ..selection = TextSelection.collapsed(offset: defaultName.length);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保存到历史记录'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: '记录名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, null), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name == null) return;
    final n = name.trim().isEmpty ? defaultName : name.trim();
    await ref.read(timerProvider.notifier).saveToHistory(n);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存到历史记录，后续标记将自动追加'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _confirmCancel(BuildContext context, TimerState timer) async {
    if (timer.marks.isEmpty) {
      ref.read(timerProvider.notifier).cancel();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消倒计时？'),
        content: Text('已有 ${timer.marks.length} 条标记记录，取消后将丢失（请先保存到历史记录）。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('继续计时')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认取消')),
        ],
      ),
    );
    if (ok == true && mounted) {
      ref.read(timerProvider.notifier).cancel();
    }
  }
}
