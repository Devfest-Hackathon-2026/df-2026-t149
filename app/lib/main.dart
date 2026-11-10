import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/api/api_endpoint.dart';
import 'core/api/uramichi_api.dart';
import 'core/auth/account_binding.dart';
import 'core/auth/account_controller.dart';
import 'core/auth/auth_gateway.dart';
import 'core/auth/firebase_auth_gateway.dart';
import 'core/config.dart';
import 'core/data/api_checkin_repository.dart';
import 'core/data/checkin_repository.dart';
import 'core/data/profile_repository.dart';
import 'core/location/location_service.dart';
import 'core/location/visit_recorder.dart';
import 'core/maps/maps_support.dart';
import 'core/settings.dart';
import 'core/sounds.dart';
import 'firebase_options.dart';
import 'startup_failed_app.dart';
import 'core/widgets/error_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 同梱した書体のライセンスを、設定の「ライセンス」に載せる
  LicenseRegistry.addLicense(() async* {
    final String ofl = await rootBundle.loadString(
      'assets/google_fonts/OFL.txt',
    );
    yield LicenseEntryWithLineBreaks(<String>['Zen Kaku Gothic New'], ofl);
  });
  // 配布用のビルドでも、グレーの四角ではなく例外の内容を出し、報告してもらえるようにする
  if (kReleaseMode) {
    ErrorWidget.builder = BuildErrorView.builder;
  }
  await _start();
}

/// 設定を読み、アプリの画面を表示する。配布版で Firebase を使えないときは、やり直す画面を表示する
Future<void> _start() async {
  final (
    _FirebaseInit firebase,
    SharedPreferences prefs,
    AppConfig config,
    _,
  ) = await (
    _initFirebase(),
    SharedPreferences.getInstance(),
    AppConfig.load(),
    MapsSupport.detect(),
  ).wait;
  // 配布版で開発用のログインに切り替えると、Google にログインしていないのにログインした表示になるため使わない
  if (firebase == _FirebaseInit.failed && kReleaseMode) {
    runApp(StartupFailedApp(onRetry: _start));
    return;
  }
  final bool firebaseReady = firebase == _FirebaseInit.ready;
  final String? baseUrl = await resolveApiBaseUrl(
    environment: kIsWeb && kReleaseMode
        ? RunEnvironment.webRelease
        : (kReleaseMode ? RunEnvironment.release : RunEnvironment.development),
    configured: config.apiBaseUrl,
    isReachable: isServerReachable,
  );

  final AuthGateway auth = firebaseReady
      ? FirebaseAuthGateway()
      : LocalAuthGateway();
  final UramichiApi api = UramichiApi(baseUrl: baseUrl, idToken: auth.idToken);
  final AccountController account = AccountController(
    auth: auth,
    profiles: baseUrl == null
        ? LocalProfileRepository(prefs: prefs)
        : ApiProfileRepository(api: api, idToken: auth.idToken, prefs: prefs),
  );
  final CheckinRepository checkins = firebaseReady
      ? ApiCheckinRepository(
          api: api,
          idTokenFor: auth.idTokenFor,
          prefs: prefs,
        )
      : LocalCheckinRepository(prefs: prefs);
  final LocationService location = DeviceLocationService();
  final VisitRecorder visits = VisitRecorder(location: location, prefs: prefs);
  await visits.resume();
  bindRecordsToAccount(account, checkins: checkins, visits: visits);
  unawaited(account.start());
  // 効果音は起動を待たせずに読み込む
  unawaited(Sounds.init());

  runApp(
    UramichiApp(
      api: api,
      account: account,
      checkins: checkins,
      location: location,
      visits: visits,
      settings: AppSettings.load(prefs),
      config: config,
    ),
  );
}

enum _FirebaseInit { ready, failed }

/// Firebase を初期化する
///
/// firebase_options.dart の設定（.env の FIREBASE_*）があれば Google アカウントでログインし、
/// チェックインと思い出ログを API サーバーに保存する。開発中に設定がないときは、開発用のログインで端末に保存する。
/// 圏外で初めて起動して時間切れになったときも、通信が戻ればログインできるよう ready を返す
Future<_FirebaseInit> _initFirebase() async {
  try {
    final FirebaseOptions options = await DefaultFirebaseOptions.load();
    await Firebase.initializeApp(
      options: options,
    ).timeout(const Duration(seconds: 5));
    return _FirebaseInit.ready;
  } on TimeoutException {
    return _FirebaseInit.ready;
  } catch (error) {
    debugPrint('Firebase を初期化できません: $error');
    return _FirebaseInit.failed;
  }
}
