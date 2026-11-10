import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'fake_location.dart';
import 'package:uramichi/app.dart';
import 'package:uramichi/core/settings.dart';
import 'package:uramichi/core/api/uramichi_api.dart';
import 'package:uramichi/core/data/checkin_repository.dart';
import 'package:uramichi/core/models/place.dart';
import 'package:uramichi/features/checkin/badges.dart';
import 'package:uramichi/features/checkin/checkin_screen.dart';
import 'fake_account.dart';

const _place = Place(
  id: 'mock_01',
  name: '路地裏の古書喫茶',
  lat: 34.69,
  lng: 135.19,
  userRatingCount: 3,
  obscurity: 84,
  title: 'untrodden',
);

UramichiApi _fakeApi() => UramichiApi(
  baseUrl: 'http://test',
  client: MockClient((req) async {
    if (req.url.path == '/api/explore') {
      return http.Response(
        jsonEncode({
          'source': 'mock',
          'places': [_place.toJson()],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return http.Response('{}', 404);
  }),
);

void main() {
  testWidgets('ホームの地図で探した場所の詳細から、チェックインの画面を開ける', (tester) async {
    await tester.pumpWidget(
      UramichiApp(
        account: readyAccountNow(),
        api: _fakeApi(),
        checkins: LocalCheckinRepository(),
        location: FakeLocationService(),
        settings: AppSettings(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('このエリアを探す'));
    await tester.pumpAndSettle();

    expect(find.text('路地裏の古書喫茶'), findsWidgets);
    expect(find.text('ダミーデータ'), findsOneWidget);

    await tester.tap(find.text('路地裏の古書喫茶').last);
    await tester.pumpAndSettle();
    expect(find.text('ウラミチで来た人'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('detail-stamp')));
    await tester.pumpAndSettle();
    expect(find.byType(CheckinScreen), findsOneWidget);
  });

  testWidgets('アプリの言語は日本語で、Material の部品の文言も日本語になる', (tester) async {
    await tester.pumpWidget(
      UramichiApp(
        account: readyAccountNow(),
        api: _fakeApi(),
        checkins: LocalCheckinRepository(),
        location: FakeLocationService(),
        settings: AppSettings(),
      ),
    );
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(Scaffold).first);
    expect(Localizations.localeOf(context), const Locale('ja', 'JP'));
    expect(MaterialLocalizations.of(context).backButtonTooltip, '戻る');
  });

  test('チェックインの順番は同じ人なら変わらない', () async {
    final repo = LocalCheckinRepository();
    final first = await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);
    final again = await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);
    expect(first.order, 1);
    expect(first.isNew, isTrue);
    expect(again.order, 1);
    expect(again.isNew, isFalse);
    expect(await repo.visitorCount(_place.id), 1);
  });

  test('バッジ', () {
    expect(badgeForOrder(1), contains('開拓者'));
    expect(badgeForOrder(11), isNull);
  });
}
