import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uramichi/core/api/uramichi_api.dart';
import 'package:uramichi/core/data/checkin_repository.dart';
import 'package:uramichi/core/location/background_samples.dart';
import 'package:uramichi/core/location/location_service.dart';
import 'package:uramichi/core/models/memory_log.dart';
import 'package:uramichi/core/models/timeline_entry.dart';
import 'package:uramichi/core/notifications.dart';
import 'package:uramichi/core/widgets/log_photo.dart';
import 'package:uramichi/core/widgets/stamp_celebration.dart';
import 'package:uramichi/features/achievements/stamp_book.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

TimelineEntry _entry({bool mine = false}) => TimelineEntry(
  id: 'tl_1',
  author: 'A1',
  mine: mine,
  placeId: 'place_01',
  placeName: '坂の上の小さな祠',
  verdict: Verdict.hit,
  createdAt: DateTime(2026, 11, 8),
  wantCount: 2,
  helpfulCount: 1,
);

void main() {
  group('記録のジャンル・写真・反応', () {
    test('記録はジャンルと写真の ID を送り、反応の数を読む', () {
      final MemoryLog log = MemoryLog.fromJson('lg_1', <String, dynamic>{
        'placeId': 'place_01',
        'verdict': 'hit',
        'createdAt': '2026-11-08T03:00:00Z',
        'genre': 'worship',
        'photoId': 'ph_abc',
        'wantCount': 3,
        'helpfulCount': 1,
      });
      expect(log.genre, 'worship');
      expect(log.photoId, 'ph_abc');
      expect(log.wantCount, 3);
      expect(log.toJson()['genre'], 'worship');
      expect(log.toJson()['photoId'], 'ph_abc');
      // 直しても、ジャンル・写真・反応の数は残る
      final MemoryLog edited = log.copyWith(rating: 2, comment: 'また来たい');
      expect(edited.genre, 'worship');
      expect(edited.photoId, 'ph_abc');
      expect(edited.helpfulCount, 1);
    });

    test('空のジャンルと写真は null として読む', () {
      final TimelineEntry e = TimelineEntry.fromJson(<String, dynamic>{
        'id': 'tl_1',
        'placeId': 'place_01',
        'genre': '',
        'photoId': '',
        'myWant': true,
      });
      expect(e.genre, isNull);
      expect(e.photoId, isNull);
      expect(e.myWant, isTrue);
    });

    test('反応を付け外しすると、数が1つずつ増減する', () {
      final TimelineEntry on = _entry().withReaction(
        ReactionKind.want,
        on: true,
      );
      expect(on.wantCount, 3);
      expect(on.myWant, isTrue);
      expect(on.helpfulCount, 1);
      // 付けた反応を2回付けても増えない
      expect(on.withReaction(ReactionKind.want, on: true).wantCount, 3);
      final TimelineEntry off = on.withReaction(ReactionKind.want, on: false);
      expect(off.wantCount, 2);
      expect(off.myWant, isFalse);
    });

    test('反応は PUT で付け、DELETE で外し、サーバーの数を使う', () async {
      final List<String> calls = <String>[];
      final UramichiApi api = UramichiApi(
        baseUrl: 'http://test',
        client: MockClient((http.Request r) async {
          calls.add('${r.method} ${r.url.path}');
          return _json(<String, Object>{
            'wantCount': 7,
            'helpfulCount': 1,
            'myWant': r.method == 'PUT',
            'myHelpful': false,
          });
        }),
      );
      final TimelineEntry after = await api.react(
        _entry(),
        ReactionKind.want,
        on: true,
        idToken: 't',
      );
      expect(after.wantCount, 7);
      expect(after.myWant, isTrue);
      await api.react(after, ReactionKind.want, on: false, idToken: 't');
      expect(calls, <String>[
        'PUT /api/timeline/tl_1/reactions/want',
        'DELETE /api/timeline/tl_1/reactions/want',
      ]);
    });

    test('写真は中身をそのまま送り、一度読んだ写真は読み直さない', () async {
      int reads = 0;
      final UramichiApi api = UramichiApi(
        baseUrl: 'http://test',
        client: MockClient((http.Request r) async {
          if (r.method == 'POST') {
            expect(r.headers['Content-Type'], 'image/jpeg');
            expect(r.headers['Authorization'], 'Bearer t');
            expect(r.bodyBytes, <int>[0xFF, 0xD8, 0xFF, 1]);
            return _json(<String, Object>{'id': 'ph_1'}, 201);
          }
          reads++;
          return http.Response.bytes(<int>[1, 2, 3], 200);
        }),
      );
      final String id = await api.uploadPhoto(
        Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 1]),
        contentType: 'image/jpeg',
        idToken: 't',
      );
      expect(id, 'ph_1');
      expect(await api.fetchPhoto(id, idToken: 't'), <int>[1, 2, 3]);
      await api.fetchPhoto(id, idToken: 't');
      expect(reads, 1);
    });

    test('端末だけで動くときも、反応と写真を手元で扱える', () async {
      final LocalCheckinRepository repo = LocalCheckinRepository();
      final List<TimelineEntry> before = await repo.nearbyTimeline(
        lat: 0,
        lng: 0,
      );
      final TimelineEntry sample = before.firstWhere(
        (TimelineEntry e) => e.isMock,
      );
      await repo.react(sample, ReactionKind.helpful, on: true);
      final List<TimelineEntry> after = await repo.nearbyTimeline(
        lat: 0,
        lng: 0,
      );
      expect(
        after.firstWhere((TimelineEntry e) => e.id == sample.id).myHelpful,
        isTrue,
      );
      final String id = await repo.uploadPhoto(
        Uint8List.fromList(<int>[1, 2]),
        contentType: 'image/png',
      );
      expect(await repo.photo(id), <int>[1, 2]);
    });

    test('写真の種類は中身の先頭のバイトで決める', () {
      expect(
        PickedPhoto.typeOf(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0])),
        'image/jpeg',
      );
      expect(
        PickedPhoto.typeOf(
          Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 13, 10, 26, 10]),
        ),
        'image/png',
      );
      expect(PickedPhoto.typeOf(Uint8List.fromList(<int>[1, 2, 3])), isNull);
    });
  });

  group('スタンプ帳', () {
    test('記録のジャンルからスタンプの種類を決め、ジャンルのない記録は無地にする', () {
      MemoryLog log(String? genre) => MemoryLog(
        id: 'x',
        placeId: 'p',
        placeName: '',
        verdict: Verdict.hit,
        createdAt: DateTime(2026),
        genre: genre,
      );
      expect(stampDesignOf(log('food')), StampDesign.food);
      expect(stampDesignOf(log('worship')), StampDesign.worship);
      expect(stampDesignOf(log('other')), StampDesign.plain);
      expect(stampDesignOf(log(null)), StampDesign.plain);
    });
  });

  group('通知', () {
    test('反応の数は、前に数えたときより増えた分だけを返す', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      // はじめて数えたときは、これまでの反応を新しい反応として知らせない
      expect(await AppNotifications.takeNewReactions(prefs, 5), 0);
      expect(await AppNotifications.takeNewReactions(prefs, 8), 3);
      expect(await AppNotifications.takeNewReactions(prefs, 8), 0);
      // 外された反応は知らせない
      expect(await AppNotifications.takeNewReactions(prefs, 6), 0);
      expect(await AppNotifications.takeNewReactions(prefs, 7), 1);
    });

    test('最後の測定まで同じ場所にいるときだけ、滞在が続いていると判定する', () {
      final DateTime t = DateTime(2026, 11, 10, 10);
      GeoSample at(int minutes, double lat) => GeoSample(
        lat: lat,
        lng: 135,
        accuracyMeters: 10,
        at: t.add(Duration(minutes: minutes)),
      );
      expect(
        currentBackgroundStay(<GeoSample>[at(0, 35), at(15, 35)]),
        isNotNull,
      );
      // 立ち去った後は知らせない
      expect(
        currentBackgroundStay(<GeoSample>[at(0, 35), at(15, 35), at(30, 35.1)]),
        isNull,
      );
      expect(currentBackgroundStay(<GeoSample>[at(0, 35)]), isNull);
      expect(currentBackgroundStay(const <GeoSample>[]), isNull);
    });
  });
}
