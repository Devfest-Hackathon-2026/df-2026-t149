// Firebase の設定は Git に含めず、app/.env から渡す（docs/setup.md）。
//
// 設定がなければ例外を投げ、アプリは Firebase を使わずに端末に保存して動く。
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DefaultFirebaseOptions {
  /// app/.env の FIREBASE_* から作り、アプリに同梱する設定。Git に含めない。
  /// Android は Gradle がビルドのたびに作り、Web は tool/apply_env.dart が作る
  static const String configAsset = 'assets/config/firebase.local.json';

  // flutterfire configure が作るファイルをコミットすると、値がリポジトリに入るため、ビルド時に受け取る
  static const Map<String, String> _defines = <String, String>{
    'FIREBASE_API_KEY': String.fromEnvironment('FIREBASE_API_KEY'),
    'FIREBASE_WEB_APP_ID': String.fromEnvironment('FIREBASE_WEB_APP_ID'),
    'FIREBASE_ANDROID_APP_ID': String.fromEnvironment(
      'FIREBASE_ANDROID_APP_ID',
    ),
    'FIREBASE_MESSAGING_SENDER_ID': String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
    ),
    'FIREBASE_PROJECT_ID': String.fromEnvironment('FIREBASE_PROJECT_ID'),
  };

  /// --dart-define で渡した設定を使い、なければ同梱した設定のファイルから読む。
  // --dart-define だけにすると、`flutter build apk` で指定を付け忘れたときに Firebase のないアプリができるため
  static Future<FirebaseOptions> load({AssetBundle? bundle}) async {
    Map<String, String> values = _defines;
    if (values['FIREBASE_API_KEY']!.isEmpty) {
      values = await _loadAsset(bundle);
    }
    return fromValues(values, isWeb: kIsWeb);
  }

  static Future<String?> loadWebClientId({
    AssetBundle? bundle,
    String definedClientId = const String.fromEnvironment(
      'FIREBASE_WEB_CLIENT_ID',
    ),
  }) async {
    if (definedClientId.isNotEmpty) {
      return definedClientId;
    }
    final String value =
        (await _loadAsset(bundle))['FIREBASE_WEB_CLIENT_ID'] ?? '';
    return value.isEmpty ? null : value;
  }

  static Future<Map<String, String>> _loadAsset(AssetBundle? bundle) async {
    try {
      final String text = await (bundle ?? rootBundle).loadString(configAsset);
      return <String, String>{
        for (final MapEntry<String, dynamic> entry
            in (jsonDecode(text) as Map<String, dynamic>).entries)
          entry.key: '${entry.value}',
      };
    } on FlutterError {
      return <String, String>{};
    }
  }

  @visibleForTesting
  static FirebaseOptions fromValues(
    Map<String, String> values, {
    required bool isWeb,
  }) {
    final String apiKey = values['FIREBASE_API_KEY'] ?? '';
    final String projectId = values['FIREBASE_PROJECT_ID'] ?? '';
    final String appId =
        values[isWeb ? 'FIREBASE_WEB_APP_ID' : 'FIREBASE_ANDROID_APP_ID'] ?? '';
    if (apiKey.isEmpty || appId.isEmpty || projectId.isEmpty) {
      throw UnsupportedError('app/.env に Firebase の設定がありません（docs/setup.md）');
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: values['FIREBASE_MESSAGING_SENDER_ID'] ?? '',
      projectId: projectId,
      authDomain: '$projectId.firebaseapp.com',
      storageBucket: '$projectId.firebasestorage.app',
    );
  }
}
