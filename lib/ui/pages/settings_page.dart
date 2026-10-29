import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/presets_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../core/format.dart';
import '../../services/native_channel.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> with WidgetsBindingObserver {
  bool _notifGranted = true;
  bool _exactGranted = true;
  bool _overlayGranted = false;
  bool _dndGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置页返回时刷新权限状态。
    if (state == AppLifecycleState.resumed) _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final notif = await NativeChannel.notifGranted();
    final exact = await NativeChannel.exactGranted();
    final overlay = await NativeChannel.overlayGranted();
    final dnd = await NativeChannel.dndGranted();
    if (!mounted) return;
    setState(() {
      _notifGranted = notif;
      _exactGranted = exact;
      _overlayGranted = overlay;
      _dndGranted = dnd;
    });
  }

  String _baseName(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    return name.replaceFirst(RegExp(r'^audio_\d+\.'), '').replaceAll(RegExp(r'\.[^.]+$'), '');
  }

  // ---------- 时长输入解析：支持 "90"、"1:30"、"1:30:20" ----------

  Duration? _parseDuration(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final parts = text.split(':');
    if (parts.length > 3) return null;
    final nums = <int>[];
    for (final p in parts) {
      final v = int.tryParse(p.trim());
      if (v == null || v < 0) return null;
      nums.add(v);
    }
    while (nums.length < 3) {
      nums.insert(0, 0);
    }
    final d = Duration(hours: nums[0], minutes: nums[1], seconds: nums[2]);
    return d > Duration.zero ? d : null;
  }

  Future<Duration?> _askDuration(String title) async {
    final controller = TextEditingController();
    final d = await showDialog<Duration>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '如 90、1:30、1:30:20', labelText: '时长（秒 或 分:秒 或 时:分:秒）'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, _parseDuration(controller.text)),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return d;
  }

  // ---------- 删除确认（阈值 / 固定预设共用） ----------

  /// 红色删除按钮：点击弹二次确认，确认后才执行删除。
  Widget _deleteButton(ThemeData theme, String what, VoidCallback onDelete) {
    return IconButton(
      tooltip: '删除$what',
      icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
      onPressed: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('删除$what？'),
            content: const Text('删除后不可恢复，确定继续吗？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (ok == true) onDelete();
      },
    );
  }

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final presets = ref.watch(presetsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _section(theme, '提示音'),
          ListTile(
            leading: const Icon(Icons.alarm_rounded),
            title: const Text('结束铃声'),
            subtitle: Text(settings.ringAudioPath == null ? '系统闹钟声' : _baseName(settings.ringAudioPath!)),
            trailing: settings.ringAudioPath == null ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => ref.read(settingsProvider.notifier).setRingAudio(null)),
            onTap: () => _pickRingAudio(context),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.vibration_rounded),
            title: const Text('结束响铃时震动'),
            value: settings.ringVibrate,
            onChanged: (v) => ref.read(settingsProvider.notifier).setRingVibrate(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('剩余提醒时震动'),
            value: settings.reminderVibrate,
            onChanged: (v) => ref.read(settingsProvider.notifier).setReminderVibrate(v),
          ),
          _section(theme, '剩余提醒阈值'),
          for (final rule in settings.thresholds)
            ListTile(
              dense: true,
              leading: const Icon(Icons.notifications_outlined),
              title: Text('剩余 ${formatClockFull(Duration(seconds: rule.seconds))} 时提醒'),
              subtitle: Text(rule.audioPath == null ? '系统提示音' : _baseName(rule.audioPath!)),
              trailing: _deleteButton(theme, '该阈值', () => ref.read(settingsProvider.notifier).removeThreshold(rule.seconds)),
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.add_rounded),
            title: const Text('添加提醒阈值'),
            subtitle: const Text('如剩 30 分、10 分、1 分各提醒一次'),
            onTap: _addThreshold,
          ),
          _section(theme, '快捷预设'),
          if (presets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('计时页的快捷预设：最近使用的时长会自动置顶，也可在下方添加固定预设。', style: TextStyle(fontSize: 12)),
            ),
          for (int i = 0; i < presets.length; i++)
            ListTile(
              dense: true,
              leading: const Icon(Icons.timer_outlined),
              title: Text(formatClockFull(presets[i])),
              trailing: _deleteButton(theme, '该预设', () => ref.read(presetsProvider.notifier).removeAt(i)),
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.add_rounded),
            title: const Text('添加固定预设'),
            subtitle: const Text('新添加的预设会排在最前'),
            onTap: () async {
              final d = await _askDuration('添加固定预设');
              if (d != null) await ref.read(presetsProvider.notifier).addPreset(d);
            },
          ),
          _section(theme, '假睡眠常亮'),
          SwitchListTile(
            secondary: const Icon(Icons.bedtime_outlined),
            title: const Text('倒计时时启用假睡眠'),
            subtitle: const Text('无操作一段时间后进入全屏调暗，只显示倒计时，防止烧屏'),
            value: settings.fakeSleepEnabled,
            onChanged: (v) => ref.read(settingsProvider.notifier).setFakeSleepEnabled(v),
          ),
          ListTile(
            enabled: settings.fakeSleepEnabled,
            leading: const Icon(Icons.hourglass_bottom_rounded),
            title: const Text('无操作进入时长'),
            subtitle: Text(_idleLabel(settings.idleTimeoutSec)),
            onTap: () => _pickIdleTimeout(settings.idleTimeoutSec),
          ),
          _section(theme, '勿扰模式'),
          SwitchListTile(
            secondary: const Icon(Icons.do_not_disturb_on_rounded),
            title: const Text('倒计时时自动开启勿扰'),
            subtitle: Text(_dndGranted ? '结束时自动恢复原状；来电与消息由系统勿扰规则静音' : '需要先授予"勿扰访问权限"'),
            value: settings.dndEnabled,
            onChanged: (v) => _toggleDnd(v),
          ),
          if (settings.dndEnabled)
            SwitchListTile(
              secondary: const Icon(Icons.phonelink_ring_rounded),
              title: const Text('响铃前临时解除勿扰'),
              subtitle: const Text('确保结束铃声必定可闻（兜底方案，默认关闭）'),
              value: settings.dndLiftOnRing,
              onChanged: (v) => ref.read(settingsProvider.notifier).setDndLiftOnRing(v),
            ),
          _section(theme, '权限'),
          ListTile(
            leading: const Icon(Icons.notifications_rounded),
            title: const Text('通知权限'),
            subtitle: Text(_notifGranted ? '已授权' : '未授权：后台无倒计时通知'),
            trailing: _notifGranted ? null : FilledButton.tonal(onPressed: () async { await NativeChannel.notifRequest(); _refreshPermissions(); }, child: const Text('去授权')),
          ),
          ListTile(
            leading: const Icon(Icons.alarm_rounded),
            title: const Text('精确闹铃权限'),
            subtitle: Text(_exactGranted ? '已授权' : '未授权：清理后台后可能无法准时响铃'),
            trailing: _exactGranted ? null : FilledButton.tonal(onPressed: () async { await NativeChannel.exactRequest(); _refreshPermissions(); }, child: const Text('去授权')),
          ),
          ListTile(
            leading: const Icon(Icons.picture_in_picture_rounded),
            title: const Text('悬浮窗权限'),
            subtitle: Text(_overlayGranted ? '已授权' : '未授权：切后台无倒计时悬浮窗'),
            trailing: _overlayGranted ? null : FilledButton.tonal(onPressed: () async { await NativeChannel.overlayRequest(); _refreshPermissions(); }, child: const Text('去授权')),
          ),
          _section(theme, '关于'),
          // 版本可现场核对面板（真机反馈排查依赖：确认装的是最新构建）。
          const ListTile(
            dense: true,
            leading: Icon(Icons.verified_outlined),
            title: Text('版本'),
            subtitle: Text('v1.0.6'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('计时器是一款专注"时间段标记"的安卓倒计时应用：'
                    '倒计时进行中随时点「标记」记录时间节点（不打断计时），'
                    '每条标记显示该节点剩余时间与距上一条标记的间隔，备注可随时补写；'
                    '标记可保存到历史记录并复制导出为表格文本，方便回溯各阶段耗时。', style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Text('其他特性：剩余时间多阈值提醒（各配提示音）、'
                    '伪熄屏常亮防烧屏、后台悬浮窗与常驻通知（通知栏可直接标记）、'
                    '勿扰联动、杀进程后仍准时响铃的精确闹铃兜底。', style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Text('本项目以 MIT 协议开源，欢迎 Star / Issue / PR：', style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () async {
                    final url = Uri.parse('https://github.com/zy8270/timerstopwatch');
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  },
                  child: Text(
                    'https://github.com/zy8270/timerstopwatch',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const AboutListTile(
            icon: Icon(Icons.info_outline_rounded),
            applicationName: '计时器',
            applicationVersion: 'v1.0.6',
            aboutBoxChildren: [Text('倒计时 + 时间段标记 + 剩余提醒 + 历史记录 + 伪熄屏常亮 + 悬浮窗/常驻通知 + 勿扰联动')],
          ),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }

  String _idleLabel(int sec) {
    if (sec < 60) return '$sec 秒';
    if (sec % 60 == 0) return '${sec ~/ 60} 分钟';
    return '${sec.toStringAsFixed(0)} 秒';
  }

  Future<void> _pickIdleTimeout(int current) async {
    final sec = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('无操作进入假睡眠'),
        children: [30, 60, 120, 300]
            .map((s) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, s),
                  child: Text(_idleLabel(s)),
                ))
            .toList(),
      ),
    );
    if (sec != null) await ref.read(settingsProvider.notifier).setIdleTimeoutSec(sec);
  }

  Future<void> _toggleDnd(bool enable) async {
    final notifier = ref.read(settingsProvider.notifier);
    if (!enable) {
      await notifier.setDndEnabled(false);
      return;
    }
    if (!await NativeChannel.dndGranted()) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('授予勿扰访问权限'),
          content: const Text('自动开关勿扰需要系统"勿扰访问权限"。请在设置中找到本应用并允许。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                NativeChannel.dndRequest();
                Navigator.pop(context);
              },
              child: const Text('去授权'),
            ),
          ],
        ),
      );
      _refreshPermissions();
      return;
    }
    await notifier.setDndEnabled(true);
  }

  Future<void> _pickRingAudio(BuildContext context) async {
    final notifier = ref.read(settingsProvider.notifier);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('结束铃声'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'system'), child: const Text('系统闹钟声')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'file'), child: const Text('从文件导入…')),
        ],
      ),
    );
    if (choice == 'system') {
      await notifier.setRingAudio(null);
    } else if (choice == 'file') {
      final path = await NativeChannel.pickAudio();
      if (path != null) await notifier.setRingAudio(path);
    }
  }

  Future<void> _addThreshold() async {
    final d = await _askDuration('剩余多久时提醒？');
    if (d == null || !mounted) return;
    final sec = d.inSeconds;
    final notifier = ref.read(settingsProvider.notifier);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('剩余 ${formatClockFull(d)} 时播放'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'system'), child: const Text('系统提示音')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'file'), child: const Text('从文件导入…')),
        ],
      ),
    );
    if (choice == 'system') {
      await notifier.addThreshold(sec, null);
    } else if (choice == 'file') {
      final path = await NativeChannel.pickAudio();
      if (path != null) await notifier.addThreshold(sec, path);
    }
  }
}
