import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api/uramichi_api.dart';
import 'core/auth/account_controller.dart';
import 'core/config.dart';
import 'core/data/checkin_repository.dart';
import 'core/data/favorites.dart';
import 'core/location/location_service.dart';
import 'core/location/visit_recorder.dart';
import 'core/services.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'features/account/account_gate.dart';
import 'features/home/home_screen.dart';
import 'core/strings.dart';

class UramichiApp extends StatefulWidget {
  UramichiApp({
    super.key,
    required this.api,
    required this.account,
    required this.checkins,
    LocationService? location,
    VisitRecorder? visits,
    AppSettings? settings,
    this.config = const AppConfig(),
  }) : location = location ?? DeviceLocationService(),
       visits =
           visits ??
           VisitRecorder(location: location ?? DeviceLocationService()),
       settings = settings ?? AppSettings();

  final UramichiApi api;
  final AccountController account;
  final CheckinRepository checkins;
  final LocationService location;
  final VisitRecorder visits;
  final AppSettings settings;
  final AppConfig config;

  @override
  State<UramichiApp> createState() => _UramichiAppState();
}

class _UramichiAppState extends State<UramichiApp> {
  late final FavoritesController _favorites = FavoritesController(
    api: widget.api,
  );

  @override
  void initState() {
    super.initState();
    widget.account.addListener(_onAccountChanged);
    _onAccountChanged();
    widget.settings.addListener(_syncDemoMode);
    _syncDemoMode();
  }

  // 設定の「デモデータで動かす」を API に伝える
  void _syncDemoMode() => widget.api.demoMode = widget.settings.demoMode;

  // ログインしている利用者のお気に入りに切り替える
  void _onAccountChanged() => _favorites.setUser(widget.account.user?.uid);

  @override
  void dispose() {
    widget.account.removeListener(_onAccountChanged);
    widget.settings.removeListener(_syncDemoMode);
    _favorites.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Services(
    api: widget.api,
    account: widget.account,
    checkins: widget.checkins,
    location: widget.location,
    visits: widget.visits,
    settings: widget.settings,
    config: widget.config,
    favorites: _favorites,
    child: DynamicColorBuilder(
      builder: (ColorScheme? wallpaperLight, ColorScheme? _) {
        // 壁紙の色は端末から非同期で届くため、届いた時点の値を設定に渡しておき、設定の画面で選べるようにする
        widget.settings.wallpaperColor = wallpaperLight?.primary;
        return ListenableBuilder(
          listenable: widget.settings,
          builder: (BuildContext context, Widget? _) {
            final Color key = widget.settings.resolveKeyColor();
            return MaterialApp(
              title: l10n.appTitle,
              // 端末の言語が英語でも日本語の字形と Material の部品の文言で表示する。
              // 端末の言語に合わせないのは、画面の文言を日本語でしか用意していないため
              locale: const Locale('ja', 'JP'),
              supportedLocales: const <Locale>[Locale('ja', 'JP')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: AppTheme.light(key: key),
              darkTheme: AppTheme.dark(key: key),
              themeMode: widget.settings.themeMode,
              debugShowCheckedModeBanner: false,
              home: AccountGate(
                account: widget.account,
                child: const HomeScreen(),
              ),
            );
          },
        );
      },
    ),
  );
}
