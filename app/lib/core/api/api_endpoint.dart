import 'dart:async';

import 'package:http/http.dart' as http;

/// API サーバーの接続先を決めるときの、アプリの動いている環境
enum RunEnvironment {
  /// Firebase Hosting で公開した Web 版。同じオリジンの /api を Cloud Run へ転送する
  webRelease,

  /// 開発中のビルド（flutter run）。PC で動かした API サーバーを探す
  development,

  /// 配布用のビルド（flutter build apk など）
  release,
}

/// 開発中に PC の API サーバーを探す候補。
/// エミュレータからは 10.0.2.2 が PC を指し、USB でつないだ実機からは adb reverse で localhost が PC を指す
const List<String> localServerCandidates = <String>[
  'http://10.0.2.2:8080',
  'http://localhost:8080',
];

/// API サーバーの接続先を決める。null のときは接続先がなく、アプリはダミーデータで動く。
///
/// - Web の公開版は、同じオリジン（空の文字列）を使う
/// - 開発中は、PC の API サーバーが応答すればそれを使い、なければ設定のファイルの URL を使う
/// - 配布用のビルドは、設定のファイルの URL を使う
Future<String?> resolveApiBaseUrl({
  required RunEnvironment environment,
  required String? configured,
  required Future<bool> Function(String baseUrl) isReachable,
}) async {
  switch (environment) {
    case RunEnvironment.webRelease:
      return '';
    case RunEnvironment.release:
      return configured;
    case RunEnvironment.development:
      final List<bool> reachable = await Future.wait<bool>(<Future<bool>>[
        for (final String url in localServerCandidates) isReachable(url),
      ]);
      for (int i = 0; i < localServerCandidates.length; i++) {
        if (reachable[i]) {
          return localServerCandidates[i];
        }
      }
      return configured;
  }
}

/// API サーバーの /api/health が短い時間で応答するか
Future<bool> isServerReachable(String baseUrl, {http.Client? client}) async {
  final http.Client c = client ?? http.Client();
  try {
    final http.Response res = await c
        .get(Uri.parse('$baseUrl/api/health'))
        .timeout(const Duration(milliseconds: 1500));
    return res.statusCode == 200;
  } catch (_) {
    // 接続できない、応答がない、どちらでも「使えない候補」として扱う
    return false;
  } finally {
    if (client == null) {
      c.close();
    }
  }
}
