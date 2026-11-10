// app/.env から、アプリのビルドに必要なファイルを作る。
//
// 使い方（app/ で実行）: dart run tool/apply_env.dart
//
// flutter の --dart-define-from-file に .env を直接渡すと、Android の地図のキーまでビルドの定義に入るため使わない。
import 'dart:convert';
import 'dart:io';

/// flutter run の --dart-define-from-file に渡すファイル。Git に含めない
const String definesFileName = 'dart_defines.local.json';

/// アプリに同梱する Firebase の設定（lib/firebase_options.dart が読む）。Git に含めない
const String firebaseConfigAsset = 'assets/config/firebase.local.json';

Map<String, String> parseEnv(String text) {
  final Map<String, String> values = <String, String>{};
  for (final String raw in const LineSplitter().convert(text)) {
    String line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    if (line.startsWith('export ')) {
      line = line.substring('export '.length).trim();
    }
    final int separator = line.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    String value = line.substring(separator + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    values[line.substring(0, separator).trim()] = value;
  }
  return values;
}

void applyEnv({required File envFile, required Directory appDir}) {
  final Map<String, String> env = envFile.existsSync()
      ? parseEnv(envFile.readAsStringSync())
      : const <String, String>{};

  final File mapsConfig = File('${appDir.path}/web/maps_config.js');
  final String mapsKey = env['MAPS_WEB_API_KEY'] ?? '';
  if (mapsKey.isNotEmpty) {
    mapsConfig.writeAsStringSync(
      '// tool/apply_env.dart が .env から作るファイル。Git に含めない\n'
      'window.uramichiMapsApiKey = ${jsonEncode(mapsKey)};\n',
    );
  } else if (mapsConfig.existsSync()) {
    mapsConfig.deleteSync();
  }

  final String firebase = jsonEncode(<String, String>{
    for (final MapEntry<String, String> e in env.entries)
      if (e.key.startsWith('FIREBASE_') && e.value.isNotEmpty) e.key: e.value,
  });
  File('${appDir.path}/$definesFileName').writeAsStringSync(firebase);
  // flutter build web に --dart-define-from-file を付け忘れても、アプリに同梱したこのファイルから読む
  File('${appDir.path}/$firebaseConfigAsset')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(firebase);
}

void main() {
  applyEnv(envFile: File('.env'), appDir: Directory.current);
  stdout.writeln(
    '.env から web/maps_config.js、$definesFileName、$firebaseConfigAsset を更新しました',
  );
}
