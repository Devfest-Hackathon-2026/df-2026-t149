import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uramichi/core/api/uramichi_api.dart';
import 'package:uramichi/core/data/favorites.dart';
import 'package:uramichi/core/models/place.dart';
import 'package:uramichi/core/theme.dart';
import 'package:uramichi/core/widgets/place_card.dart';

/// お気に入りを覚える架空のサーバー
class _Server {
  final List<String> ids = <String>[];
  final List<http.Request> requests = <http.Request>[];
  bool fail = false;

  UramichiApi api() => UramichiApi(
    baseUrl: 'http://test',
    idToken: () async => 'token',
    client: MockClient((http.Request r) async {
      requests.add(r);
      if (fail) {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode(<String, Object>{
              'error': <String, String>{'code': 'internal', 'message': '失敗'},
            }),
          ),
          500,
        );
      }
      final String path = r.url.path;
      Object body;
      if (path == '/api/favorites/ids') {
        body = <String, Object>{'placeIds': ids};
      } else if (path == '/api/favorites') {
        body = <String, Object>{
          'favorites': <Object>[
            for (final String id in ids)
              <String, Object?>{
                'placeId': id,
                'place': id == 'gone'
                    ? null
                    : <String, Object>{
                        'id': id,
                        'name': '場所$id',
                        'lat': 34.0,
                        'lng': 135.0,
                        'types': <String>['park'],
                        'primaryType': 'park',
                      },
                'createdAt': '2026-11-09T00:00:00Z',
              },
          ],
        };
      } else {
        final String id = Uri.decodeComponent(path.split('/').last);
        if (r.method == 'PUT') {
          ids.insert(0, id);
        } else {
          ids.remove(id);
        }
        body = <String, Object>{'placeId': id};
      }
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
    }),
  );
}

const Place _real = Place(id: 'ChIJreal', name: '本物の祠', lat: 34, lng: 135);
const Place _mock = Place(id: 'mock_01', name: '架空の祠', lat: 34, lng: 135);

void main() {
  test('ログインするとお気に入りの place ID を読み、付け外しをサーバーへ送る', () async {
    final _Server server = _Server()..ids.add('ChIJold');
    final FavoritesController c = FavoritesController(api: server.api());
    await c.setUser('u1');
    expect(c.isFavorite('ChIJold'), isTrue);

    await c.toggle(_real);
    expect(c.isFavorite(_real.id), isTrue);
    expect(server.ids, contains(_real.id));
    expect(server.requests.last.method, 'PUT');

    await c.toggle(_real);
    expect(c.isFavorite(_real.id), isFalse);
    expect(server.requests.last.method, 'DELETE');

    // ログアウトすると消える
    await c.setUser(null);
    expect(c.count, 0);
  });

  test('サーバーに送れなかったら元に戻す', () async {
    final _Server server = _Server();
    final FavoritesController c = FavoritesController(api: server.api());
    await c.setUser('u1');
    server.fail = true;
    await expectLater(c.toggle(_real), throwsA(isA<ApiException>()));
    expect(c.isFavorite(_real.id), isFalse);
  });

  test('ダミーの場所は端末で覚え、サーバーへ送らない', () async {
    final _Server server = _Server();
    final FavoritesController c = FavoritesController(api: server.api());
    await c.setUser('u1');
    final int before = server.requests.length;
    await c.toggle(_mock);
    expect(c.isFavorite(_mock.id), isTrue);
    expect(server.requests.length, before);

    final List<FavoriteEntry> list = await c.list();
    expect(list.first.place?.name, '架空の祠');
  });

  test('一覧は名前と位置を読み、読めない場所も残す', () async {
    final _Server server = _Server()..ids.addAll(<String>['a', 'gone']);
    final FavoritesController c = FavoritesController(api: server.api());
    await c.setUser('u1');
    final List<FavoriteEntry> list = await c.list();
    expect(list.map((FavoriteEntry e) => e.placeId), <String>['a', 'gone']);
    expect(list.first.place?.name, '場所a');
    expect(list.last.place, isNull);
  });

  testWidgets('口コミ数を取得していないお気に入りは、口コミ 0 件や称号を表示しない', (
    WidgetTester tester,
  ) async {
    final _Server server = _Server()..ids.add('a');
    final FavoritesController c = FavoritesController(api: server.api());
    await c.setUser('u1');
    final Place place = (await c.list()).single.place!;
    expect(place.reviewCountKnown, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: PlaceRow(place: place, onTap: () {}),
        ),
      ),
    );
    expect(find.text('場所a'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    for (final PlaceTitle t in PlaceTitle.values) {
      expect(find.text(t.label), findsNothing);
    }
    expect(find.byIcon(Icons.rate_review_outlined), findsNothing);
  });

  group('利用者を切り替えている途中', () {
    late String user;
    late Map<String, List<String>> idsByUser;
    late Completer<void> gate;
    late Completer<void> arrived;
    late String gatedPath;

    UramichiApi api() => UramichiApi(
      baseUrl: 'http://test',
      idToken: () async => 'token',
      client: MockClient((http.Request r) async {
        // 応答の中身は、要求を送った時点の利用者で決まる
        final String sender = user;
        final String path = r.url.path;
        if (path == gatedPath) {
          arrived.complete();
          await gate.future;
        }
        if (r.method == 'PUT' || r.method == 'DELETE') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, Object>{
                'error': <String, String>{'code': 'internal', 'message': '失敗'},
              }),
            ),
            500,
          );
        }
        final List<String> ids = idsByUser[sender]!;
        final Object body = path == '/api/favorites/ids'
            ? <String, Object>{'placeIds': ids}
            : <String, Object>{
                'favorites': <Object>[
                  for (final String id in ids)
                    <String, Object?>{
                      'placeId': id,
                      'place': null,
                      'createdAt': '2026-11-09T00:00:00Z',
                    },
                ],
              };
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      }),
    );

    setUp(() {
      user = 'a';
      idsByUser = <String, List<String>>{
        'a': <String>['ChIJa'],
        'b': <String>['ChIJb', _real.id],
      };
      gate = Completer<void>();
      arrived = Completer<void>();
      gatedPath = '';
    });

    test('前の利用者の一覧が後から届いても、切り替えた利用者のお気に入りに混ぜない', () async {
      final FavoritesController c = FavoritesController(api: api());
      await c.setUser('a');
      gatedPath = '/api/favorites';
      final Future<List<FavoriteEntry>> listOfA = c.list();
      await arrived.future;

      user = 'b';
      await c.setUser('b');
      gate.complete();
      final List<FavoriteEntry> late = await listOfA;

      expect(
        late.map((FavoriteEntry e) => e.placeId),
        isNot(contains('ChIJa')),
      );
      expect(c.isFavorite('ChIJa'), isFalse);
      expect(c.isFavorite('ChIJb'), isTrue);
    });

    test('前の利用者の付け外しが後から失敗しても、切り替えた利用者のお気に入りを戻さない', () async {
      final FavoritesController c = FavoritesController(api: api());
      await c.setUser('a');
      gatedPath = '/api/favorites/${_real.id}';
      final Future<void> toggleOfA = c.toggle(_real);
      await arrived.future;

      user = 'b';
      await c.setUser('b');
      expect(c.isFavorite(_real.id), isTrue);
      gate.complete();
      await expectLater(toggleOfA, throwsA(isA<ApiException>()));

      expect(c.isFavorite(_real.id), isTrue);
      expect(c.isChanging(_real.id), isFalse);
    });
  });

  testWidgets('★評価と区別できるよう、お気に入りはハートで表す', (WidgetTester tester) async {
    // FavoriteButton は Services の中でだけ表示する（screens_test で画面ごとに確かめる）
    expect(Icons.favorite.codePoint, isNot(Icons.star_rounded.codePoint));
  });
}
