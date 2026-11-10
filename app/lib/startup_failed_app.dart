import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme.dart';
import 'core/widgets/state_view.dart';
import 'core/strings.dart';

/// 配布版で Firebase を初期化できなかったときの画面。押すと初期化からやり直す
class StartupFailedApp extends StatelessWidget {
  const StartupFailedApp({super.key, required this.onRetry});

  /// 初期化からやり直す。成功すると、アプリの画面に置き換わる
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: l10n.appTitle,
    locale: const Locale('ja', 'JP'),
    supportedLocales: const <Locale>[Locale('ja', 'JP')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    debugShowCheckedModeBanner: false,
    home: _StartupFailedScreen(onRetry: onRetry),
  );
}

class _StartupFailedScreen extends StatefulWidget {
  const _StartupFailedScreen({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  State<_StartupFailedScreen> createState() => _StartupFailedScreenState();
}

class _StartupFailedScreenState extends State<_StartupFailedScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: _retrying
          ? const Center(child: CircularProgressIndicator())
          : StateView(
              icon: Icons.cloud_off_outlined,
              title: l10n.startupFailedTitle,
              primary: StateViewAction(l10n.retry, _retry, icon: Icons.refresh),
            ),
    ),
  );
}
