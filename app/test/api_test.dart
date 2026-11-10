import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uramichi/core/api/mock_data.dart';
import 'package:uramichi/core/api/uramichi_api.dart';
import 'package:uramichi/core/geo.dart';
import 'package:uramichi/core/models/place.dart';
import 'package:uramichi/core/models/profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('API を使えない失敗の判定', () {
    test('接続できない、応答がない、JSON でない応答、API の未定義の経路、501〜504 は使えないと判定する', () {
      expect(UramichiApi.isUnavailable(http.ClientException('x')), isTrue);
      expect(UramichiApi.isUnavailable(TimeoutException('x')), isTrue);
      expect(UramichiApi.isUnavailable(const FormatException('x')), isTrue);
      expect(
        UramichiApi.isUnavailable(const ApiException(404, 'unknown', 'x')),
        isTrue,
      );
      expect(
        UramichiApi.isUnavailable(const ApiException(404, 'not_found', 'x')),
        isTrue,
      );
      for (final int status in <int>[501, 502, 503, 504]) {
        expect(
          UramichiApi.isUnavailable(ApiException(status, 'x', 'x')),
          isTrue,
        );
      }
    });

    test('API の答え（有名スポットが見つからない）とサーバーの処理の失敗（500）は、使えないと判定しない', () {
      expect(
        UramichiApi.isUnavailable(
          const ApiException(404, 'origin_not_found', 'x'),
        ),
        isFalse,
      );
      expect(
        UramichiApi.isUnavailable(const ApiException(400, 'bad_request', 'x')),
        isFalse,
      );
      expect(
        UramichiApi.isUnavailable(const ApiException(500, 'internal', 'x')),
        isFalse,
      );
    });
  });

  group('ダミーデータへの切り替え', () {
    UramichiApi api(
      http.Response Function(http.Request) handler, {
      List<Uri>? log,
    }) => UramichiApi(
      baseUrl: 'http://test',
      client: MockClient((http.Request r) async {
        log?.add(r.url);
        return handler(r);
      }),
    );

    test('API サーバーに接続できなくても、ダミーデータに切り替えずに失敗を伝える', () async {
      await expectLater(
        UramichiApi(
          baseUrl: 'http://test',
          client: MockClient(
            (http.Request r) async => throw http.ClientException('x', r.url),
          ),
        ).explore(lat: 34.693, lng: 135.19),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('有名スポットが見つからない答えは、ダミーデータに置き換えずにそのまま伝える', () async {
      final UramichiApi client = api(
        (http.Request _) => http.Response(
          jsonEncode(<String, Object>{
            'error': <String, String>{
              'code': 'origin_not_found',
              'message': '見つかりませんでした',
            },
          }),
          404,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      );
      await expectLater(
        client.alternatives('ないお寺'),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.code,
            'code',
            'origin_not_found',
          ),
        ),
      );
    });

    test('接続先のない開発用のビルドだけ、API サーバーを呼ばずにダミーデータを返す', () async {
      final List<Uri> log = <Uri>[];
      final UramichiApi client = UramichiApi(
        baseUrl: null,
        client: MockClient((http.Request r) async {
          log.add(r.url);
          return http.Response('{}', 200);
        }),
      );
      final ExploreResult r = await client.explore(lat: 34.693, lng: 135.19);
      expect(r.isMock, isTrue);
      expect(log, isEmpty);
    });
  });

  group('チェックインの候補', () {
    late Uri requested;
    late UramichiApi client;

    setUp(() {
      client = UramichiApi(
        baseUrl: 'http://test',
        client: MockClient((http.Request r) async {
          requested = r.url;
          return http.Response('{"source":"google","places":[]}', 200);
        }),
      );
    });

    test('チェックインの候補は purpose を付けて探し、未踏サーチは付けない', () async {
      await client.exploreForCheckin(lat: 34.6, lng: 135.1, radius: 300);
      expect(requested.queryParameters['purpose'], 'checkin');

      await client.explore(lat: 34.6, lng: 135.1);
      expect(requested.queryParameters.containsKey('purpose'), isFalse);
    });

    test('検索には ID トークンを付ける', () async {
      final List<String?> sent = <String?>[];
      final UramichiApi signedIn = UramichiApi(
        baseUrl: 'http://test',
        idToken: () async => 'token-1',
        client: MockClient((http.Request r) async {
          sent.add(r.headers['Authorization']);
          return http.Response(
            r.url.path == '/api/alternatives'
                ? '{"source":"google","origin":{"id":"o","name":"有名","lat":1,"lng":1,"types":[],"userRatingCount":0},"alternatives":[]}'
                : '{"source":"google","places":[]}',
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }),
      );

      await signedIn.explore(lat: 34.6, lng: 135.1);
      await signedIn.exploreForCheckin(lat: 34.6, lng: 135.1, radius: 300);
      await signedIn.alternatives('有名');

      expect(sent, List<String>.filled(3, 'Bearer token-1'));
    });

    test('通信できずにログインできないときは、未踏サーチもダミーを返さずに失敗を伝える', () async {
      final UramichiApi offline = UramichiApi(
        baseUrl: 'http://test',
        idToken: () async => throw http.ClientException('x'),
        client: MockClient(
          (http.Request r) async => throw StateError('呼ばれないはず'),
        ),
      );

      await expectLater(
        offline.explore(lat: 34.6, lng: 135.1),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('サーバーが候補を返せない 503 は例外になり、ダミーを返さない', () async {
      final UramichiApi failing = UramichiApi(
        baseUrl: 'http://test',
        client: MockClient(
          (http.Request r) async => http.Response(
            '{"error":{"code":"places_unavailable","message":"x"}}',
            503,
          ),
        ),
      );
      await expectLater(
        failing.exploreForCheckin(lat: 34.6, lng: 135.1, radius: 300),
        throwsA(
          predicate((Object? e) => e != null && UramichiApi.isUnavailable(e)),
        ),
      );
    });
  });

  group('同梱したダミーデータ', () {
    test('周辺の場所と代わりの候補が、アプリの Place として読める', () async {
      final MockData mock = MockData();
      final ExploreResult explore = await mock.explore(
        lat: 34.693,
        lng: 135.19,
        radius: 5000,
      );
      expect(explore.places, isNotEmpty);
      for (final Place p in explore.places) {
        expect(PlaceTitle.of(p.title), isNotNull, reason: p.name);
        expect(p.obscurity, isNotNull, reason: p.name);
      }

      final AlternativesResult alternatives = await mock.alternatives(
        radius: 10000,
      );
      expect(alternatives.origin.name, isNotEmpty);
      expect(alternatives.alternatives, isNotEmpty);
    });

    test('地図を動かしても、ダミーの場所は指定した地点の周りに置き直される', () async {
      final MockData mock = MockData();
      final ExploreResult home = await mock.explore(
        lat: 34.693,
        lng: 135.19,
        radius: 5000,
      );
      final ExploreResult moved = await mock.explore(
        lat: 35.0,
        lng: 135.7,
        radius: 5000,
      );

      expect(moved.places.length, home.places.length);
      for (int i = 0; i < home.places.length; i++) {
        final int before = distanceMeters(
          34.693,
          135.19,
          home.places[i].lat,
          home.places[i].lng,
        );
        final int after = distanceMeters(
          35.0,
          135.7,
          moved.places[i].lat,
          moved.places[i].lng,
        );
        expect(
          (after - before).abs(),
          lessThan(50),
          reason: home.places[i].name,
        );
      }
    });

    test('探す半径より遠いダミーの場所は返さない', () async {
      final MockData mock = MockData();
      final ExploreResult near = await mock.explore(
        lat: 34.693,
        lng: 135.19,
        radius: 300,
      );
      for (final Place p in near.places) {
        expect(
          distanceMeters(34.693, 135.19, p.lat, p.lng),
          lessThanOrEqualTo(300),
        );
      }
      final ExploreResult all = await mock.explore(
        lat: 34.693,
        lng: 135.19,
        radius: 5000,
      );
      expect(near.places.length, lessThan(all.places.length));
    });
  });

  group('プロフィール', () {
    test('保存していなければ null を返す', () async {
      final UramichiApi api = UramichiApi(
        baseUrl: 'http://test',
        client: MockClient((http.Request r) async {
          expect(r.method, 'GET');
          expect(r.url.path, '/api/me');
          expect(r.headers['Authorization'], 'Bearer tok');
          return http.Response('{"profile":null}', 200);
        }),
      );
      expect(await api.fetchProfile(idToken: 'tok'), isNull);
    });

    test('PUT で保存し、サーバーが保存した値を返す', () async {
      final UramichiApi api = UramichiApi(
        baseUrl: 'http://test',
        client: MockClient((http.Request r) async {
          expect(r.method, 'PUT');
          expect(r.url.path, '/api/me');
          expect(r.headers['Authorization'], 'Bearer tok');
          expect(jsonDecode(r.body), <String, dynamic>{
            'nickname': ' たろう ',
            'icon': 'pets',
          });
          return http.Response(
            jsonEncode(<String, Object>{
              'profile': <String, String>{'nickname': 'たろう', 'icon': 'pets'},
            }),
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }),
      );
      final Profile saved = await api.saveProfile(
        const Profile(nickname: ' たろう ', icon: 'pets'),
        idToken: 'tok',
      );
      expect(saved, const Profile(nickname: 'たろう', icon: 'pets'));
    });

    test('匿名のログインで呼ぶと login_required の例外になる', () async {
      final UramichiApi api = UramichiApi(
        baseUrl: 'http://test',
        client: MockClient(
          (http.Request r) async => http.Response(
            '{"error":{"code":"login_required","message":"Google アカウントでログインしてからやり直してください"}}',
            403,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          ),
        ),
      );
      await expectLater(
        api.fetchProfile(idToken: 'anon'),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.code,
            'code',
            'login_required',
          ),
        ),
      );
    });
  });
}
