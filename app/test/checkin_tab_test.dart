import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/features/place/place_detail_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uramichi/core/api/uramichi_api.dart';
import 'package:uramichi/core/config.dart';
import 'package:uramichi/core/data/checkin_repository.dart';
import 'package:uramichi/core/location/location_service.dart';
import 'package:uramichi/core/location/visit_recorder.dart';
import 'package:uramichi/core/models/place.dart';
import 'package:uramichi/core/services.dart';
import 'package:uramichi/core/settings.dart';
import 'package:uramichi/core/strings.dart';
import 'package:uramichi/features/checkin/checkin_tab_controller.dart';
import 'package:uramichi/features/checkin/checkin_screen.dart';
import 'package:uramichi/features/checkin/checkin_tab_screen.dart';
import 'package:uramichi/features/achievements/stamp_book.dart';
import 'package:uramichi/core/models/memory_log.dart';

import 'fake_location.dart';
import 'fake_account.dart';

const double _lat = 34.697;
const double _lng = 135.192;

Map<String, Object> _spot(String id, String name, double dLat) =>
    <String, Object>{
      'id': id,
      'name': name,
      'lat': _lat + dLat,
      'lng': _lng,
      'types': <String>[],
    };

/// 応答では遠い順に並べ、アプリが近い順に並べ直すことを確かめる
final List<Map<String, Object>> _spots = <Map<String, Object>>[
  _spot('far', '遠い神社', 0.002),
  _spot('near', '近くの祠', 0.0003),
  _spot('middle', '隣の公園', 0.001),
];

GeoSample _sample(int minutes) => GeoSample(
  lat: _lat,
  lng: _lng,
  accuracyMeters: 10,
  at: DateTime(2026, 11, 8, 12).add(Duration(minutes: minutes)),
);

class _Harness {
  _Harness({this.online = true, this.status = 200});

  bool online;
  int status;
  int exploreCalls = 0;
  final FakeLocationService location = FakeLocationService();
  final LocalCheckinRepository checkins = LocalCheckinRepository();
  late final VisitRecorder visits = VisitRecorder(location: location);
  List<Place> known = const <Place>[];
  late final UramichiApi api = UramichiApi(
    baseUrl: 'http://test',
    client: MockClient((http.Request r) async {
      if (!online) {
        throw http.ClientException('x', r.url);
      }
      exploreCalls++;
      return http.Response.bytes(
        utf8.encode(
          jsonEncode(
            status == 200
                ? <String, Object>{'source': 'places', 'places': _spots}
                : <String, Object>{
                    'error': <String, String>{
                      'code': status == 429 ? 'daily_limit' : 'internal',
                      'message': '場所を探せませんでした',
                    },
                  },
          ),
        ),
        status,
      );
    }),
  );
  late final CheckinTabController controller = CheckinTabController(
    api: api,
    location: location,
    visits: visits,
    start: const LatLng(_lat, _lng),
    knownPlaces: () => known,
  );

  void addVisit() => visits
    ..addSample(_sample(0))
    ..addSample(_sample(10));

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      Services(
        account: readyAccountNow(),
        api: api,
        checkins: checkins,
        location: location,
        visits: visits,
        settings: AppSettings(),
        config: const AppConfig(),
        child: MaterialApp(
          home: Scaffold(
            body: CheckinTabScreen(controller: controller, onShowMap: () {}),
          ),
        ),
      ),
    );
    controller.open();
    await tester.pumpAndSettle();
  }
}

Finder _visitCard(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(Card));

void main() {
  group('現在地からのチェックイン', () {
    testWidgets('開くと最も近いスポットが選ばれ、ボタンでチェックインできる', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await h.pump(tester);

      expect(_selected(h), 'near');

      await tester.tap(_hereStamp);
      await tester.pumpAndSettle();

      expect(find.byType(CheckinScreen), findsOneWidget);
      expect(await h.checkins.visitorCount('near'), 1);
    });

    testWidgets('開いただけではチェックインしない', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await h.pump(tester);

      expect(await h.checkins.visitorCount('near'), 0);
    });

    testWidgets('候補のリストから別のスポットに変更してチェックインできる', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await h.pump(tester);

      await tester.tap(find.textContaining('ちがう場所？'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(RadioListTile<String>, '隣の公園'));
      await tester.pumpAndSettle();
      expect(_selected(h), 'middle');

      await tester.tap(_hereStamp);
      await tester.pumpAndSettle();

      expect(await h.checkins.visitorCount('middle'), 1);
      expect(await h.checkins.visitorCount('near'), 0);
    });

    testWidgets('選んだスポットと候補のリストから、場所の詳細を開ける', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await h.pump(tester);

      await tester.tap(find.widgetWithText(TextButton, '詳細'));
      await tester.pumpAndSettle();
      expect(find.byType(PlaceDetailScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('ちがう場所？'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('隣の公園の詳細'));
      await tester.pumpAndSettle();
      final PlaceDetailScreen detail = tester.widget(
        find.byType(PlaceDetailScreen),
      );
      expect(detail.place.id, 'middle');
      // 詳細を開いても、チェックインするスポットは変えない
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(_selected(h), 'near');
    });

    testWidgets('位置情報を拒否されたら、許可の操作を示す', (WidgetTester tester) async {
      final _Harness h = _Harness();
      h.location.access = LocationAccess.denied;
      await h.pump(tester);

      expect(find.text('位置情報を許可'), findsOneWidget);
      expect(find.text('地図で探す'), findsOneWidget);
    });

    testWidgets('端末の設定で拒否されているときは、設定を開く操作を示す', (WidgetTester tester) async {
      final _Harness h = _Harness();
      h.location.access = LocationAccess.deniedForever;
      await h.pump(tester);

      expect(find.text('設定を開く'), findsOneWidget);
    });

    testWidgets('現在地を測定できないときは、もう一度試せる', (WidgetTester tester) async {
      final _Harness h = _Harness();
      h.location.position = null;
      await h.pump(tester);

      expect(find.text('現在地を確認できませんでした'), findsOneWidget);
      expect(find.text('もう一度試す'), findsOneWidget);
    });

    testWidgets('サーバーの処理の失敗は、圏外と区別して表示する', (WidgetTester tester) async {
      final _Harness h = _Harness(status: 500);
      await h.pump(tester);

      expect(find.text('場所を探せませんでした'), findsOneWidget);
      expect(find.text(l10n.recordHere), findsNothing);
    });
  });

  group('今日の旅', () {
    testWidgets('今日押したスタンプを並べ、前の日の記録は出さない', (WidgetTester tester) async {
      final _Harness h = _Harness();
      final DateTime now = DateTime.now();
      await h.checkins.addLog(
        MemoryLog(
          id: '',
          placeId: 'elsewhere',
          placeName: '近くの祠',
          verdict: Verdict.hit,
          rating: 5,
          createdAt: now,
          genre: 'worship',
        ),
      );
      await h.checkins.addLog(
        MemoryLog(
          id: '',
          placeId: 'old',
          placeName: '先週の喫茶店',
          verdict: Verdict.hit,
          createdAt: now.subtract(const Duration(days: 3)),
        ),
      );
      await h.pump(tester);

      expect(find.text('今日の旅'), findsOneWidget);
      expect(find.text('スタンプ 1 個'), findsOneWidget);
      expect(find.byType(StampBookStamp), findsOneWidget);
      expect(find.text('先週の喫茶店'), findsNothing);
    });

    testWidgets('押し忘れかもしれない滞在を、今日の旅の中に出す', (WidgetTester tester) async {
      final _Harness h = _Harness()..addVisit();
      await h.pump(tester);

      expect(find.textContaining('押し忘れ？'), findsOneWidget);
      expect(find.text('後から押す'), findsOneWidget);
    });

    testWidgets('今日もう押した場所は、押したスタンプを見せて重ねて押させない', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await h.checkins.addLog(
        MemoryLog(
          id: '',
          placeId: 'near',
          placeName: '近くの祠',
          verdict: Verdict.hit,
          createdAt: DateTime.now(),
        ),
      );
      await h.pump(tester);

      expect(_hereStamp, findsNothing);
      expect(
        find.byKey(const ValueKey<String>('here-stamped')),
        findsOneWidget,
      );
      expect(find.text(l10n.alreadyStampedToday), findsOneWidget);
      // ほかの場所を選べば押せる
      await tester.tap(find.textContaining('ちがう場所？'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(RadioListTile<String>, '隣の公園'));
      await tester.pumpAndSettle();
      expect(_hereStamp, findsOneWidget);
    });

    testWidgets('まだ何もなければ、上のスタンプを押すよう案内する', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await h.pump(tester);

      expect(find.text(l10n.journeyEmpty), findsOneWidget);
    });
  });

  group('圏外のとき', () {
    testWidgets('ダミーのスポットを出さず、いまの場所を記録できる', (WidgetTester tester) async {
      final _Harness h = _Harness(online: false);
      await h.pump(tester);

      expect(find.text(l10n.offline), findsOneWidget);
      expect(_hereStamp, findsNothing);

      await tester.tap(find.text(l10n.recordHere));
      await tester.pumpAndSettle();

      expect(h.visits.visits, hasLength(1));
    });

    testWidgets('探す上限に達したら、通信できないとは言わず、地図で探すよう伝える', (
      WidgetTester tester,
    ) async {
      final _Harness h = _Harness(status: 429);
      await h.pump(tester);

      expect(find.text(l10n.offline), findsNothing);
      expect(find.text('今日はこれ以上、近くのスポットを探せません'), findsOneWidget);
      expect(find.text('地図で探す'), findsOneWidget);
    });

    testWidgets('探す上限に達しても、地図で読み込んだ近くの場所にはチェックインできる', (
      WidgetTester tester,
    ) async {
      final _Harness h = _Harness(status: 429);
      h.known = <Place>[Place.fromJson(_spot('near', '近くの祠', 0.0003))];
      await h.pump(tester);

      expect(find.text('近くの祠'), findsOneWidget);
      expect(_hereStamp, findsOneWidget);
      expect(find.textContaining('オフライン'), findsNothing);
    });

    testWidgets('別の画面で読み込み済みの近くの場所は、候補に出す', (WidgetTester tester) async {
      final _Harness h = _Harness(online: false);
      h.known = <Place>[Place.fromJson(_spot('near', '近くの祠', 0.0003))];
      await h.pump(tester);

      expect(find.text('近くの祠'), findsOneWidget);
      expect(_hereStamp, findsOneWidget);
    });

    testWidgets('記録した場所は、通信できるようになるとスポットを選べる', (WidgetTester tester) async {
      final _Harness h = _Harness(online: false);
      await h.pump(tester);
      await tester.tap(find.text(l10n.recordHere));
      await tester.pumpAndSettle();

      h.online = true;
      await _tapVisible(tester, find.text('スポットを探す'));
      await tester.pumpAndSettle();

      expect(find.text('後から押す'), findsOneWidget);
      expect(_visitCard('近くの祠'), findsOneWidget);
    });
  });

  group('行ったかもしれない場所', () {
    testWidgets('滞在した場所に最も近いスポットを提案し、チェックインすると一覧から消える', (
      WidgetTester tester,
    ) async {
      final _Harness h = _Harness()..addVisit();
      await h.pump(tester);

      final Finder card = _visitCard('近くの祠');
      await _tapVisible(
        tester,
        find.descendant(of: card, matching: find.text('後から押す')),
      );
      await tester.pumpAndSettle();

      expect(await h.checkins.visitorCount('near'), 1);
      expect(h.visits.visits, isEmpty);
    });

    testWidgets('リストから別のスポットに変更してチェックインできる', (WidgetTester tester) async {
      final _Harness h = _Harness()..addVisit();
      await h.pump(tester);

      await _tapVisible(tester, find.text('場所を変更'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(RadioListTile<String>, '隣の公園').last);
      await tester.pumpAndSettle();

      final Finder card = _visitCard('隣の公園');
      await _tapVisible(
        tester,
        find.descendant(of: card, matching: find.text('後から押す')),
      );
      await tester.pumpAndSettle();

      expect(await h.checkins.visitorCount('middle'), 1);
      expect(await h.checkins.visitorCount('near'), 0);
    });

    testWidgets('今回はチェックインしないと選ぶと、チェックインせずに一覧から消える', (
      WidgetTester tester,
    ) async {
      final _Harness h = _Harness()..addVisit();
      await h.pump(tester);

      await _tapVisible(tester, find.text('チェックインしない'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('今回はチェックインしない'));
      await tester.pumpAndSettle();

      expect(h.visits.visits, isEmpty);
      expect(await h.checkins.visitorCount('near'), 0);
    });

    testWidgets('この場所を今後提案しないと選ぶと、同じ場所にいても提案しない', (WidgetTester tester) async {
      final _Harness h = _Harness()..addVisit();
      await h.pump(tester);

      await _tapVisible(tester, find.text('チェックインしない'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('この場所を今後提案しない'));
      await tester.pumpAndSettle();

      h.visits.addSample(_sample(20));
      expect(h.visits.visits, isEmpty);
    });

    testWidgets('タブを開くまでは、滞在した位置をサーバーに送らない', (WidgetTester tester) async {
      final _Harness h = _Harness();
      h.controller;
      h.addVisit();

      expect(h.exploreCalls, 0);
      expect(
        h.controller.spotsOf(h.visits.visits.single),
        isA<VisitSpotsIdle>(),
      );
    });

    testWidgets('読み込めないときも、チェックインしないを選べる', (WidgetTester tester) async {
      final _Harness h = _Harness(online: false)..addVisit();
      await h.pump(tester);

      expect(find.text('スポットを読み込めませんでした'), findsOneWidget);
      expect(find.text('チェックインしない'), findsOneWidget);
    });
  });

  group('滞在した場所を記録のスイッチ', () {
    testWidgets('確認してから記録を始める', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await h.pump(tester);

      await _tapVisible(tester, find.byType(Switch));
      await tester.pumpAndSettle();
      expect(h.visits.enabled, isFalse);

      await tester.tap(find.text('記録する'));
      await tester.pumpAndSettle();
      expect(h.visits.enabled, isTrue);
    });

    testWidgets('確認で断ると記録しない', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await h.pump(tester);

      await _tapVisible(tester, find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('記録しない'));
      await tester.pumpAndSettle();

      expect(h.visits.enabled, isFalse);
    });

    testWidgets('記録できない端末では表示しない', (WidgetTester tester) async {
      final _Harness h = _Harness();
      h.location.canTrack = false;
      await h.pump(tester);

      expect(find.byType(Switch), findsNothing);
    });
  });
}

String? _selected(_Harness h) => switch (h.controller.state) {
  NearbyLoaded(:final String selectedId) => selectedId,
  _ => null,
};

/// 「いまここ」の押してスタンプ
final Finder _hereStamp = find.byKey(const ValueKey<String>('here-stamp'));

/// 画面の外にあるかもしれない部品を見える位置まで動かしてから押す
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}
