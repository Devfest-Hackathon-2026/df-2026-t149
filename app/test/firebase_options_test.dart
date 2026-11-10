import 'dart:convert';

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/firebase_options.dart';

/// 指定したアセットだけを持つ、アプリに同梱したファイルの代わり
class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final String? text = files[key];
    if (text == null) {
      throw FlutterError('アセットがありません: $key');
    }
    return ByteData.sublistView(utf8.encode(text));
  }
}

const Map<String, String> _values = <String, String>{
  'FIREBASE_API_KEY': 'key',
  'FIREBASE_ANDROID_APP_ID': 'android-app',
  'FIREBASE_WEB_APP_ID': 'web-app',
  'FIREBASE_MESSAGING_SENDER_ID': '123',
  'FIREBASE_PROJECT_ID': 'uramichi',
  'FIREBASE_WEB_CLIENT_ID': 'web-client',
};

void main() {
  test('Android のログイン用 ID を同梱した設定から読む', () async {
    final bundle = _Bundle(<String, String>{
      DefaultFirebaseOptions.configAsset: jsonEncode(_values),
    });
    expect(
      await DefaultFirebaseOptions.loadWebClientId(bundle: bundle),
      'web-client',
    );
  });

  test('ログイン用 ID はビルド時の指定を優先する', () async {
    final bundle = _Bundle(<String, String>{
      DefaultFirebaseOptions.configAsset: jsonEncode(_values),
    });
    expect(
      await DefaultFirebaseOptions.loadWebClientId(
        bundle: bundle,
        definedClientId: 'defined-client',
      ),
      'defined-client',
    );
  });

  test('ログイン用 ID がない場合は null を返す', () async {
    expect(
      await DefaultFirebaseOptions.loadWebClientId(bundle: _Bundle(const {})),
      isNull,
    );
  });

  test('--dart-define がなくても、アプリに同梱した設定のファイルから Firebase の設定を読む', () async {
    final FirebaseOptions options = await DefaultFirebaseOptions.load(
      bundle: _Bundle(<String, String>{
        DefaultFirebaseOptions.configAsset: jsonEncode(_values),
      }),
    );

    expect(options.apiKey, 'key');
    expect(options.projectId, 'uramichi');
  });

  test('設定のファイルもなければ、設定がないことを例外で伝える', () async {
    await expectLater(
      DefaultFirebaseOptions.load(bundle: _Bundle(const <String, String>{})),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('Android と Web で、それぞれのアプリの ID を使う', () {
    expect(
      DefaultFirebaseOptions.fromValues(_values, isWeb: false).appId,
      'android-app',
    );
    expect(
      DefaultFirebaseOptions.fromValues(_values, isWeb: true).appId,
      'web-app',
    );
  });
}
