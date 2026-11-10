import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uramichi/app.dart';
import 'package:uramichi/core/api/uramichi_api.dart';
import 'package:uramichi/core/data/api_checkin_repository.dart';
import 'package:uramichi/core/data/checkin_repository.dart';
import 'package:uramichi/core/geo.dart';
import 'package:uramichi/core/location/location_service.dart';
import 'package:uramichi/core/models/memory_log.dart';
import 'package:uramichi/core/models/timeline_entry.dart';
import 'package:uramichi/core/models/place.dart';
import 'package:uramichi/core/models/place_genre.dart';
import 'package:uramichi/core/settings.dart';
import 'package:uramichi/core/strings.dart';
import 'package:uramichi/core/widgets/stamp_celebration.dart';
import 'package:uramichi/core/widgets/mock_banner.dart';
import 'package:uramichi/core/widgets/place_card.dart';
import 'package:uramichi/core/widgets/places_map.dart';
import 'package:uramichi/features/achievements/achievement_widgets.dart';
import 'package:uramichi/features/achievements/achievements.dart';
import 'package:uramichi/features/achievements/achievements_screen.dart';
import 'package:uramichi/features/regions/region_picker.dart';
import 'package:uramichi/features/favorites/favorites_screen.dart';
import 'package:uramichi/features/place/place_detail_screen.dart';
import 'package:uramichi/core/share.dart';
import 'package:uramichi/core/widgets/screen_header.dart';
import 'package:uramichi/features/map/condition_pill.dart';
import 'package:uramichi/features/timeline/edit_log_sheet.dart';
import 'package:uramichi/features/timeline/entry_detail_sheet.dart';
import 'package:uramichi/features/checkin/checkin_celebration.dart';
import 'package:uramichi/features/assistant/assistant_sheet.dart';
import 'package:uramichi/features/alternatives/alternatives_screen.dart';
import 'package:uramichi/features/map/map_search_controller.dart';
import 'package:uramichi/features/map/map_screen.dart';
import 'package:uramichi/core/widgets/floating_tab_bar.dart';
import 'package:uramichi/core/widgets/map_zoom.dart';
import 'package:uramichi/features/map/results_panel.dart';
import 'package:uramichi/core/models/profile.dart';
import 'package:uramichi/features/timeline/timeline_screen.dart';
import 'package:uramichi/features/checkin/checkin_screen.dart';
import 'package:uramichi/features/home/home_screen.dart';
import 'package:uramichi/core/widgets/rating_summary.dart';

import 'fake_location.dart';
import 'fake_account.dart';

const LatLng _center = LatLng(34.697, 135.192);

Place _place(
  String id, {
  String title = 'hidden',
  int obscurity = 50,
  double lat = 34.697,
  double lng = 135.192,
  int hits = 0,
  int misses = 0,
  String type = 'park',
}) => Place(
  id: id,
  name: id,
  lat: lat,
  lng: lng,
  title: title,
  obscurity: obscurity,
  primaryType: type,
  types: <String>[type],
  hits: hits,
  misses: misses,
);

class _FailingCheckins extends LocalCheckinRepository {
  Object? checkinError;
  Object? saveError;

  @override
  Future<CheckinResult> checkIn(
    Place place, {
    required double lat,
    required double lng,
    DateTime? visitedAt,
  }) async {
    if (checkinError case final Object error) {
      throw error;
    }
    return super.checkIn(place, lat: lat, lng: lng, visitedAt: visitedAt);
  }

  @override
  Future<void> addLog(MemoryLog log) async {
    if (saveError case final Object error) {
      throw error;
    }
    return super.addLog(log);
  }
}

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// API サーバーの代わり。受け取ったリクエストを記録する
class _Server {
  _Server({this.places = const <Place>[]});

  List<Place> places;
  final List<http.Request> requests = <http.Request>[];

  /// PATCH /api/logs を失敗させるか
  bool failPatch = false;

  /// /api/locate の応答の source
  String locateSource = 'google';

  /// /api/locate で接続に失敗させるか
  bool failLocate = false;

  /// GET /api/logs を失敗させるか
  bool failLogs = false;

  /// /api/explore の応答の source
  String exploreSource = 'google';

  /// お気に入りの place ID（新しい順）
  final List<String> favorites = <String>[];

  /// GET /api/logs で返す自分の記録。null なら1件の記録を返す
  List<Map<String, Object>>? logs;

  Iterable<Uri> to(String path) => requests
      .where((http.Request r) => r.url.path == path)
      .map((http.Request r) => r.url);

  UramichiApi api() => UramichiApi(
    baseUrl: 'http://test',
    idToken: () async => 'token',
    client: MockClient((http.Request r) async {
      requests.add(r);
      if (r.method == 'PATCH' && failPatch) {
        return _json(<String, Object>{
          'error': <String, String>{'code': 'internal', 'message': '変更できません'},
        }, 500);
      }
      if (r.url.path == '/api/locate' && failLocate) {
        throw http.ClientException('圏外', r.url);
      }
      if (r.url.path == '/api/logs' && r.method == 'GET' && failLogs) {
        return _json(<String, Object>{
          'error': <String, String>{
            'code': 'internal',
            'message': '記録を読めませんでした',
          },
        }, 500);
      }
      if (r.url.path.startsWith('/api/timeline/') &&
          r.url.path.contains('/reactions/')) {
        final bool on = r.method == 'PUT';
        return _json(<String, Object>{
          'wantCount': on ? 4 : 3,
          'helpfulCount': 0,
          'myWant': on,
          'myHelpful': false,
        });
      }
      return switch (r.url.path) {
        '/api/alternatives' => _json(<String, Object?>{
          'source': 'google',
          'origin': _place('有名な寺', title: 'famous').toJson(),
          'alternatives': <Object>[_place('代わりの祠').toJson()],
        }),
        '/api/explore' => _json(<String, Object>{
          'source': exploreSource,
          'places': <Object>[for (final Place p in places) p.toJson()],
        }),
        '/api/locate' => _json(<String, Object>{
          'source': locateSource,
          'name': '嵐山',
          'lat': 35.01,
          'lng': 135.67,
        }),
        '/api/timeline' => _json(<String, Object>{
          'entries': <Object>[
            <String, Object>{
              'id': 'e1',
              'author': 'AB12CD',
              'authorName': 'さんぽ部',
              'authorIcon': 'pets',
              'mine': false,
              'placeId': 'p1',
              'placeName': '公開された場所',
              'verdict': 'hit',
              'comment': '良かった',
              'order': 2,
              'createdAt': '2026-11-07T00:00:00Z',
              'wantCount': 3,
            },
          ],
        }),
        '/api/logs' when r.method == 'GET' && logs != null => _json(
          <String, Object>{'logs': logs!},
        ),
        '/api/logs' when r.method == 'GET' => _json(<String, Object>{
          'logs': <Object>[
            <String, Object>{
              'id': 'lg_1',
              'placeId': 'p1',
              'placeName': '自分の場所',
              'verdict': 'miss',
              'comment': '',
              'order': 1,
              'public': false,
              'createdAt': '2026-11-07T00:00:00Z',
            },
          ],
        }),
        '/api/assistant' => _json(<String, Object?>{
          'source': 'gemini',
          'placesSource': 'google',
          'intent': 'recommend',
          'reply': '嵐山の近くでお寺を選びました',
          'center': <String, Object>{'name': '嵐山', 'lat': 35.01, 'lng': 135.67},
          'search': <String, Object>{
            'genres': <String>['worship'],
          },
          'suggestions': <Object>[
            <String, Object>{
              'place': _place('静かな寺', type: 'buddhist_temple').toJson(),
              'reason': '口コミが少ない静かなお寺です',
            },
          ],
        }),
        '/api/favorites/ids' => _json(<String, Object>{'placeIds': favorites}),
        '/api/favorites' => _json(<String, Object>{
          'favorites': <Object>[
            for (final String id in favorites)
              <String, Object?>{
                'placeId': id,
                'place': places
                    .firstWhere(
                      (Place p) => p.id == id,
                      orElse: () => _place(id),
                    )
                    .toJson(),
                'createdAt': '2026-11-09T00:00:00Z',
              },
          ],
        }),
        final String path when path.startsWith('/api/favorites/') => (() {
          final String id = Uri.decodeComponent(path.split('/').last);
          r.method == 'PUT' ? favorites.insert(0, id) : favorites.remove(id);
          return _json(<String, Object>{'placeId': id});
        })(),
        '/api/checkins' => _json(<String, Object>{'order': 1, 'isNew': true}),
        '/api/logs' => _json(<String, Object>{
          'id': 'lg_2',
          'placeId': 'p1',
          'verdict': 'hit',
          'createdAt': '2026-11-07T00:00:00Z',
        }, 201),
        _ => _json(<String, Object>{'ok': true}),
      };
    }),
  );
}

MapSearchController _controller(
  _Server server, {
  FakeLocationService? location,
  AppSettings? settings,
}) => MapSearchController(
  api: server.api(),
  location: location ?? FakeLocationService(),
  settings: settings ?? AppSettings(),
  start: _center,
);

Future<void> _pumpApp(
  WidgetTester tester,
  _Server server, {
  CheckinRepository? checkins,
  FakeLocationService? location,
  Size size = const Size(400, 900),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final UramichiApi api = server.api();
  await tester.pumpWidget(
    UramichiApp(
      account: readyAccountNow(),
      api: api,
      checkins:
          checkins ??
          ApiCheckinRepository(
            api: api,
            uid: 'u1',
            idTokenFor: (String _) async => 'token',
          ),
      location: location ?? FakeLocationService(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('探す操作の状態', () {
    test('探す前は探すボタンを示し、地図に何も出さず、サーバーを呼ばない', () {
      final _Server server = _Server(places: <Place>[_place('a')]);
      final MapSearchController c = _controller(server);

      expect(c.state, isA<SearchIdle>());
      expect(c.action, SearchAction.searchArea);
      expect(c.visiblePlaces, isEmpty);
      expect(server.requests, isEmpty);
    });

    test('探した後は探すボタンを消し、ジャンルを変えると探すまで古い結果として示す', () async {
      final _Server server = _Server(places: <Place>[_place('a')]);
      final MapSearchController c = _controller(server);

      await c.search();
      expect(c.action, SearchAction.none);
      expect(c.isStale, isFalse);

      c.toggleGenre(PlaceGenre.food);
      expect(c.action, SearchAction.applyConditions);
      expect(c.isStale, isTrue);
      expect(c.isGenrePending(PlaceGenre.food), isTrue);
      expect(c.isGenrePending(PlaceGenre.nature), isFalse);
      expect(server.to('/api/explore').length, 1);

      c.toggleGenre(PlaceGenre.food);
      expect(c.action, SearchAction.none, reason: '元の条件に戻すと古い結果ではない');

      c.toggleGenre(PlaceGenre.food);
      await c.search();
      expect(c.action, SearchAction.none);
      expect(server.to('/api/explore').last.queryParameters['genre'], 'food');
    });

    test('半径を変えると探すまで古い結果として示す', () async {
      final MapSearchController c = _controller(_Server());
      await c.search();

      c.setRadius(3000);

      expect(c.action, SearchAction.applyConditions);
      expect(c.isRadiusPending, isTrue);
    });

    test('地図を動かすと探すボタンを示す。わずかな移動では示さない', () async {
      final MapSearchController c = _controller(_Server());
      await c.search();

      c.moveTo(LatLng(c.center.latitude + 0.0001, c.center.longitude));
      expect(c.action, SearchAction.none);

      c.moveTo(LatLng(c.center.latitude + 0.01, c.center.longitude));
      expect(c.action, SearchAction.searchArea);
    });

    test('Google マップの移動中は表示が変わるときだけ通知し、最後の地点を検索に使う', () async {
      final _Server server = _Server(places: <Place>[_place('a')]);
      final MapSearchController c = _controller(server);
      await c.search();
      int notifications = 0;
      c.addListener(() => notifications++);

      c.moveTo(const LatLng(34.6971, 135.192), mapRendersMovement: true);
      expect(notifications, 0);
      c.moveTo(const LatLng(34.698, 135.192), mapRendersMovement: true);
      expect(notifications, 1);
      expect(c.isStale, isFalse);
      c.moveTo(const LatLng(34.699, 135.192), mapRendersMovement: true);
      expect(notifications, 1);
      c.moveTo(const LatLng(34.703, 135.192), mapRendersMovement: true);
      expect(notifications, 2);
      expect(c.isStale, isTrue);
      c.moveTo(const LatLng(34.699, 135.192), mapRendersMovement: true);
      expect(notifications, 3);
      expect(c.isStale, isFalse);
      await c.search();
      expect(server.to('/api/explore').last.queryParameters['lat'], '34.699');
    });

    test('簡易地図は移動するたびに描画を更新する', () async {
      final MapSearchController c = _controller(_Server());
      int notifications = 0;
      c.addListener(() => notifications++);
      c.moveTo(const LatLng(34.698, 135.192));
      c.moveTo(const LatLng(34.699, 135.192));
      expect(notifications, 2);
    });

    test('地図の移動中は並べ替えた結果を再利用し、称号と順序の変更を反映する', () async {
      final _Server server = _Server(
        places: <Place>[
          _place('hidden', title: 'hidden', obscurity: 40),
          _place('famous', title: 'famous', obscurity: 90),
        ],
      );
      final MapSearchController c = _controller(server);
      await c.search();
      final List<Place> initial = c.visiblePlaces;
      c.moveTo(const LatLng(34.699, 135.192));
      expect(identical(c.visiblePlaces, initial), isTrue);

      c.toggleTitle(PlaceTitle.famous);
      expect(c.visiblePlaces.map((Place p) => p.id), <String>[
        'famous',
        'hidden',
      ]);
      expect(identical(c.visiblePlaces, initial), isFalse);
      server.places = <Place>[_place('new')];
      await c.search();
      expect(c.visiblePlaces.single.id, 'new');
    });

    test('称号と並べ替えはサーバーを呼ばず、すぐに反映する', () async {
      final _Server server = _Server(
        places: <Place>[
          _place('hidden', title: 'hidden'),
          _place('famous', title: 'famous'),
        ],
      );
      final MapSearchController c = _controller(server);
      await c.search();

      expect(c.visiblePlaces.map((Place p) => p.id), <String>['hidden']);
      c.toggleTitle(PlaceTitle.famous);
      expect(c.visiblePlaces.length, 2);
      expect(c.isStale, isFalse);
      expect(server.to('/api/explore').length, 1);
    });

    test('並べ替えは穴場で近い順、知られていない順、近い順で変わる', () async {
      final _Server server = _Server(
        places: <Place>[
          _place('far-unknown', obscurity: 100, lat: 34.697 + 0.012),
          _place('near-known', obscurity: 40),
          _place('near-unknown', obscurity: 90, lat: 34.697 + 0.001),
        ],
      );
      final MapSearchController c = _controller(server);
      await c.start();
      await c.search();

      List<String> ids() => c.visiblePlaces.map((Place p) => p.id).toList();
      expect(ids().first, 'near-unknown');
      c.setSort(ResultSort.obscure);
      expect(ids().first, 'far-unknown');
      c.setSort(ResultSort.near);
      expect(ids().first, 'near-known');
    });
  });

  group('現在地と下調べ', () {
    test('許可されると現在地へ移動する', () async {
      final FakeLocationService location = FakeLocationService()
        ..position = GeoSample(
          lat: 35,
          lng: 136,
          accuracyMeters: 5,
          at: DateTime(2026),
        );
      final MapSearchController c = _controller(_Server(), location: location);

      await c.start();

      expect(c.center, const LatLng(35, 136));
      expect(c.userLocation, const LatLng(35, 136));
      expect(location.lastAsk, isTrue);
    });

    test('許可されないと前回の地点のまま使え、現在地は持たない', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'lastMapLat': 43.0,
        'lastMapLng': 141.0,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final MapSearchController c = _controller(
        _Server(),
        location: FakeLocationService()..access = LocationAccess.denied,
        settings: AppSettings.load(prefs),
      );

      await c.start();

      expect(c.center, const LatLng(43, 141));
      expect(c.userLocation, isNull);
    });

    test('検索欄の地点へ移動するが、探すのは利用者の操作を待つ', () async {
      final _Server server = _Server();
      final MapSearchController c = _controller(server);

      await c.jumpTo('嵐山');

      expect(c.center, const LatLng(35.01, 135.67));
      expect(c.state, isA<SearchIdle>());
      expect(server.to('/api/explore'), isEmpty);
    });

    test('距離は近くなら現在地から、遠い地点の下調べなら探した地点から測る', () async {
      final _Server server = _Server(
        places: <Place>[_place('a', lat: 35.01, lng: 135.67)],
      );
      final MapSearchController c = _controller(server);
      await c.start();

      await c.jumpTo('嵐山');
      await c.search();

      expect(c.distanceTo(c.visiblePlaces.single), 0);

      c.moveTo(_center);
      await c.search();
      expect(c.distanceTo(c.visiblePlaces.single), greaterThan(10000));
    });
  });

  group('地点の検索の失敗とダミー', () {
    test('通信できないときはダミーの地点へ移動せず、失敗を伝える', () async {
      final _Server server = _Server()..failLocate = true;
      final MapSearchController c = _controller(server);
      final LatLng before = c.center;

      await expectLater(c.jumpTo('東京'), throwsA(isA<http.ClientException>()));

      expect(c.center, before);
      expect(c.searchedPlaceName, isNull);
    });

    test('サーバーがダミーの地点を返したら、ダミーであることを返す', () async {
      final MapSearchController c = _controller(
        _Server()..locateSource = 'mock',
      );

      expect(await c.jumpTo('東京'), isTrue);
    });

    test('本物の地点なら、ダミーとして扱わない', () async {
      expect(await _controller(_Server()).jumpTo('嵐山'), isFalse);
    });

    testWidgets('ダミーの地点へ移動したら画面で伝える', (WidgetTester tester) async {
      await _pumpApp(tester, _Server()..locateSource = 'mock');

      await tester.enterText(find.byType(TextField), '東京');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.textContaining('ダミー'), findsWidgets);
    });

    testWidgets('通信できないときは画面で伝える', (WidgetTester tester) async {
      await _pumpApp(tester, _Server()..failLocate = true);

      await tester.enterText(find.byType(TextField), '東京');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('代わりに行くならここへの入口', () {
    testWidgets('検索した地点から代わりを探せる。タブは増やさない', (WidgetTester tester) async {
      final _Server server = _Server();
      await _pumpApp(tester, server);
      expect(find.text('代わりを探す'), findsNothing);

      await tester.enterText(find.byType(TextField), '清水寺');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('「清水寺」の代わりを探す'));
      await tester.pumpAndSettle();

      expect(find.byType(AlternativesScreen), findsOneWidget);
      expect(server.to('/api/alternatives').single.queryParameters['q'], '清水寺');
      expect(find.text('代わりの祠'), findsWidgets);
      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    test('地図を動かすと、検索した地点の名前を取り消す', () async {
      final MapSearchController c = _controller(_Server());
      await c.jumpTo('清水寺');
      expect(c.searchedPlaceName, '嵐山');
      expect(c.searchedQuery, '清水寺');

      c.moveTo(const LatLng(35.1, 135.67));

      expect(c.searchedPlaceName, isNull);
      expect(c.searchedQuery, isNull);
    });
  });

  group('距離の基準の表示', () {
    testWidgets('現在地の近くでは現在地から、遠い地点では探した地点からと示す', (WidgetTester tester) async {
      await _pumpApp(tester, _Server(places: <Place>[_place('穴場の祠')]));
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ConditionPill, '現在地の近く'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '嵐山');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ConditionPill, '嵐山'), findsOneWidget);
      expect(find.widgetWithText(ConditionPill, '現在地の近く'), findsNothing);
    });
  });

  group('ジャンル', () {
    test('その他は、ほかのジャンルに入らない場所だけに当たる', () {
      final Place cafe = _place('cafe', type: 'cafe');
      final Place hotel = _place('hotel', type: 'lodging');
      expect(PlaceGenre.matches(cafe, <PlaceGenre>{PlaceGenre.food}), isTrue);
      expect(PlaceGenre.matches(hotel, <PlaceGenre>{PlaceGenre.food}), isFalse);
      expect(PlaceGenre.matches(hotel, <PlaceGenre>{PlaceGenre.other}), isTrue);
      expect(PlaceGenre.matches(cafe, <PlaceGenre>{PlaceGenre.other}), isFalse);
      expect(
        PlaceGenre.matches(cafe, <PlaceGenre>{
          PlaceGenre.other,
          PlaceGenre.food,
        }),
        isTrue,
      );
      expect(PlaceGenre.matches(cafe, const <PlaceGenre>{}), isTrue);
    });
  });

  group('お気に入り', () {
    testWidgets('一覧のハートでお気に入りに入れ、お気に入りの画面から詳細を開ける', (
      WidgetTester tester,
    ) async {
      final _Server server = _Server(places: <Place>[_place('穴場の祠')]);
      await _pumpApp(tester, server);
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(l10n.favoriteAddTooltip).first);
      await tester.pumpAndSettle();
      expect(server.favorites, contains('穴場の祠'));
      expect(find.text(l10n.favoriteAddedNamed('穴場の祠')), findsOneWidget);
      expect(find.byTooltip(l10n.favoriteRemoveTooltip), findsWidgets);

      // お気に入りの一覧はタイムラインのタブにある
      await tester.tap(find.bySemanticsLabel('タイムライン'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.favorites));
      await tester.pumpAndSettle();
      expect(find.byType(FavoritesList), findsOneWidget);
      await tester.tap(find.text('穴場の祠'));
      await tester.pumpAndSettle();
      expect(find.byType(PlaceDetailScreen), findsOneWidget);

      // 最後の1件を外して戻ると、空の一覧ではなく、お気に入りの入れ方の案内を出す
      await tester.tap(find.byTooltip(l10n.favoriteRemoveTooltip));
      await tester.pumpAndSettle();
      expect(server.favorites, isNot(contains('穴場の祠')));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(l10n.noFavoritesYet), findsOneWidget);
    });
  });

  group('遠くを調べる', () {
    testWidgets('次の旅の候補の地域を選ぶと、その地域を広い範囲で探す', (WidgetTester tester) async {
      final _Server server = _Server();
      await _pumpApp(tester, server);

      await tester.tap(find.text('遠くを調べる'));
      await tester.pumpAndSettle();
      expect(find.byType(RegionPickerSheet), findsOneWidget);
      expect(find.text('東京に行ったことがあるなら'), findsOneWidget);
      // ほかの地域と比べて下げる言い方はしない
      expect(find.textContaining('より'), findsNothing);
      expect(find.textContaining('がいいよ'), findsNothing);

      await tester.tap(find.text('長野県・松本・安曇野').first);
      await tester.pumpAndSettle();
      final Uri last = server.to('/api/explore').last;
      expect(last.queryParameters['radius'], '20000');
      expect(
        double.parse(last.queryParameters['lat']!),
        closeTo(36.238, 0.001),
      );
      // 選んだ地域の名前を見せ、近くを探すに戻せる
      final Finder area = find.widgetWithText(ConditionPill, '長野県・松本・安曇野');
      expect(area, findsOneWidget);

      await tester.tap(area);
      await tester.pumpAndSettle();
      await tester.tap(find.text('近くを探す'));
      await tester.pumpAndSettle();
      expect(server.to('/api/explore').last.queryParameters['radius'], '1500');
    });

    testWidgets('地名で調べると、その地点へ移動して広い範囲で探す', (WidgetTester tester) async {
      final _Server server = _Server();
      await _pumpApp(tester, server);

      await tester.tap(find.text('遠くを調べる'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(RegionPickerSheet),
          matching: find.byType(TextField),
        ),
        '嵐山',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(server.to('/api/locate').last.queryParameters['q'], '嵐山');
      expect(server.to('/api/explore').last.queryParameters['radius'], '20000');
    });
  });

  group('地図の画面', () {
    testWidgets('探した後も、同じ場所で探し直せる', (WidgetTester tester) async {
      final _Server server = _Server(places: <Place>[_place('穴場の祠')]);
      await _pumpApp(tester, server);
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();
      expect(server.to('/api/explore').length, 1);

      await tester.tap(find.text(l10n.searchAgain).first);
      await tester.pumpAndSettle();
      expect(server.to('/api/explore').length, 2);
    });

    testWidgets('地図を動かすと探すボタンを出し、大きく動かすと前の場所の結果だと伝える', (
      WidgetTester tester,
    ) async {
      final _Server server = _Server(places: <Place>[_place('穴場の祠')]);
      await _pumpApp(tester, server);
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();
      final MapSearchController controller = tester
          .widget<MapScreen>(find.byType(MapScreen))
          .controller;

      controller.moveTo(const LatLng(34.698, 135.192));
      await tester.pumpAndSettle();
      expect(find.text('このエリアを探す'), findsOneWidget);
      expect(find.byKey(ResultsPanel.staleKey), findsNothing);

      // 500 m より動かすと、薄くせずに前の場所の結果だと文で伝え、探し直せる
      controller.moveTo(const LatLng(34.703, 135.192));
      await tester.pumpAndSettle();
      expect(find.text(l10n.staleMoved), findsOneWidget);
      await tester.tap(find.text(l10n.searchAgain));
      await tester.pumpAndSettle();
      expect(server.to('/api/explore').length, 2);
      expect(find.byKey(ResultsPanel.staleKey), findsNothing);
    });

    testWidgets('結果のシートを引き上げても、検索欄とボタンに重ならない', (WidgetTester tester) async {
      final _Server server = _Server(
        places: <Place>[for (int i = 0; i < 12; i++) _place('場所$i')],
      );
      await _pumpApp(tester, server);
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();

      // シートをいちばん上まで引き上げる
      await tester.drag(find.byType(ResultsPanel), const Offset(0, -2000));
      await tester.pumpAndSettle();

      final double sheetTop = tester.getTopLeft(find.byType(ResultsPanel)).dy;
      final double controlsBottom = <Finder>[
        find.byType(TextField).first,
        find.text(PlaceGenre.food.label),
      ].map((Finder f) => tester.getBottomLeft(f).dy).reduce(math.max);
      expect(sheetTop, greaterThanOrEqualTo(controlsBottom));
      // 右下のボタンは、場所が足りなければ隠し、シートに重ねない
      for (final Finder f in <Finder>[
        find.byTooltip('Geminiちゃん'),
        find.byType(ZoomLever),
      ]) {
        if (f.evaluate().isNotEmpty) {
          expect(tester.getBottomLeft(f).dy, lessThanOrEqualTo(sheetTop));
        }
      }
      // 上の操作は押せる
      await tester.tap(find.text(PlaceGenre.food.label));
      await tester.pumpAndSettle();
      final MapSearchController c = tester
          .widget<MapScreen>(find.byType(MapScreen))
          .controller;
      expect(c.genres, contains(PlaceGenre.food));
    });

    testWidgets('結果のシートを引いても、地図は作り直さない', (WidgetTester tester) async {
      final _Server server = _Server(
        places: <Place>[for (int i = 0; i < 12; i++) _place('場所$i')],
      );
      await _pumpApp(tester, server);
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();
      final PlacesMap before = tester.widget(find.byType(PlacesMap).first);

      await tester.drag(find.byType(ResultsPanel), const Offset(0, -120));
      await tester.pumpAndSettle();

      expect(
        identical(tester.widget(find.byType(PlacesMap).first), before),
        isTrue,
      );
    });

    testWidgets('チェックイン・タイムライン・実績のタブには見出しがある', (WidgetTester tester) async {
      await _pumpApp(tester, _Server());
      for (final String tab in <String>['チェックイン', 'タイムライン', '実績']) {
        await tester.tap(find.bySemanticsLabel(tab));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(ScreenHeader),
            matching: find.text(tab),
          ),
          findsOneWidget,
          reason: tab,
        );
      }
    });

    testWidgets('地図に拡大・縮小のボタンがあり、半径を変えると円が収まる拡大率に戻る', (
      WidgetTester tester,
    ) async {
      final _Server server = _Server();
      await _pumpApp(tester, server);
      expect(find.byType(ZoomLever), findsOneWidget);
      final MapSearchController c = tester
          .widget<MapScreen>(find.byType(MapScreen))
          .controller;
      final double before = c.zoom.zoom;
      await tester.tap(find.byTooltip('拡大'));
      await tester.pumpAndSettle();
      // 1段ずつ動かすときは、段の切れ目にそろえる
      expect(c.zoom.zoom, before.floorToDouble() + 1);

      c.setRadius(20000);
      await tester.pumpAndSettle();
      expect(c.zoom.zoom, lessThan(before));
    });

    testWidgets('並び順は文字で見せ、説明付きの一覧から選ぶ', (WidgetTester tester) async {
      final _Server server = _Server(places: <Place>[_place('穴場の祠')]);
      await _pumpApp(tester, server);
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();
      final MapSearchController c = tester
          .widget<MapScreen>(find.byType(MapScreen))
          .controller;

      final Finder sort = find.widgetWithText(ConditionPill, 'おすすめ順');
      await tester.ensureVisible(sort);
      await tester.pumpAndSettle();
      await tester.tap(sort);
      await tester.pumpAndSettle();
      expect(find.text('口コミの少ない、知られていない場所から'), findsOneWidget);
      await tester.tap(find.text('近い順'));
      await tester.pumpAndSettle();
      expect(c.sort, ResultSort.near);
      expect(find.widgetWithText(ConditionPill, '近い順'), findsOneWidget);
    });

    testWidgets('一覧をお気に入りだけに絞れる', (WidgetTester tester) async {
      final _Server server = _Server(
        places: <Place>[_place('穴場の祠'), _place('静かな公園')],
      )..favorites.add('静かな公園');
      await _pumpApp(tester, server);
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();
      final MapSearchController c = tester
          .widget<MapScreen>(find.byType(MapScreen))
          .controller;
      expect(c.visiblePlaces, hasLength(2));

      final Finder chip = find.widgetWithText(ConditionPill, 'お気に入り');
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(c.visiblePlaces.map((Place p) => p.id), <String>['静かな公園']);
    });

    testWidgets('チェックインのタブは地図を持たず、いまの場所の押してスタンプを出す', (
      WidgetTester tester,
    ) async {
      final _Server server = _Server(places: <Place>[_place('近くの場所')]);
      await _pumpApp(tester, server);
      await tester.tap(find.bySemanticsLabel('チェックイン'));
      await tester.pumpAndSettle();
      // 地図は地図のタブの1つだけ。チェックインのタブは「探す」ではなく「押す」ページにする
      expect(find.byType(PlacesMap, skipOffstage: false), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('here-stamp')), findsOneWidget);
      expect(find.text('今日の旅'), findsOneWidget);
    });

    testWidgets('現在地のそばの場所を探すと、地図でも押してスタンプでチェックインできる', (
      WidgetTester tester,
    ) async {
      final _Server server = _Server(places: <Place>[_place('そばの祠')]);
      await _pumpApp(tester, server);
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();

      final Finder here = find.byKey(const ValueKey<String>('map-here-stamp'));
      expect(here, findsOneWidget);
      expect(find.text('いま「そばの祠」の近くにいます'), findsOneWidget);
      await tester.tap(find.descendant(of: here, matching: find.text('押す')));
      await tester.pumpAndSettle();
      expect(find.byType(CheckinScreen), findsOneWidget);
    });

    testWidgets('現在地から遠い場所だけなら、地図に押してスタンプを出さない', (WidgetTester tester) async {
      final _Server server = _Server(
        places: <Place>[_place('遠くの祠', lat: 34.72)],
      );
      await _pumpApp(tester, server);
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('map-here-stamp')),
        findsNothing,
      );
    });

    testWidgets('開いていないタブは思い出ログを読み込まない', (WidgetTester tester) async {
      final _Server server = _Server();
      await _pumpApp(tester, server);
      expect(server.to('/api/logs'), isEmpty);

      await tester.tap(find.bySemanticsLabel('タイムライン'));
      await tester.pumpAndSettle();
      expect(server.to('/api/logs').length, 1);

      await tester.tap(find.bySemanticsLabel('実績'));
      await tester.pumpAndSettle();
      expect(server.to('/api/logs').length, 2);
    });
    testWidgets('起動すると結果を出さず、ボタンを押すと探す', (WidgetTester tester) async {
      final _Server server = _Server(places: <Place>[_place('穴場の祠')]);
      await _pumpApp(tester, server);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('穴場の祠'), findsNothing);
      expect(server.to('/api/explore'), isEmpty);

      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();

      expect(find.text('穴場の祠'), findsWidgets);
      expect(find.text('このエリアを探す'), findsNothing);
    });

    testWidgets('ジャンルを変えると前の条件の結果だと伝え、この条件で探すを押すまで探さない', (
      WidgetTester tester,
    ) async {
      final _Server server = _Server(places: <Place>[_place('穴場の祠')]);
      await _pumpApp(tester, server);
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();

      expect(find.byKey(ResultsPanel.staleKey), findsNothing);

      await tester.tap(find.text('飲食'));
      await tester.pumpAndSettle();

      expect(find.text('この条件で探す'), findsOneWidget);
      // 結果は薄くせず、前の条件の結果だと文で伝える
      expect(find.byKey(ResultsPanel.staleKey), findsOneWidget);
      expect(find.text(l10n.staleConditions), findsOneWidget);
      expect(server.to('/api/explore').length, 1);

      await tester.tap(find.text('この条件で探す'));
      await tester.pumpAndSettle();

      expect(server.to('/api/explore').last.queryParameters['genre'], 'food');
      expect(find.text('この条件で探す'), findsNothing);
      expect(find.byKey(ResultsPanel.staleKey), findsNothing);
    });

    testWidgets('探した後も検索欄の文字を残す', (WidgetTester tester) async {
      await _pumpApp(tester, _Server(places: <Place>[_place('穴場の祠')]));
      await tester.enterText(find.byType(TextField), '嵐山');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '嵐山'), findsOneWidget);
    });

    testWidgets('★評価の前の当たりとハズレの数は、★で表示し、ハズレの数は見せない', (
      WidgetTester tester,
    ) async {
      final _Server server = _Server(
        places: <Place>[_place('穴場の祠', hits: 8, misses: 2)],
      );
      await _pumpApp(tester, server);
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();

      final RatingSummary summary = tester.widget(find.byType(RatingSummary));
      expect(summary.stars, closeTo(3.6, 0.001)); // 当たり8件を★4、ハズレ2件を★2として数える
      expect(summary.count, 10);
      expect(find.byIcon(Icons.thumb_down_outlined), findsNothing);
    });

    testWidgets('人気度で全て隠れたときは、有名な場所も見る操作を示す', (WidgetTester tester) async {
      final _Server server = _Server(
        places: <Place>[_place('有名な寺', title: 'famous')],
      );
      await _pumpApp(tester, server);
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();
      expect(
        server.to('/api/explore').last.queryParameters['popularity'],
        '0,1',
      );

      await tester.ensureVisible(find.text('有名な場所も見る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('有名な場所も見る'));
      await tester.pumpAndSettle();

      expect(find.byType(PlaceRow), findsOneWidget);
      // 有名な場所は人気順でも探すため、幅を広げて探し直す
      expect(
        server.to('/api/explore').last.queryParameters['popularity'],
        '0,3',
      );
    });

    testWidgets('人気度のスライダーで有名な場所まで広げると、探し直しを促す', (WidgetTester tester) async {
      final _Server server = _Server(
        places: <Place>[
          _place('祠', title: 'untrodden'),
          _place('有名な寺', title: 'famous'),
        ],
      );
      await _pumpApp(tester, server);
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();
      // 人気度は絞り込みのチップに今の幅を見せ、押すとスライダーを出す
      final Finder chip = find.widgetWithText(ConditionPill, '人気度：未踏〜穴場');
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byType(PopularitySlider), findsOneWidget);
      expect(find.text('未踏〜穴場'), findsOneWidget);
      final int calls = server.to('/api/explore').length;

      final MapSearchController c = tester
          .widget<PopularitySlider>(find.byType(PopularitySlider))
          .controller;
      c.setPopularity(0, 3);
      await tester.pumpAndSettle();
      expect(find.text('未踏〜超有名'), findsOneWidget);
      expect(find.text(l10n.appliedOnSearch), findsOneWidget);
      expect(c.action, SearchAction.applyConditions);
      // 手元の結果はすぐに絞り込み直す
      expect(c.visiblePlaces, hasLength(2));
      expect(server.to('/api/explore').length, calls);

      // 狭めるだけなら探し直さない
      c.setPopularity(0, 0);
      await tester.pumpAndSettle();
      expect(c.action, SearchAction.none);
      expect(c.visiblePlaces.single.name, '祠');
    });

    testWidgets('タブはアイコンだけで、項目名を文字で表示しない', (WidgetTester tester) async {
      await _pumpApp(tester, _Server());

      expect(find.text('地図'), findsNothing);
      expect(find.text('タイムライン'), findsNothing);
      expect(find.bySemanticsLabel('タイムライン'), findsOneWidget);
    });

    testWidgets('広い画面では左の列でタブを切り替え、下のタブを出さない', (WidgetTester tester) async {
      await _pumpApp(tester, _Server(), size: const Size(1280, 800));

      expect(find.byType(FloatingTabRail), findsOneWidget);
      expect(find.byType(FloatingTabBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ダークテーマでも折りたたんだタブがはみ出さない', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _pumpApp(tester, _Server(), size: const Size(1280, 720));
      expect(tester.takeException(), isNull);
    });

    testWidgets('画面幅を変えても検索結果の開閉を続けられる', (tester) async {
      await _pumpApp(
        tester,
        _Server(places: <Place>[_place('穴場の祠')]),
        size: const Size(1280, 800),
      );
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(400, 800) * 3;
      await tester.pumpAndSettle();
      expect(find.byType(FloatingTabBar), findsOneWidget);
      tester.view.physicalSize = const Size(1280, 800) * 3;
      await tester.pumpAndSettle();
      expect(find.byType(FloatingTabRail), findsOneWidget);
      expect(find.byTooltip(l10n.collapseList), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('高さの低い広い画面でもタブがはみ出さない', (tester) async {
      await _pumpApp(tester, _Server(), size: const Size(800, 320));
      expect(tester.takeException(), isNull);
    });

    testWidgets('文字を大きくしても縦のタブを操作できる', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpApp(tester, _Server(), size: const Size(768, 1024));
      await tester.tap(find.bySemanticsLabel('タイムライン'));
      await tester.pumpAndSettle();
      expect(find.byType(TimelineScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('タブレットのシステムバーを避け、タブと検索結果が隙間なく揃う', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 72, bottom: 60);
      tester.view.viewPadding = const FakeViewPadding(top: 72, bottom: 60);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpApp(
        tester,
        _Server(places: <Place>[_place('穴場の祠')]),
        size: const Size(1000, 625),
      );

      final Finder rail = find.byType(FloatingTabRail);
      final List<double> closedCenters =
          <String>['地図', 'チェックイン', 'タイムライン', '実績']
              .map(
                (label) => tester
                    .getCenter(
                      find.descendant(of: rail, matching: find.text(label)),
                    )
                    .dy,
              )
              .toList();
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();

      final Rect railRect = tester.getRect(rail);
      final Rect surfaceRect = tester.getRect(
        find.byKey(const ValueKey<String>('wide-tab-surface')),
      );
      final Rect searchRect = tester.getRect(find.byType(TextField).first);
      // タブと結果パネルは、システムバーを避けた1枚の面になる
      expect(surfaceRect.left, closeTo(railRect.left, 1));
      // FakeViewPadding は物理ピクセルなので、論理ピクセルでは 3 で割った値になる
      expect(surfaceRect.top, closeTo(72 / 3 + 12, 1));
      expect(surfaceRect.bottom, closeTo(625 - 60 / 3 - 12, 1));
      expect(searchRect.top, greaterThanOrEqualTo(surfaceRect.top));
      // 検索欄は左右ともパネルの部分の縁から離れ、一覧の行と左右の端がそろう
      expect(searchRect.left - railRect.right, greaterThanOrEqualTo(16));
      expect(surfaceRect.right - searchRect.right, greaterThanOrEqualTo(16));
      for (int i = 0; i < closedCenters.length; i++) {
        final label = <String>['地図', 'チェックイン', 'タイムライン', '実績'][i];
        expect(
          tester
              .getCenter(find.descendant(of: rail, matching: find.text(label)))
              .dy,
          closeTo(closedCenters[i], 1),
        );
      }
      final Rect labelRect = tester.getRect(
        find.descendant(of: rail, matching: find.text('チェックイン')),
      );
      expect(labelRect.left - railRect.left, greaterThanOrEqualTo(12));
      expect(railRect.right - labelRect.right, greaterThanOrEqualTo(12));
      expect(tester.takeException(), isNull);
    });

    testWidgets('タブレットの縦向きの幅でも、左に浮かせたタブに項目名と設定のボタンを出す', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, _Server(), size: const Size(768, 1024));

      final Finder rail = find.byType(FloatingTabRail);
      expect(rail, findsOneWidget);
      for (final String label in <String>['地図', 'チェックイン', 'タイムライン', '実績']) {
        expect(
          find.descendant(of: rail, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: rail, matching: find.byTooltip('設定')),
        findsOneWidget,
      );
      // 地図はタブの後ろまで全面に表示し、タブは画面の左端の中央に浮かせる
      final Rect railRect = tester.getRect(rail);
      expect(tester.getRect(find.byType(MapScreen)).left, 0);
      expect(railRect.left, greaterThan(0));
      expect(railRect.center.dy, closeTo(1024 / 2, 1));
      for (final String label in <String>['チェックイン', 'タイムライン']) {
        final Rect labelRect = tester.getRect(
          find.descendant(of: rail, matching: find.text(label)),
        );
        expect(labelRect.left - railRect.left, greaterThanOrEqualTo(8));
        expect(railRect.right - labelRect.right, greaterThanOrEqualTo(8));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('広い画面では、探す前は地図を全幅で見せ、探した後だけ左に結果のパネルを出す', (
      WidgetTester tester,
    ) async {
      await _pumpApp(
        tester,
        _Server(places: <Place>[_place('穴場の祠')]),
        size: const Size(1280, 800),
      );
      final Finder surface = find.byKey(
        const ValueKey<String>('wide-tab-surface'),
      );
      final Finder rail = find.byType(FloatingTabRail);
      bool panelShown() =>
          tester.getSize(surface).width > tester.getSize(rail).width + 1;
      double labelY(String label) => tester
          .getCenter(find.descendant(of: rail, matching: find.text(label)))
          .dy;
      const List<String> labels = <String>['地図', 'チェックイン', 'タイムライン', '実績'];

      // 地図では、タブは面を描かず、地図の画面がタブと同じ位置に面を1枚だけ描く
      expect(panelShown(), isFalse);
      expect(tester.widget<FloatingTabRail>(rail).showSurface, isFalse);
      final Rect closedSurface = tester.getRect(surface);
      final Rect railRect = tester.getRect(rail);
      expect(closedSurface.left, closeTo(railRect.left, 1));
      expect(closedSurface.top, closeTo(railRect.top, 1));
      expect(closedSurface.bottom, closeTo(railRect.bottom, 1));
      final List<double> labelYs = labels.map(labelY).toList();

      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();
      expect(panelShown(), isTrue);
      expect(find.text('穴場の祠'), findsWidgets);
      final Rect openSurface = tester.getRect(surface);
      expect(openSurface.left, closeTo(railRect.left, 1));
      expect(openSurface.height, greaterThan(closedSurface.height));
      expect(openSurface.center.dy, closeTo(400, 1));
      // 面が広がっても、タブのボタンは動かない
      for (int i = 0; i < labels.length; i++) {
        expect(labelY(labels[i]), closeTo(labelYs[i], 1));
      }
      expect(
        tester.getSize(find.byTooltip(l10n.collapseList)).width,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getRect(find.byTooltip(l10n.collapseList)).left,
        closeTo(openSurface.right, 1),
      );

      // 畳む途中も1枚の面のまま、左端と上下の中心を保って縮む
      await tester.tap(find.byTooltip('一覧を畳む'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final Rect moving = tester.getRect(surface);
      expect(moving.left, closeTo(railRect.left, 1));
      expect(moving.center.dy, closeTo(400, 1));
      expect(moving.height, lessThan(openSurface.height));
      expect(moving.height, greaterThan(closedSurface.height));
      expect(moving.width, lessThan(openSurface.width));
      expect(moving.width, greaterThan(closedSurface.width));
      expect(labelY('チェックイン'), closeTo(labelYs[1], 1));
      await tester.pumpAndSettle();
      expect(panelShown(), isFalse);
      expect(tester.getRect(surface), rectMoreOrLessEquals(closedSurface));
      await tester.tap(find.byTooltip('一覧を開く'));
      await tester.pumpAndSettle();
      expect(panelShown(), isTrue);

      // 検索を消すと、探す前の状態に戻る
      await tester.tap(find.byTooltip('検索を消す'));
      await tester.pumpAndSettle();
      expect(panelShown(), isFalse);
      expect(find.text('このエリアを探す'), findsOneWidget);

      // 地図以外のタブでは、タブが自分の面を描く
      await tester.tap(find.bySemanticsLabel('タイムライン'));
      await tester.pumpAndSettle();
      expect(tester.widget<FloatingTabRail>(rail).showSurface, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('狭い画面でも探した結果があふれない', (WidgetTester tester) async {
      await _pumpApp(
        tester,
        _Server(places: <Place>[_place('穴場の祠')]),
        size: const Size(320, 640),
      );
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('チェックイン', () {
    Future<void> openCheckin(
      WidgetTester tester,
      _FailingCheckins checkins,
    ) async {
      await _pumpApp(tester, _Server(), checkins: checkins);
      Navigator.of(tester.element(find.byType(HomeScreen))).push(
        MaterialPageRoute<void>(
          builder: (_) => const CheckinScreen(
            place: Place(id: 'p1', name: '祠', lat: 34, lng: 135),
            lat: 34,
            lng: 135,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('チェックイン失敗時は案内を表示し、再試行できる', (tester) async {
      final checkins = _FailingCheckins()
        ..checkinError = const ApiException(400, 'too_far', 'この場所から離れています');
      await openCheckin(tester, checkins);
      expect(find.text('この場所から離れています'), findsOneWidget);
      checkins.checkinError = null;
      await tester.tap(find.text(l10n.retry));
      await tester.pumpAndSettle();
      expect(find.text(l10n.record), findsOneWidget);
    });

    testWidgets('保存失敗時は例外の詳細を表示せず、入力を保って再試行できる', (tester) async {
      final checkins = _FailingCheckins()
        ..saveError = StateError('internal details');
      await openCheckin(tester, checkins);
      await tester.tap(find.bySemanticsLabel('★2、まあまあ'));
      await tester.enterText(find.byType(TextField).last, '思い出');
      await tester.tap(find.text(l10n.record));
      await tester.pump();
      expect(find.text(l10n.errorGeneric), findsOneWidget);
      expect(find.textContaining('internal details'), findsNothing);
      expect(find.text('思い出'), findsOneWidget);
      checkins.saveError = null;
      await tester.tap(find.text(l10n.record));
      await tester.pumpAndSettle();
      expect(find.byType(CheckinCelebrationScreen), findsOneWidget);
    });

    testWidgets('端末に保存できない場合は保存失敗を伝える', (tester) async {
      final checkins = _FailingCheckins()
        ..checkinError = const LocalSaveException();
      await openCheckin(tester, checkins);
      expect(find.text(l10n.errorSaveLocal), findsOneWidget);
    });

    testWidgets('評価を選ぶまで残せず、既定は自分だけで、公開を選ぶとサーバーへ送る', (
      WidgetTester tester,
    ) async {
      final _Server server = _Server();
      final UramichiApi api = server.api();
      tester.view.physicalSize = const Size(1200, 2700);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UramichiApp(
          account: readyAccountNow(),
          api: api,
          checkins: ApiCheckinRepository(
            api: api,
            uid: 'u1',
            idTokenFor: (String _) async => 't',
          ),
          location: FakeLocationService(),
        ),
      );
      await tester.pumpAndSettle();
      final BuildContext context = tester.element(find.byType(HomeScreen));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => const CheckinScreen(
            place: Place(id: 'p1', name: '祠', lat: 34, lng: 135),
            lat: 34,
            lng: 135,
          ),
        ),
      );
      await tester.pumpAndSettle();

      FilledButton save() => tester.widget(
        find.ancestor(
          of: find.text('記録する'),
          matching: find.byWidgetPredicate((Widget w) => w is FilledButton),
        ),
      );
      expect(save().onPressed, isNull);

      await tester.tap(find.bySemanticsLabel('★2、まあまあ'));
      await tester.pump();
      expect(find.text('まあまあ'), findsOneWidget);
      await tester.tap(find.text('記録する'));
      await tester.pumpAndSettle();
      // 残すと、祝う画面で何人目か・★評価・シェアを見せる
      expect(find.byType(CheckinCelebrationScreen), findsOneWidget);
      expect(find.text('まあまあ'), findsOneWidget);
      expect(find.text(ShareTarget.x.label), findsOneWidget);
      await tester.ensureVisible(find.text('次の場所を探す'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('次の場所を探す'));
      await tester.pumpAndSettle();

      Map<String, dynamic> lastLog() =>
          jsonDecode(
                server.requests
                    .lastWhere(
                      (http.Request r) =>
                          r.method == 'POST' && r.url.path == '/api/logs',
                    )
                    .body,
              )
              as Map<String, dynamic>;
      expect(lastLog()['public'], isFalse);
      expect(lastLog()['rating'], 2);
      expect(lastLog()['verdict'], 'miss');
      expect(find.byType(CheckinScreen), findsNothing);

      Navigator.of(tester.element(find.byType(HomeScreen))).push(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => const CheckinScreen(
            place: Place(id: 'p2', name: '社', lat: 34, lng: 135),
            lat: 34,
            lng: 135,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('★5、最高！'));
      await tester.tap(find.text(l10n.visibilityPublic));
      await tester.pump();
      await tester.tap(find.text('記録する'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('次の場所を探す'));
      await tester.pumpAndSettle();

      expect(lastLog()['public'], isTrue);
      expect(lastLog()['rating'], 5);
      expect(lastLog()['verdict'], 'hit');
    });
  });

  group('Geminiちゃん', () {
    // 開いた後に地図の右下のボタンが隠れても（画面の高さが変わったときなど）、シートを描き直せる。
    // 配布用のビルドでは「Null check operator used on a null value」になっていた
    testWidgets('開いた後に地図のボタンが作り直されても、シートを描き直せる', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(412 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final _Server server = _Server(places: <Place>[_place('a')]);
      await _pumpApp(tester, server);

      await tester.tap(find.byTooltip('Geminiちゃん'));
      await tester.pumpAndSettle();
      expect(find.byType(AssistantSheet), findsOneWidget);

      // 低い画面にすると、右下のボタンを隠す
      tester.view.physicalSize = const Size(412 * 3, 300 * 3);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(412 * 3, 900 * 3);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AssistantSheet), findsOneWidget);
      expect(find.byType(ActionChip), findsWidgets);
    });

    testWidgets('話しかけると答えと理由を見せ、地図で同じ条件を探せる', (WidgetTester tester) async {
      final _Server server = _Server(places: <Place>[_place('a')]);
      await _pumpApp(tester, server);

      await tester.tap(find.byTooltip('Geminiちゃん'));
      await tester.pumpAndSettle();
      expect(find.byType(AssistantSheet), findsOneWidget);

      await tester.tap(find.text(AssistantSheet.examples.first));
      await tester.pumpAndSettle();

      final http.Request sent = server.requests.singleWhere(
        (http.Request r) => r.url.path == '/api/assistant',
      );
      final Map<String, dynamic> body =
          jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['message'], AssistantSheet.examples.first);
      expect(body['lat'], isA<double>());
      expect(find.text('嵐山の近くでお寺を選びました'), findsOneWidget);
      expect(find.text('静かな寺'), findsOneWidget);
      expect(find.text('口コミが少ない静かなお寺です'), findsOneWidget);

      await tester.tap(find.text('地図でこのあたりを探す'));
      await tester.pumpAndSettle();

      expect(find.byType(AssistantSheet), findsNothing);
      final Uri explore = server.to('/api/explore').last;
      expect(explore.queryParameters['lat'], '35.01');
      expect(explore.queryParameters['genre'], 'worship');
    });

    testWidgets('状況を一緒に送り、おすすめをそのまま地図と一覧に出せる', (WidgetTester tester) async {
      final _Server server = _Server();
      await _pumpApp(tester, server);
      await tester.tap(find.byTooltip('Geminiちゃん'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'お寺に行きたい');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      final Map<String, dynamic> body =
          jsonDecode(
                server.requests
                    .lastWhere(
                      (http.Request r) => r.url.path == '/api/assistant',
                    )
                    .body,
              )
              as Map<String, dynamic>;
      final Map<String, dynamic> context = (body['context'] as Map)
          .cast<String, dynamic>();
      expect(context['timeOfDay'], isIn(<String>['朝', '昼', '夕方', '夜', '深夜']));
      expect(context['onSite'], isA<bool>());

      // 答えの後の例文は、答えの種類に合わせる
      expect(find.text('もっと知られていない所'), findsOneWidget);

      final int explores = server.to('/api/explore').length;
      await tester.tap(find.text('おすすめを地図に出す'));
      await tester.pumpAndSettle();
      expect(find.byType(AssistantSheet), findsNothing);
      // 探し直さずに、おすすめの場所を一覧に出す
      expect(server.to('/api/explore').length, explores);
      expect(find.text('静かな寺'), findsWidgets);
    });

    testWidgets('おすすめを押すと場所の詳細を開く', (WidgetTester tester) async {
      final _Server server = _Server();
      await _pumpApp(tester, server);
      await tester.tap(find.byTooltip('Geminiちゃん'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'お寺に行きたい');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      await tester.tap(find.text('静かな寺'));
      await tester.pumpAndSettle();
      expect(find.byType(PlaceDetailScreen), findsOneWidget);
    });

    testWidgets('おすすめの詳細は、地図の検索ではなく答えの中心からの距離とデータ元で表示する', (
      WidgetTester tester,
    ) async {
      final _Server server = _Server(places: <Place>[_place('a')])
        ..exploreSource = 'mock';
      await _pumpApp(tester, server);
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Geminiちゃん'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'お寺に行きたい');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      await tester.tap(find.text('静かな寺'));
      await tester.pumpAndSettle();

      final PlaceDetailScreen detail = tester.widget(
        find.byType(PlaceDetailScreen),
      );
      // 答えの中心は嵐山（35.01, 135.67）で、おすすめは 34.697, 135.192 にある
      expect(
        detail.distanceMeters,
        distanceMeters(35.01, 135.67, 34.697, 135.192),
      );
      expect(detail.isMock, isFalse);
    });
  });

  group('実績', () {
    testWidgets('実績とスタンプ帳を切り替え、スタンプ帳では集めた種類と月ごとのスタンプを見せる', (
      WidgetTester tester,
    ) async {
      final _Server server = _Server();
      await _pumpApp(tester, server);
      await tester.tap(find.bySemanticsLabel('実績'));
      await tester.pumpAndSettle();
      // 最初は実績だけを見せ、スタンプは出さない
      expect(find.byType(StampSeal), findsNothing);

      await tester.tap(find.text(l10n.achievementsViewStamps));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsWidgets);
      expect(find.text(l10n.stampBookTotalUnit), findsOneWidget);
      expect(find.textContaining('集めた種類'), findsOneWidget);
      expect(find.byType(StampSeal), findsOneWidget);
      expect(find.text(l10n.stampBookMonthCount(1)), findsOneWidget);

      // スタンプを押すと記録の詳細を開き、シェアできる
      await tester.tap(find.byType(StampSeal));
      await tester.pumpAndSettle();
      expect(find.text(l10n.shareAction), findsOneWidget);
      await tester.tap(find.text(l10n.shareAction));
      await tester.pumpAndSettle();
      expect(find.text(l10n.shareSheetTitle), findsOneWidget);
      expect(find.text(ShareTarget.line.label), findsOneWidget);
    });

    testWidgets('思い出ログから解除した実績を数える', (WidgetTester tester) async {
      final _Server server = _Server();
      await _pumpApp(tester, server);
      await tester.tap(find.bySemanticsLabel('実績'));
      await tester.pumpAndSettle();

      expect(find.byType(AchievementsScreen), findsOneWidget);
      // 1人目のハズレが1件：はじめの一歩、開拓者、名誉のハズレ（時刻で決まるシークレット実績は端末の時間帯による）
      expect(
        find.text('/ ${achievementDefinitions.length} 解除'),
        findsOneWidget,
      );
      // 上に「もう少しで解除」と絞り込みがあるので、一覧の実績までスクロールする
      await tester.scrollUntilVisible(
        find.bySemanticsLabel('名誉のハズレ、解除済み'),
        200,
        scrollable: _verticalScrollable,
      );
      expect(find.bySemanticsLabel('名誉のハズレ、解除済み'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.bySemanticsLabel('目利き、未解除'),
        200,
        scrollable: _verticalScrollable,
      );
      expect(find.bySemanticsLabel('目利き、未解除'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.bySemanticsLabel('名誉のハズレ、解除済み'),
        -200,
        scrollable: _verticalScrollable,
      );

      // 詳細を開くと、解除した場所と日付が見える
      await tester.tap(find.bySemanticsLabel('名誉のハズレ、解除済み'));
      await tester.pumpAndSettle();
      expect(find.byType(AchievementDetailSheet), findsOneWidget);
      expect(find.textContaining('に解除'), findsWidgets);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // シークレット実績は、解除するまで名前を隠してヒントだけを見せる
      await tester.scrollUntilVisible(
        find.textContaining('ヒント：あと少しで一番乗り'),
        300,
        scrollable: _verticalScrollable,
      );
      expect(find.text('惜しい！'), findsNothing);
      expect(find.textContaining('ヒント：'), findsWidgets);
    });
  });

  group('タイムライン', () {
    Future<void> openTimeline(WidgetTester tester, _Server server) async {
      await _pumpApp(tester, server);
      await tester.tap(find.bySemanticsLabel('タイムライン'));
      await tester.pumpAndSettle();
      expect(find.byType(TimelineScreen), findsOneWidget);
    }

    Map<String, Object> log(String id, String name, String createdAt) =>
        <String, Object>{
          'id': id,
          'placeId': 'p_$id',
          'placeName': name,
          'verdict': 'hit',
          'stars': 4,
          'comment': '',
          'order': 1,
          'public': false,
          'createdAt': createdAt,
        };

    testWidgets('自分の記録は新しい順に1列で並び、日付の見出しで区切られる', (WidgetTester tester) async {
      final _Server server = _Server()
        ..logs = <Map<String, Object>>[
          log('a', '古い場所', '2026-11-05T03:00:00Z'),
          log('b', '新しい場所', '2026-11-08T05:30:00Z'),
          log('c', '同じ日の朝の場所', '2026-11-08T01:00:00Z'),
        ];
      await openTimeline(tester, server);

      double y(String text) => tester.getTopLeft(find.text(text)).dy;
      String header(String createdAt) {
        final DateTime t = DateTime.parse(createdAt).toLocal();
        return timelineDayLabel(
          DateTime(t.year, t.month, t.day),
          DateTime.now(),
        );
      }

      final String newDay = header('2026-11-08T05:30:00Z');
      final String oldDay = header('2026-11-05T03:00:00Z');
      expect(find.text(newDay), findsOneWidget);
      expect(find.text(oldDay), findsOneWidget);
      expect(y(newDay), lessThan(y('新しい場所')));
      expect(y('新しい場所'), lessThan(y('同じ日の朝の場所')));
      expect(y('同じ日の朝の場所'), lessThan(y(oldDay)));
      expect(y(oldDay), lessThan(y('古い場所')));
      // 1列なので、カードの左端がそろう
      expect(
        tester.getTopLeft(find.text('新しい場所')).dx,
        tester.getTopLeft(find.text('古い場所')).dx,
      );
    });

    testWidgets('日付の見出しは、今日と昨日を日付の前に添え、年が違うときは年も示す', (
      WidgetTester tester,
    ) async {
      final DateTime now = DateTime(2026, 11, 10, 15);
      expect(
        timelineDayLabel(DateTime(2026, 11, 10), now),
        '${l10n.timelineToday}　${l10n.timelineDate(11, 10, '2')}',
      );
      expect(
        timelineDayLabel(DateTime(2026, 11, 9), now),
        '${l10n.timelineYesterday}　${l10n.timelineDate(11, 9, '1')}',
      );
      expect(
        timelineDayLabel(DateTime(2025, 12, 31), now),
        l10n.timelineDateWithYear(2025, 12, 31, '3'),
      );
      expect(l10n.timelineDate(11, 10, '2'), '11月10日（火）');
    });

    testWidgets('広い画面では、左の列に切り替えボタン、右の列に記録を並べる', (WidgetTester tester) async {
      await _pumpApp(tester, _Server(), size: const Size(1280, 800));
      await tester.tap(find.bySemanticsLabel('タイムライン'));
      await tester.pumpAndSettle();
      final Rect toggle = tester.getRect(
        find.byType(SegmentedButton<TimelineScope>),
      );
      final Rect card = tester.getRect(find.text('自分の場所'));
      expect(toggle.width, closeTo(340, 1));
      expect(card.left, greaterThan(toggle.right));
      expect(card.top, lessThan(toggle.bottom + 200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('狭い画面では、切り替えボタンを画面の幅いっぱいに置く', (WidgetTester tester) async {
      await _pumpApp(tester, _Server(), size: const Size(400, 800));
      await tester.tap(find.bySemanticsLabel('タイムライン'));
      await tester.pumpAndSettle();
      final Rect toggle = tester.getRect(
        find.byType(SegmentedButton<TimelineScope>),
      );
      expect(toggle.left, closeTo(16, 1));
      expect(toggle.width, closeTo(400 - 32, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('タイムラインに文字付きの「お気に入り」があり、お気に入りの場所を見られる', (
      WidgetTester tester,
    ) async {
      final _Server server = _Server(places: <Place>[_place('静かな公園')])
        ..favorites.add('静かな公園');
      await openTimeline(tester, server);
      expect(find.text('自分の記録'), findsOneWidget);
      expect(find.text(l10n.nearby), findsOneWidget);

      await tester.tap(find.text('お気に入り'));
      await tester.pumpAndSettle();
      expect(find.byType(FavoritesList), findsOneWidget);
      expect(find.text('静かな公園'), findsOneWidget);
    });

    testWidgets('自分と周辺を行き来しても、自分の記録を表示できる', (WidgetTester tester) async {
      final _Server server = _Server();
      await openTimeline(tester, server);
      expect(find.text('自分の場所'), findsOneWidget);

      await tester.tap(find.text(l10n.nearby));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自分の記録'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('自分の場所'), findsOneWidget);
    });

    testWidgets('記録を押すと、詳細を開いて Google マップで開ける', (WidgetTester tester) async {
      final _Server server = _Server();
      await openTimeline(tester, server);
      await tester.tap(find.text(l10n.nearby));
      await tester.pumpAndSettle();

      await tester.tap(find.text('公開された場所'));
      await tester.pumpAndSettle();

      expect(find.byType(EntryDetailSheet), findsOneWidget);
      expect(find.text('Google マップで開く'), findsOneWidget);
      expect(find.text('この記録を報告'), findsOneWidget);
      final EntryDetailSheet sheet = tester.widget(
        find.byType(EntryDetailSheet),
      );
      expect(sheet.entry.mapsUri.queryParameters['query_place_id'], isNotEmpty);
      expect(sheet.entry.mapsUri.queryParameters['query'], '公開された場所');
    });

    testWidgets('周辺の記録は、投稿者を符号ではなくニックネームとアイコンで示す', (WidgetTester tester) async {
      final _Server server = _Server();
      await openTimeline(tester, server);
      await tester.tap(find.text(l10n.nearby));
      await tester.pumpAndSettle();

      expect(find.text('さんぽ部'), findsOneWidget);
      expect(find.byIcon(ProfileIcon.pets.icon), findsOneWidget);
      expect(find.text('AB12CD'), findsNothing);
    });

    testWidgets('自分の記録の公開状態を、読み直さずに変えられる', (WidgetTester tester) async {
      final _Server server = _Server();
      await openTimeline(tester, server);
      expect(find.text('自分の場所'), findsOneWidget);
      final int reads = server.to('/api/logs').length;

      await tester.tap(find.byIcon(Icons.lock_outline));
      await tester.pumpAndSettle();

      final http.Request patch = server.requests.singleWhere(
        (http.Request r) => r.method == 'PATCH',
      );
      expect(patch.url.path, '/api/logs/lg_1');
      expect(jsonDecode(patch.body), <String, bool>{'public': true});
      expect(find.byIcon(Icons.public), findsOneWidget);
      expect(server.to('/api/logs').length, reads);
    });

    testWidgets('自分の記録を押して、★評価とひとことを後から直せる', (WidgetTester tester) async {
      final _Server server = _Server();
      await openTimeline(tester, server);
      final int reads = server.to('/api/logs').length;

      await tester.tap(find.text('自分の場所'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.editLog));
      await tester.pumpAndSettle();
      expect(find.byType(EditLogSheet), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(RegExp('^★2、')));
      await tester.enterText(
        find.descendant(
          of: find.byType(EditLogSheet),
          matching: find.byType(TextField),
        ),
        '思ったより混んでいた',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final http.Request patch = server.requests.singleWhere(
        (http.Request r) => r.method == 'PATCH',
      );
      expect(patch.url.path, '/api/logs/lg_1');
      expect(jsonDecode(patch.body), <String, Object>{
        'rating': 2,
        'comment': '思ったより混んでいた',
      });
      // 一覧を読み直さずに、直した内容を見せる
      expect(find.text('思ったより混んでいた'), findsOneWidget);
      expect(server.to('/api/logs').length, reads);
    });

    testWidgets('周辺の記録の場所を、お気に入りに入れられる', (WidgetTester tester) async {
      final _Server server = _Server();
      await openTimeline(tester, server);
      await tester.tap(find.text(l10n.nearby));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('お気に入りに入れる').first);
      await tester.pumpAndSettle();

      expect(
        server.requests.where(
          (http.Request r) =>
              r.method == 'PUT' && r.url.path.startsWith('/api/favorites/'),
        ),
        hasLength(1),
      );
      expect(find.byTooltip('お気に入りから外す'), findsWidgets);
    });

    testWidgets('自分の記録を読めないときは理由を示し、もう一度試すと読み直す', (WidgetTester tester) async {
      final _Server server = _Server()..failLogs = true;
      await openTimeline(tester, server);
      expect(find.text('記録を読めませんでした'), findsOneWidget);
      expect(find.text('自分の場所'), findsNothing);

      server.failLogs = false;
      await tester.tap(find.text('もう一度試す'));
      await tester.pumpAndSettle();

      expect(find.text('自分の場所'), findsOneWidget);
    });

    testWidgets('公開の取り消しに失敗したら、公開中の表示に戻す', (WidgetTester tester) async {
      final _Server server = _Server();
      await openTimeline(tester, server);

      await tester.tap(find.byIcon(Icons.lock_outline));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.public), findsOneWidget);

      server.failPatch = true;
      await tester.tap(find.byIcon(Icons.public));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.public), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.text('変更できません'), findsOneWidget);
    });

    testWidgets('地図を別の地点へ動かしてタブを開くと、周辺の記録を読み直し、基準の地点を示す', (
      WidgetTester tester,
    ) async {
      final _Server server = _Server();
      await openTimeline(tester, server);
      await tester.tap(find.text(l10n.nearby));
      await tester.pumpAndSettle();
      expect(server.to('/api/timeline'), hasLength(1));
      expect(find.text('現在地'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('地図'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('タイムライン'));
      await tester.pumpAndSettle();
      expect(server.to('/api/timeline'), hasLength(1), reason: '地点が同じなら読み直さない');

      await tester.tap(find.bySemanticsLabel('地図'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '嵐山');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('タイムライン'));
      await tester.pumpAndSettle();

      expect(server.to('/api/timeline'), hasLength(2));
      expect(server.to('/api/timeline').last.queryParameters['lat'], '35.01');
      expect(find.text('嵐山'), findsWidgets);
    });

    testWidgets('端末だけで動くときの架空の投稿は、ダミーと分かるように示す', (WidgetTester tester) async {
      await _pumpApp(tester, _Server(), checkins: LocalCheckinRepository());
      await tester.tap(find.bySemanticsLabel('タイムライン'));
      await tester.pumpAndSettle();
      expect(find.byType(MockBanner), findsNothing);

      await tester.tap(find.text(l10n.nearby));
      await tester.pumpAndSettle();

      expect(find.byType(MockBanner), findsOneWidget);
    });

    testWidgets('本物の投稿にはダミーの表示を出さない', (WidgetTester tester) async {
      await openTimeline(tester, _Server());
      await tester.tap(find.text(l10n.nearby));
      await tester.pumpAndSettle();

      expect(find.byType(MockBanner), findsNothing);
    });

    testWidgets('みんなの口コミは、周辺と全国の新着を切り替えて見られる', (WidgetTester tester) async {
      final _Server server = _Server();
      await openTimeline(tester, server);
      await tester.tap(find.text(l10n.nearby));
      await tester.pumpAndSettle();
      expect(server.to('/api/timeline').last.queryParameters['lat'], isNotNull);

      await tester.tap(find.text(l10n.timelineAreaNationwide));
      await tester.pumpAndSettle();
      final Uri all = server.to('/api/timeline').last;
      expect(all.queryParameters['scope'], 'all');
      expect(all.queryParameters['lat'], isNull);
      expect(find.text(l10n.timelineNationwideNote), findsOneWidget);
      expect(find.text('公開された場所'), findsOneWidget);
    });

    testWidgets('周辺に切り替えると公開された記録を読み、報告すると消える', (WidgetTester tester) async {
      final _Server server = _Server();
      await openTimeline(tester, server);
      expect(server.to('/api/timeline'), isEmpty);

      await tester.tap(find.text(l10n.nearby));
      await tester.pumpAndSettle();

      expect(find.text('公開された場所'), findsOneWidget);
      expect(find.text('さんぽ部'), findsOneWidget);

      await tester.tap(find.byTooltip('この記録を報告'));
      await tester.pumpAndSettle();
      // 理由を選ぶまで報告できない。やめたときは何もしない
      expect(find.text(l10n.reportSheetTitle), findsOneWidget);
      final Finder send = find.widgetWithText(FilledButton, l10n.reportSend);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      await tester.tap(find.text(l10n.reportReasonSpam));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, '同じ宣伝が何度も');
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(find.text('公開された場所'), findsNothing);
      final List<http.Request> reports = server.requests
          .where((http.Request r) => r.url.path == '/api/timeline/e1/report')
          .toList();
      expect(reports, hasLength(1));
      expect(jsonDecode(reports.single.body), <String, Object>{
        'reason': 'spam',
        'note': '同じ宣伝が何度も',
      });
    });

    testWidgets('報告の理由を選ぶ画面を閉じたら報告しない', (WidgetTester tester) async {
      final _Server server = _Server();
      await openTimeline(tester, server);
      await tester.tap(find.text(l10n.nearby));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('この記録を報告'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('公開された場所'), findsOneWidget);
      expect(server.to('/api/timeline/e1/report'), isEmpty);
    });
  });

  group('口コミへの反応', () {
    testWidgets('ほかの人の口コミに「行ってみたい」を付け外しでき、数が変わる', (WidgetTester tester) async {
      final _Server server = _Server();
      await _pumpApp(tester, server);
      await tester.tap(find.bySemanticsLabel('タイムライン'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.nearby));
      await tester.pumpAndSettle();

      expect(find.text('行ってみたい 3'), findsOneWidget);
      await tester.tap(find.text('行ってみたい 3'));
      await tester.pumpAndSettle();
      expect(find.text('行ってみたい 4'), findsOneWidget);
      expect(
        server.requests.where(
          (http.Request r) =>
              r.method == 'PUT' &&
              r.url.path == '/api/timeline/e1/reactions/want',
        ),
        hasLength(1),
      );

      await tester.tap(find.text('行ってみたい 4'));
      await tester.pumpAndSettle();
      expect(find.text('行ってみたい 3'), findsOneWidget);
      expect(
        server.requests.where((http.Request r) => r.method == 'DELETE'),
        hasLength(1),
      );
    });
  });

  group('ダミーデータだけで動くとき', () {
    test('端末の保存先でも、公開状態を変え、周辺に見せ、報告を反映する', () async {
      final LocalCheckinRepository repo = LocalCheckinRepository();
      await repo.addLog(
        MemoryLog(
          id: '',
          placeId: 'mock_01',
          placeName: '祠',
          verdict: Verdict.hit,
          createdAt: DateTime(2026),
        ),
      );
      final MemoryLog saved = (await repo.watchLogs().first).single;
      expect(saved.id, isNotEmpty);

      final int before = (await repo.nearbyTimeline(lat: 0, lng: 0)).length;
      await repo.setLogPublic(saved, isPublic: true);
      final entries = await repo.nearbyTimeline(lat: 0, lng: 0);
      expect(entries.length, before + 1);
      expect(entries.first.mine, isTrue);

      await repo.reportEntry(entries.last.id, reason: ReportReason.spam);
      expect((await repo.nearbyTimeline(lat: 0, lng: 0)).length, before);
    });
  });
}

/// 縦に流れる一覧（実績のページの中には、横に流れるスタンプ帳もある）
final Finder _verticalScrollable = find
    .byWidgetPredicate(
      (Widget w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .last;
