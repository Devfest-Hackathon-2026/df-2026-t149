import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uramichi/app.dart';
import 'package:uramichi/core/settings.dart';
import 'package:uramichi/core/api/mock_data.dart';
import 'package:uramichi/core/api/uramichi_api.dart';
import 'package:uramichi/core/data/checkin_repository.dart';
import 'package:uramichi/core/models/place.dart';
import 'package:uramichi/core/widgets/mock_banner.dart';
import 'package:uramichi/core/location/location_service.dart';
import 'package:uramichi/features/alternatives/alternatives_screen.dart';
import 'package:uramichi/features/checkin/checkin_screen.dart';
import 'package:uramichi/features/home/home_screen.dart';
import 'package:uramichi/features/place/place_detail_screen.dart';

import 'fake_location.dart';
import 'fake_account.dart';

Place _place(
  String id,
  String name, {
  int obscurity = 50,
  String title = 'hidden',
  int reviews = 50,
  int? distance,
  String type = 'park',
}) => Place(
  id: id,
  name: name,
  lat: 34.693,
  lng: 135.19,
  primaryType: type,
  userRatingCount: reviews,
  obscurity: obscurity,
  title: title,
  distanceMeters: distance,
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// API サーバーの代わり。受け取ったリクエストを記録し、[handler] の応答を返す
/// アプリに同梱するダミーデータの代わり。API を使えないときに、この場所と候補を返す
MockData _testMock() => MockData(
  load: (String path) async => path.endsWith('explore.json')
      ? jsonEncode(<String, Object?>{
          ..._explore(<Place>[_place('m', 'ダミーの路地')], mock: true),
          'center': <String, double>{'lat': 34.693, 'lng': 135.19},
        })
      : jsonEncode(<String, Object?>{
          'source': 'mock',
          'origin': _place(
            'mo',
            'ダミーの大きな寺',
            title: 'famous',
            reviews: 9000,
          ).toJson(),
          'alternatives': <Map<String, dynamic>>[
            _place(
              'ma',
              'ダミーの小道',
              title: 'untrodden',
              reviews: 2,
              distance: 500,
            ).toJson(),
          ],
        }),
);

class _FakeServer {
  _FakeServer(this.handler);

  /// API サーバーに接続できない状態
  _FakeServer.unreachable()
    : handler = ((Uri uri) => throw http.ClientException('接続できません', uri));

  http.Response Function(Uri uri) handler;
  final List<Uri> requests = <Uri>[];

  /// null でないあいだ、応答を返さずに待たせる
  Completer<void>? gate;

  UramichiApi api() => UramichiApi(
    baseUrl: 'http://test',
    client: MockClient((http.Request request) async {
      requests.add(request.url);
      final Completer<void>? gate = this.gate;
      if (gate != null) {
        await gate.future;
      }
      return handler(request.url);
    }),
    mock: _testMock(),
  );

  Iterable<Uri> requestsTo(String path) =>
      requests.where((Uri uri) => uri.path == path);
}

Map<String, Object?> _explore(
  List<Place> places, {
  bool mock = false,
}) => <String, Object?>{
  'source': mock ? 'mock' : 'google',
  'places': <Map<String, dynamic>>[for (final Place p in places) p.toJson()],
};

Future<void> _pumpApp(
  WidgetTester tester,
  _FakeServer server, {
  LocationService? location,
}) async {
  tester.view.physicalSize = const Size(1200, 2700);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UramichiApp(
      account: readyAccountNow(),
      api: server.api(),
      checkins: LocalCheckinRepository(),
      location: location ?? FakeLocationService(),
      settings: AppSettings(),
    ),
  );
}

/// ホームの上に画面を開く
Future<void> _push(WidgetTester tester, Widget screen) async {
  Navigator.of(
    tester.element(find.byType(HomeScreen)),
  ).push(MaterialPageRoute<void>(builder: (BuildContext _) => screen));
  await tester.pumpAndSettle();
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  group('API を使えないとき', () {
    testWidgets('API サーバーに接続できなくても、ダミーデータを表示しない', (WidgetTester tester) async {
      await _pumpApp(tester, _FakeServer.unreachable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();

      expect(find.text('ダミーの路地'), findsNothing);
      expect(find.byType(MockBanner), findsNothing);
    });

    testWidgets('API が本物のデータを返すときは、ダミーデータの帯を表示しない', (
      WidgetTester tester,
    ) async {
      await _pumpApp(
        tester,
        _FakeServer((Uri _) => _json(_explore(<Place>[_place('r', '本物の路地')]))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();

      expect(find.text('本物の路地'), findsWidgets);
      expect(find.byType(MockBanner), findsNothing);
    });

    testWidgets('代わりの検索も、API サーバーに接続できないときはダミーの候補を出さない', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, _FakeServer.unreachable());
      await tester.pumpAndSettle();
      await _push(tester, const AlternativesScreen());
      await tester.enterText(find.byType(TextField), '清水寺');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('ダミーの大きな寺'), findsNothing);
      expect(find.text('もう一度試す'), findsOneWidget);
    });
  });

  group('代わりに行くならここ', () {
    final Place origin = _place(
      'o',
      '駅前の大きな神社',
      obscurity: 0,
      title: 'famous',
      reviews: 15400,
      type: 'shinto_shrine',
    );

    Map<String, Object?> alternatives(List<Place> places) => <String, Object?>{
      'source': 'google',
      'origin': origin.toJson(),
      'alternatives': <Map<String, dynamic>>[
        for (final Place p in places) p.toJson(),
      ],
    };

    Future<void> search(
      WidgetTester tester,
      _FakeServer server,
      String query,
    ) async {
      await _pumpApp(tester, server);
      await tester.pumpAndSettle();
      await _push(tester, const AlternativesScreen());
      await tester.enterText(find.byType(TextField), query);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    }

    testWidgets('検索のボタンで検索する。入力が空の間は押せない', (WidgetTester tester) async {
      final _FakeServer server = _FakeServer(
        (Uri uri) => uri.path == '/api/alternatives'
            ? _json(alternatives(<Place>[]))
            : _json(_explore(<Place>[])),
      );
      await _pumpApp(tester, server);
      await tester.pumpAndSettle();
      await _push(tester, const AlternativesScreen());

      final Finder button = find.widgetWithIcon(IconButton, Icons.search);
      expect(tester.widget<IconButton>(button).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '  駅前の大きな神社 ');
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(
        server.requestsTo('/api/alternatives').single.queryParameters['q'],
        '駅前の大きな神社',
      );
    });

    testWidgets('候補が少ないときは候補を表示したまま範囲を広げられる', (WidgetTester tester) async {
      final _FakeServer server = _FakeServer(
        (Uri uri) => uri.path == '/api/alternatives'
            ? _json(
                alternatives(<Place>[
                  _place('a', '小さな祠', obscurity: 90, reviews: 3),
                ]),
              )
            : _json(_explore(<Place>[])),
      );
      await search(tester, server, '駅前の大きな神社');

      expect(find.text('小さな祠'), findsOneWidget);
      await tester.ensureVisible(find.text('範囲を広げる'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('範囲を広げる'));
      await tester.pumpAndSettle();

      expect(
        server
            .requestsTo('/api/alternatives')
            .map((Uri uri) => uri.queryParameters['radius']),
        <String>['3000', '6000'],
      );
    });

    testWidgets('候補が 3 件あれば範囲を広げる操作を表示しない', (WidgetTester tester) async {
      final _FakeServer server = _FakeServer(
        (Uri uri) => uri.path == '/api/alternatives'
            ? _json(
                alternatives(<Place>[
                  _place('a', '小さな祠', obscurity: 90, reviews: 3),
                  _place('b', '小さな社', obscurity: 80, reviews: 5),
                  _place('c', '小さな庭', obscurity: 70, reviews: 9),
                ]),
              )
            : _json(_explore(<Place>[])),
      );
      await search(tester, server, '駅前の大きな神社');

      expect(find.text('範囲を広げる'), findsNothing);
    });

    testWidgets('有名スポットを表示し、最も近い候補をいちばん上に選定理由と共に表示する', (
      WidgetTester tester,
    ) async {
      final _FakeServer server = _FakeServer(
        (Uri uri) => uri.path == '/api/alternatives'
            ? _json(
                alternatives(<Place>[
                  _place(
                    'a',
                    '遠い未踏の祠',
                    obscurity: 90,
                    title: 'untrodden',
                    distance: 1500,
                    type: 'shinto_shrine',
                    reviews: 10,
                  ),
                  _place(
                    'b',
                    '近い未踏の社',
                    obscurity: 90,
                    title: 'untrodden',
                    distance: 400,
                    type: 'shinto_shrine',
                    reviews: 3,
                  ),
                  _place(
                    'c',
                    '穴場の公園',
                    obscurity: 60,
                    distance: 2000,
                    reviews: 300,
                  ),
                ]),
              )
            : _json(_explore(<Place>[])),
      );
      await search(tester, server, '駅前の大きな神社');

      expect(
        server.requestsTo('/api/alternatives').single.queryParameters['q'],
        '駅前の大きな神社',
      );
      expect(find.text('駅前の大きな神社'), findsWidgets);
      expect(find.text('15,400件'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(AlternativesScreen.topCandidateKey),
          matching: find.text('近い未踏の社'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(AlternativesScreen.topCandidateKey),
          matching: find.textContaining('レビュー 1/5133'),
        ),
        findsOneWidget,
      );
      expect(find.text('レビュー 1/51 以下'), findsOneWidget);
      expect(_top(tester, '遠い未踏の祠'), lessThan(_top(tester, '穴場の公園')));
    });

    testWidgets('有名スポットが見つからないときは、別の名前で探す操作を示す', (WidgetTester tester) async {
      final _FakeServer server = _FakeServer(
        (Uri uri) => uri.path == '/api/alternatives'
            ? _json(<String, Object?>{
                'error': <String, String>{
                  'code': 'origin_not_found',
                  'message': '見つかりませんでした',
                },
              }, 404)
            : _json(_explore(<Place>[])),
      );
      await search(tester, server, 'ないお寺');

      expect(find.text('「ないお寺」が見つかりませんでした'), findsOneWidget);
      expect(find.text('別の名前で探す'), findsOneWidget);
    });

    testWidgets('候補が0件のときは、範囲を広げて探し直せる', (WidgetTester tester) async {
      final _FakeServer server = _FakeServer(
        (Uri uri) => uri.path == '/api/alternatives'
            ? _json(alternatives(<Place>[]))
            : _json(_explore(<Place>[])),
      );
      await search(tester, server, '駅前の大きな神社');

      await tester.tap(find.text('範囲を広げる'));
      await tester.pumpAndSettle();

      final List<Uri> calls = server.requestsTo('/api/alternatives').toList();
      expect(calls.first.queryParameters['radius'], '3000');
      expect(calls.last.queryParameters['radius'], '6000');
    });

    test('並び順は有名スポットから近い順で、距離が不明な候補は最後になる', () {
      final List<Place> sorted = sortAlternatives(<Place>[
        _place('a', 'A', obscurity: 90, distance: 900),
        _place('b', 'B', obscurity: 50, distance: 300),
        _place('c', 'C', obscurity: 90),
        _place('d', 'D', obscurity: 70, distance: 600),
      ]);
      expect(sorted.map((Place p) => p.id), <String>['b', 'd', 'a', 'c']);
    });

    group('選定理由', () {
      Place typed(String type, {int reviews = 100, List<String>? types}) =>
          Place(
            id: type,
            name: type,
            lat: 0,
            lng: 0,
            primaryType: type,
            types: types ?? <String>[type],
            userRatingCount: reviews,
          );

      test('同じジャンルなら同じであることとレビューの比率を示す', () {
        expect(
          alternativeReason(
            typed('shinto_shrine', reviews: 100),
            typed('buddhist_temple', reviews: 21250),
          ),
          '同じ寺社・レビュー 1/212',
        );
      });

      test('ジャンルが違えば比率だけを示す', () {
        expect(
          alternativeReason(
            typed('park', reviews: 100),
            typed('museum', reviews: 1000),
          ),
          'レビュー 1/10',
        );
      });

      test('観光名所全般を含む展望は同じジャンルとして示さない', () {
        expect(
          alternativeReason(
            typed('tourist_attraction', reviews: 100),
            typed('observation_deck', reviews: 1000),
          ),
          'レビュー 1/10',
        );
      });

      test('主な種類が一覧にない場合は types からジャンルを判定する', () {
        expect(
          alternativeReason(
            typed('city_park', types: <String>['city_park', 'park']),
            typed('garden', reviews: 500),
          ),
          '同じ公園・レビュー 1/5',
        );
      });

      test('ジャンルが不明なら比率だけを示す', () {
        expect(
          alternativeReason(
            typed('library', reviews: 100),
            typed('stadium', reviews: 1000),
          ),
          'レビュー 1/10',
        );
      });

      test('比率が 2 分の 1 より大きければ比率を示さない', () {
        expect(
          alternativeReason(
            typed('park', reviews: 700),
            typed('garden', reviews: 1000),
          ),
          '同じ公園',
        );
      });

      test('示せる情報がなければ null を返す', () {
        expect(
          alternativeReason(
            typed('library', reviews: 700),
            typed('stadium', reviews: 1000),
          ),
          isNull,
        );
      });
    });

    test('候補のレビュー数が有名スポットの何分の1以下かを表す', () {
      expect(
        fewerReviewsLabel(origin, <Place>[_place('a', 'A', reviews: 300)]),
        'レビュー 1/51 以下',
      );
      expect(
        fewerReviewsLabel(origin, <Place>[_place('a', 'A', reviews: 0)]),
        'レビュー 0件の場所だけ',
      );
      expect(
        fewerReviewsLabel(origin, <Place>[_place('a', 'A', reviews: 10000)]),
        isNull,
      );
    });
  });

  group('場所の詳細のチェックイン', () {
    Future<void> openDetail(
      WidgetTester tester,
      FakeLocationService location, {
      String id = 'p',
    }) async {
      final _FakeServer server = _FakeServer(
        (Uri _) => _json(_explore(<Place>[_place(id, '路地裏の古書喫茶')])),
      );
      await _pumpApp(tester, server, location: location);
      await tester.pumpAndSettle();
      await _push(tester, PlaceDetailScreen(place: _place(id, '路地裏の古書喫茶')));
      location.lastAsk = null;
    }

    GeoSample at(double lat, double lng) => GeoSample(
      lat: lat,
      lng: lng,
      accuracyMeters: 10,
      at: DateTime(2026, 11, 8, 12),
    );

    testWidgets('詳細を開いただけでは位置情報の許可を求めない', (WidgetTester tester) async {
      final FakeLocationService location = FakeLocationService();
      final _FakeServer server = _FakeServer(
        (Uri _) => _json(_explore(<Place>[_place('p', '路地裏の古書喫茶')])),
      );
      await _pumpApp(tester, server, location: location);
      await tester.pumpAndSettle();
      location.lastAsk = null;

      await _push(tester, PlaceDetailScreen(place: _place('p', '路地裏の古書喫茶')));

      expect(location.lastAsk, isNull);
    });

    testWidgets('500 m 以内ならチェックインの画面を開く', (WidgetTester tester) async {
      final FakeLocationService location = FakeLocationService();
      await openDetail(tester, location);
      location.position = at(34.693, 135.19);

      await tester.tap(find.byKey(const ValueKey<String>('detail-stamp')));
      await tester.pumpAndSettle();

      expect(find.byType(CheckinScreen), findsOneWidget);
    });

    testWidgets('500 m より遠いとチェックインの画面を開かず、距離を示す', (WidgetTester tester) async {
      final FakeLocationService location = FakeLocationService();
      await openDetail(tester, location);
      location.position = at(34.71, 135.19);

      await tester.tap(find.byKey(const ValueKey<String>('detail-stamp')));
      await tester.pumpAndSettle();

      expect(find.byType(CheckinScreen), findsNothing);
      expect(find.textContaining('この場所まで 1.9 km あります'), findsOneWidget);
    });

    testWidgets('位置情報が許可されていないと、設定を開く操作を示す', (WidgetTester tester) async {
      final FakeLocationService location = FakeLocationService();
      await openDetail(tester, location);
      location.access = LocationAccess.deniedForever;

      await tester.tap(find.byKey(const ValueKey<String>('detail-stamp')));
      await tester.pumpAndSettle();

      expect(find.byType(CheckinScreen), findsNothing);
      expect(find.text('位置情報が許可されていません'), findsOneWidget);
      expect(find.text('設定を開く'), findsOneWidget);
    });

    testWidgets('現在地を測定できないと、チェックインの画面を開かずに伝える', (WidgetTester tester) async {
      final FakeLocationService location = FakeLocationService();
      await openDetail(tester, location);
      location.position = null;

      await tester.tap(find.byKey(const ValueKey<String>('detail-stamp')));
      await tester.pumpAndSettle();

      expect(find.byType(CheckinScreen), findsNothing);
      expect(find.text('現在地を測定できませんでした'), findsOneWidget);
    });

    testWidgets('ダミーの場所は現在地を確かめずにチェックインの画面を開く', (WidgetTester tester) async {
      final FakeLocationService location = FakeLocationService();
      await openDetail(tester, location, id: 'mock_01');
      location.position = at(0, 0);

      await tester.tap(find.byKey(const ValueKey<String>('detail-stamp')));
      await tester.pumpAndSettle();

      expect(location.lastAsk, isNull);
      expect(find.byType(CheckinScreen), findsOneWidget);
    });
  });

  group('場所の詳細', () {
    testWidgets('称号、名前、レビュー数、ウラミチで来た人数を表示し、押してスタンプでチェックインを開く', (
      WidgetTester tester,
    ) async {
      final _FakeServer server = _FakeServer(
        (Uri _) => _json(
          _explore(<Place>[
            _place(
              'p',
              '路地裏の古書喫茶',
              title: 'untrodden',
              reviews: 3,
              type: 'cafe',
            ),
          ]),
        ),
      );
      await _pumpApp(tester, server);
      await tester.pumpAndSettle();

      await _push(
        tester,
        PlaceDetailScreen(
          place: _place(
            'p',
            '路地裏の古書喫茶',
            title: 'untrodden',
            reviews: 3,
            type: 'cafe',
          ),
          distanceMeters: 120,
        ),
      );

      expect(find.text('未踏'), findsWidgets);
      expect(find.text('路地裏の古書喫茶'), findsOneWidget);
      expect(find.text('レビュー'), findsOneWidget);
      expect(find.text('ウラミチで来た人'), findsOneWidget);
      expect(find.text('距離'), findsOneWidget);
      expect(find.text('道順'), findsOneWidget);
      expect(find.text('Google マップで開く'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('detail-stamp')));
      await tester.pumpAndSettle();
      expect(find.byType(CheckinScreen), findsOneWidget);
    });
  });

  testWidgets('端末がダークモードのときはダークのテーマで表示する', (WidgetTester tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final _FakeServer server = _FakeServer(
      (Uri _) => _json(_explore(<Place>[])),
    );
    await _pumpApp(tester, server);
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(HomeScreen));
    expect(Theme.of(context).brightness, Brightness.dark);
  });
}
