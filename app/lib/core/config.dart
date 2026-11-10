import 'dart:convert';

import 'package:flutter/services.dart';

/// アプリの設定。ビルドのときには指定せず、アプリに同梱する assets/config/app_config.json から読む。
///
/// API キーなどの秘密情報はここに書かない（地図のキーは app/.env に書く）。
class AppConfig {
  const AppConfig({
    this.apiBaseUrl,
    this.initialLat = defaultLat,
    this.initialLng = defaultLng,
  });

  static const double defaultLat = 34.6930;
  static const double defaultLng = 135.1900;
  static const String path = 'assets/config/app_config.json';

  /// 公開した API サーバー（Cloud Run）の URL。まだ公開していなければ null
  final String? apiBaseUrl;

  /// 最初に地図を表示する地点
  final double initialLat;
  final double initialLng;

  /// 設定のファイルを読む。ファイルが読めないときは、接続先のない設定として扱う
  static Future<AppConfig> load({AssetBundle? bundle}) async {
    try {
      final Map<String, dynamic> json =
          jsonDecode(
                await (bundle ?? rootBundle).loadString(path, cache: false),
              )
              as Map<String, dynamic>;
      final String url = (json['apiBaseUrl'] as String? ?? '').trim();
      return AppConfig(
        apiBaseUrl: url.isEmpty ? null : _withoutTrailingSlash(url),
        initialLat: (json['initialLat'] as num?)?.toDouble() ?? defaultLat,
        initialLng: (json['initialLng'] as num?)?.toDouble() ?? defaultLng,
      );
    } catch (_) {
      // ファイルがないときに rootBundle は Exception ではなく FlutterError を投げるため、種類を分けずに受け止める
      return const AppConfig();
    }
  }

  static String _withoutTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
