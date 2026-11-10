import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uramichi/core/api/api_endpoint.dart';
import 'package:uramichi/core/api/uramichi_api.dart';
import 'package:uramichi/core/config.dart';

/// 文字列を assets のファイルとして返す
class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final String? text = files[key];
    if (text == null) {
      throw FlutterError('$key がありません');
    }
    return ByteData.sublistView(Uint8List.fromList(text.codeUnits));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final String? text = files[key];
    if (text == null) {
      throw FlutterError('$key がありません');
    }
    return text;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('設定のファイル', () {
    test('同梱した設定のファイルを読める', () async {
      final AppConfig config = await AppConfig.load();
      expect(config.initialLat, isNonZero);
      expect(config.initialLng, isNonZero);
    });

    test('URL を書くと接続先になり、末尾の / は外す', () async {
      final AppConfig config = await AppConfig.load(
        bundle: _Bundle(<String, String>{
          AppConfig.path: '{"apiBaseUrl": "https://api.example.test/"}',
        }),
      );
      expect(config.apiBaseUrl, 'https://api.example.test');
    });

    test('URL が空のときと、ファイルが読めないときは、接続先なしにする', () async {
      final AppConfig empty = await AppConfig.load(
        bundle: _Bundle(<String, String>{
          AppConfig.path: '{"apiBaseUrl": " "}',
        }),
      );
      expect(empty.apiBaseUrl, isNull);

      final AppConfig missing = await AppConfig.load(
        bundle: _Bundle(<String, String>{}),
      );
      expect(missing.apiBaseUrl, isNull);
      expect(missing.initialLat, AppConfig.defaultLat);
    });
  });

  group('接続先の決め方', () {
    test('Web の公開版は、同じオリジンを使う', () async {
      expect(
        await resolveApiBaseUrl(
          environment: RunEnvironment.webRelease,
          configured: 'https://api.example.test',
          isReachable: (String _) async => true,
        ),
        '',
      );
    });

    test('配布用のビルドは、PC のサーバーを探さずに設定のファイルの URL を使う', () async {
      final List<String> probed = <String>[];
      expect(
        await resolveApiBaseUrl(
          environment: RunEnvironment.release,
          configured: 'https://api.example.test',
          isReachable: (String url) async {
            probed.add(url);
            return true;
          },
        ),
        'https://api.example.test',
      );
      expect(probed, isEmpty);
    });

    test('開発中は、応答した PC のサーバーを使う', () async {
      expect(
        await resolveApiBaseUrl(
          environment: RunEnvironment.development,
          configured: 'https://api.example.test',
          isReachable: (String url) async => url == 'http://localhost:8080',
        ),
        'http://localhost:8080',
      );
      expect(
        await resolveApiBaseUrl(
          environment: RunEnvironment.development,
          configured: null,
          isReachable: (String url) async => url == 'http://10.0.2.2:8080',
        ),
        'http://10.0.2.2:8080',
      );
    });

    test('開発中に PC のサーバーが応答しなければ、設定のファイルの URL を使い、それもなければ接続先なしにする', () async {
      Future<bool> none(String _) async => false;
      expect(
        await resolveApiBaseUrl(
          environment: RunEnvironment.development,
          configured: 'https://api.example.test',
          isReachable: none,
        ),
        'https://api.example.test',
      );
      expect(
        await resolveApiBaseUrl(
          environment: RunEnvironment.development,
          configured: null,
          isReachable: none,
        ),
        isNull,
      );
    });

    test('サーバーの応答の確認は、/api/health が 200 を返したときだけ成功にする', () async {
      expect(
        await isServerReachable(
          'http://test',
          client: MockClient(
            (http.Request r) async =>
                http.Response('{}', r.url.path == '/api/health' ? 200 : 404),
          ),
        ),
        isTrue,
      );
      expect(
        await isServerReachable(
          'http://test',
          client: MockClient(
            (http.Request r) async => throw http.ClientException('x', r.url),
          ),
        ),
        isFalse,
      );
    });
  });

  test('接続先がないときは、API を呼ばずにダミーデータを返す', () async {
    final List<Uri> log = <Uri>[];
    final ExploreResult r = await UramichiApi(
      baseUrl: null,
      client: MockClient((http.Request req) async {
        log.add(req.url);
        return http.Response('{}', 200);
      }),
    ).explore(lat: 34.693, lng: 135.19);
    expect(r.isMock, isTrue);
    expect(r.places, isNotEmpty);
    expect(log, isEmpty);
  });
}
