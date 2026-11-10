import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/apply_env.dart';

void main() {
  late Directory root;
  late Directory appDir;

  setUp(() {
    root = Directory.systemTemp.createTempSync('apply_env');
    appDir = Directory('${root.path}/app')..createSync();
    Directory('${appDir.path}/web').createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  File fileIn(String path) => File('${appDir.path}/$path');

  void run(String env) {
    final File file = File('${root.path}/.env')..writeAsStringSync(env);
    applyEnv(envFile: file, appDir: appDir);
  }

  Map<String, dynamic> defines() =>
      jsonDecode(fileIn(definesFileName).readAsStringSync())
          as Map<String, dynamic>;

  test('Web の地図のキーを maps_config.js に書く', () {
    run('MAPS_WEB_API_KEY=web-key\n');

    expect(
      fileIn('web/maps_config.js').readAsStringSync(),
      contains('window.uramichiMapsApiKey = "web-key";'),
    );
  });

  test('ビルドの定義には Firebase の値だけを渡す', () {
    run('''
FIREBASE_API_KEY=firebase-key
FIREBASE_PROJECT_ID=project
MAPS_ANDROID_API_KEY=android-key
''');

    expect(defines(), <String, String>{
      'FIREBASE_API_KEY': 'firebase-key',
      'FIREBASE_PROJECT_ID': 'project',
    });
  });

  test('Firebase の値を、アプリに同梱する設定のファイルにも書く', () {
    run('FIREBASE_API_KEY=firebase-key\nMAPS_ANDROID_API_KEY=android-key\n');

    expect(
      jsonDecode(fileIn(firebaseConfigAsset).readAsStringSync()),
      <String, String>{'FIREBASE_API_KEY': 'firebase-key'},
    );
  });

  test('コメント、空行、引用符、export の付いた行を読む', () {
    expect(
      parseEnv('''
# コメント
A=1

B="二 重"
C='一重'
export D=4
E=
BROKEN
'''),
      <String, String>{'A': '1', 'B': '二 重', 'C': '一重', 'D': '4', 'E': ''},
    );
  });

  test('キーがないときは maps_config.js を消し、アプリを簡易地図で動かす', () {
    fileIn('web/maps_config.js').writeAsStringSync('古いキー');

    run('MAPS_WEB_API_KEY=\n');

    expect(fileIn('web/maps_config.js').existsSync(), isFalse);
    expect(defines(), isEmpty);
  });

  test('.env がなくても、flutter が読むファイルを作る', () {
    applyEnv(envFile: File('${root.path}/ない.env'), appDir: appDir);

    expect(defines(), isEmpty);
  });

  test('キーに引用符が含まれても JavaScript の文字列を壊さない', () {
    run('MAPS_WEB_API_KEY=a"b\n');

    expect(
      fileIn('web/maps_config.js').readAsStringSync(),
      contains(r'"a\"b"'),
    );
  });
}
