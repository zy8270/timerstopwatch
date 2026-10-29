import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/fake_sleep_controller.dart';
import '../controllers/presets_controller.dart';
import '../controllers/settings_controller.dart';
import '../controllers/timer_controller.dart';
import '../core/format.dart';
import '../services/native_channel.dart';
import 'ui/pages/history_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/pages/timer_page.dart';
import 'ui/widgets/fake_sleep_layer.dart';

class TimerApp extends StatelessWidget {
  const TimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3F6DF5);
    return MaterialApp(
      title: '计时器',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed), useMaterial3: true),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const NavShell(),
    );
  }
}

/// 底部导航：历史 | 计时 | 设置（计时居中，默认选中）。
/// 同时承载：原生回调（通知标记/响铃关闭）、前后台切换的悬浮窗联动、首启权限引导、
/// 空闲检测与假睡眠常亮模式（覆盖全屏，含底部导航）。
class NavShell extends ConsumerStatefulWidget {
  const NavShell({super.key});

  @override
  ConsumerState<NavShell> createState() => _NavShellState();
}

class _NavShellState extends ConsumerState<NavShell> with WidgetsBindingObserver {
  /// 默认落在中间的「计时」页。
  int _index = 1;
  bool _overlayGuidePending = false;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NativeChannel.init(onCall: _onNativeCall);
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstRunGuide());
    // 被杀后重启时计时会话直接从快照恢复（provider 初始值即活跃），
    // ref.listen 不会对初始值触发，这里补一次空闲计时启动。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(timerProvider).isSessionActive) _restartIdleTimer();
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onNativeCall(String method) {
    debugPrint('[timer] native call: $method');
    switch (method) {
      case 'onNotificationMark':
        ref.read(timerProvider.notifier).onNotificationMark();
      case 'onRingStopped':
        ref.read(timerProvider.notifier).onRingStoppedExternally();
    }
  }

  // ---------- 首启权限引导：通知 → 精确闹铃 ----------

  Future<void> _firstRunGuide() async {
    final settings = ref.read(settingsProvider);
    if (!settings.notifGuideDone) {
      await NativeChannel.notifRequest();
      await ref.read(settingsProvider.notifier).markNotifGuideDone();
    }
    if (!mounted) return;
    if (!await NativeChannel.exactGranted()) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('授予精确闹铃权限'),
          content: const Text('为保证退出应用或清理后台后，倒计时到点仍能准时响铃，请在系统设置中允许本应用使用闹钟提醒。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('暂不')),
            FilledButton(
              onPressed: () {
                NativeChannel.exactRequest();
                Navigator.pop(context);
              },
              child: const Text('去设置'),
            ),
          ],
        ),
      );
    }
  }

  // ---------- 前后台切换：悬浮窗 ----------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final timer = ref.read(timerProvider);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _idleTimer?.cancel();
      if (timer.isSessionActive) {
        _onGoBackground();
      }
    } else if (state == AppLifecycleState.resumed) {
      NativeChannel.overlayHide();
      _maybeShowOverlayGuide();
      if (ref.read(timerProvider).isSessionActive) _restartIdleTimer();
    }
  }

  Future<void> _onGoBackground() async {
    final timer = ref.read(timerProvider);
    if (await NativeChannel.overlayGranted()) {
      await NativeChannel.overlayShow(formatClock(timer.remaining));
      return;
    }
    final settings = ref.read(settingsProvider);
    if (!settings.overlayGuideDone) {
      await ref.read(settingsProvider.notifier).markOverlayGuideDone();
      _overlayGuidePending = true;
    }
  }

  Future<void> _maybeShowOverlayGuide() async {
    if (!_overlayGuidePending) return;
    _overlayGuidePending = false;
    if (await NativeChannel.overlayGranted()) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('开启倒计时悬浮窗？'),
        content: const Text('授予"显示在其他应用上层"权限后，切到后台时会出现半透明悬浮窗显示倒计时，并可从常驻通知直接标记。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('暂不')),
          FilledButton(
            onPressed: () {
              NativeChannel.overlayRequest();
              Navigator.pop(context);
            },
            child: const Text('去开启'),
          ),
        ],
      ),
    );
  }

  // ---------- 空闲检测与假睡眠 ----------

  void _onUserActivity() {
    ref.read(fakeSleepProvider.notifier).clearReEntry();
    _restartIdleTimer();
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    if (!mounted) return;
    if (!ref.read(timerProvider).isSessionActive) return;
    final settings = ref.read(settingsProvider);
    if (!settings.fakeSleepEnabled) return;
    final sec = ref.read(fakeSleepProvider).reEntrySec ?? settings.idleTimeoutSec;
    _idleTimer = Timer(Duration(seconds: sec), () {
      if (!mounted) return;
      if (ref.read(timerProvider).isSessionActive) {
        ref.read(fakeSleepProvider.notifier).enter();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fakeSleep = ref.watch(fakeSleepProvider);

    // 会话开始启动空闲计时；会话结束清理并退出假睡眠。
    ref.listen(timerProvider, (prev, next) {
      final was = prev?.isSessionActive ?? false;
      final active = next.isSessionActive;
      if (!was && active) {
        _restartIdleTimer();
      } else if (was && !active) {
        _idleTimer?.cancel();
        ref.read(fakeSleepProvider.notifier).exit();
      }
    });

    return Listener(
      onPointerDown: (_) => _onUserActivity(),
      onPointerMove: (_) => _onUserActivity(),
      child: Stack(
        children: [
          Scaffold(
            body: IndexedStack(
              index: _index,
              children: const [HistoryPage(), TimerPage(), SettingsPage()],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              // 切换页签时退出计时页的预设编辑模式（真机反馈：切页后编辑状态残留）。
              onDestinationSelected: (i) {
                ref.read(presetEditingProvider.notifier).state = false;
                setState(() => _index = i);
              },
              destinations: const [
                NavigationDestination(icon: Icon(Icons.history_rounded), selectedIcon: Icon(Icons.history), label: '历史'),
                NavigationDestination(icon: Icon(Icons.timer_outlined), selectedIcon: Icon(Icons.timer), label: '计时'),
                NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
              ],
            ),
          ),
          if (fakeSleep.active) const FakeSleepLayer(),
        ],
      ),
    );
  }
}
