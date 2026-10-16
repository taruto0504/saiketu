import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/disclaimer_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/main_shell.dart';
import 'services/app_services.dart';
import 'services/settings.dart';
import 'theme.dart';

class LabSightApp extends StatefulWidget {
  const LabSightApp({super.key});

  @override
  State<LabSightApp> createState() => _LabSightAppState();
}

class _LabSightAppState extends State<LabSightApp> with WidgetsBindingObserver {
  late bool _locked;
  bool _obscured = false;
  DateTime? _backgroundAt;
  Timer? _idle;

  AppSettings get _settings => context.read<AppSettings>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locked = context.read<AppSettings>().lockEnabled;
    _resetIdle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idle?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = _settings.lockEnabled;
    switch (state) {
      case AppLifecycleState.resumed:
        final bg = _backgroundAt;
        _backgroundAt = null;
        if (lock && bg != null && DateTime.now().difference(bg) >= Duration(minutes: _settings.autoLockMinutes)) {
          _locked = true;
        }
        setState(() => _obscured = false);
        _resetIdle();
        context.read<AppServices>().runAutoDelete();
      case AppLifecycleState.inactive:
        // アプリ切替画面に内容が映らないよう隠す
        if (lock) setState(() => _obscured = true);
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundAt ??= DateTime.now();
        if (lock) setState(() => _obscured = true);
      case AppLifecycleState.detached:
        break;
    }
  }

  void _resetIdle() {
    _idle?.cancel();
    if (!_settings.lockEnabled) return;
    _idle = Timer(Duration(minutes: _settings.autoLockMinutes), () {
      if (mounted && _settings.lockEnabled) setState(() => _locked = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    return MaterialApp(
      title: 'LabSight',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: settings.themeMode,
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final scaled = MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1.0) * settings.textScale)),
          child: child!,
        );
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _resetIdle(),
          child: Stack(
            children: [
              scaled,
              if (_locked && settings.lockEnabled)
                Positioned.fill(
                  child: LockScreen(onUnlocked: () {
                    setState(() => _locked = false);
                    _resetIdle();
                  }),
                ),
              if (_obscured && settings.lockEnabled && !(_locked))
                Positioned.fill(child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor)),
            ],
          ),
        );
      },
      home: settings.agreed ? const MainShell() : const DisclaimerScreen(),
    );
  }
}
