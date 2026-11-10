import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uramichi/core/api/uramichi_api.dart';
import 'package:uramichi/core/models/assistant_answer.dart';
import 'package:uramichi/core/models/memory_log.dart';
import 'package:uramichi/core/models/place_genre.dart';
import 'package:uramichi/features/achievements/achievements.dart';
import 'package:uramichi/features/assistant/assistant_controller.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

const Map<String, Object?> _answer = <String, Object?>{
  'source': 'gemini',
  'placesSource': 'google',
  'intent': 'alternatives',
  'reply': '清水寺の代わりを選びました',
  'center': <String, Object>{'name': '清水寺', 'lat': 34.99, 'lng': 135.78},
  'search': <String, Object>{
    'genres': <String>['worship', 'unknown'],
    'query': '清水寺',
  },
  'suggestions': <Object>[
    <String, Object>{
      'place': <String, Object>{
        'id': 'p1',
        'name': '小さな寺',
        'lat': 34.99,
        'lng': 135.78,
        'types': <String>['buddhist_temple'],
        'userRatingCount': 12,
        'title': 'hidden',
        'distanceMeters': 420,
      },
      'reason': '口コミが12件の静かなお寺です',
    },
  ],
};

void main() {
  test('見つかった場所を読み、形の違う値があっても答えの残りは読む', () {
    final AssistantAnswer a = AssistantAnswer.fromJson(<String, dynamic>{
      'reply': '近くの「駅」を1件見つけました。',
      'intent': 'recommend',
      'center': <String, dynamic>{'name': '中央駅', 'lat': null, 'lng': 135},
      'targets': <Object?>[
        <String, dynamic>{
          'id': 'st',
          'name': '中央駅',
          'lat': 35.0,
          'lng': 135.0,
          'types': <String>['train_station'],
        },
        null,
      ],
      'suggestions': <Object?>[
        null,
        <String, dynamic>{'place': null, 'reason': 'x'},
        <String, dynamic>{
          'place': <String, dynamic>{
            'id': 'h',
            'name': '駅裏の祠',
            'lat': 35.001,
            'lng': 135.0,
            'types': <String>[],
          },
          'reason': '口コミの少ない祠です',
        },
      ],
    });
    expect(a.targets.single.name, '中央駅');
    expect(a.suggestions.single.place.name, '駅裏の祠');
    // 位置の欠けた中心は使わない
    expect(a.center, isNull);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  group('Geminiちゃんの API', () {
    test('答えの JSON を読む。知らないジャンルは読み飛ばす', () {
      final AssistantAnswer a = AssistantAnswer.fromJson(_answer);
      expect(a.byGemini, isTrue);
      expect(a.isMock, isFalse);
      expect(a.intent, AssistantIntent.alternatives);
      expect(a.center!.name, '清水寺');
      expect(a.genres, <PlaceGenre>{PlaceGenre.worship});
      expect(a.query, '清水寺');
      expect(a.suggestions.single.place.distanceMeters, 420);
      expect(a.suggestions.single.reason, contains('12件'));
      expect(
        AssistantAnswer.fromJson(<String, Object>{
          'source': 'fake',
          'intent': 'dance',
          'reply': 'x',
        }).intent,
        AssistantIntent.chat,
      );
    });

    test('一言、地図の中心、直前のやり取りをトークン付きで送る', () async {
      late http.Request sent;
      final UramichiApi api = UramichiApi(
        baseUrl: 'http://test',
        idToken: () async => 'token',
        client: MockClient((http.Request r) async {
          sent = r;
          return _json(_answer);
        }),
      );
      await api.askAssistant(
        '清水寺の代わり',
        lat: 1,
        lng: 2,
        history: const <AssistantTurn>[
          AssistantTurn.user('こんにちは'),
          AssistantTurn.assistant('どうぞ'),
        ],
      );
      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/assistant');
      expect(sent.headers['Authorization'], 'Bearer token');
      expect(jsonDecode(sent.body), <String, Object>{
        'message': '清水寺の代わり',
        'lat': 1.0,
        'lng': 2.0,
        'history': <Object>[
          <String, String>{'role': 'user', 'text': 'こんにちは'},
          <String, String>{'role': 'assistant', 'text': 'どうぞ'},
        ],
      });
    });

    test('サーバーに接続できないときは、ダミーの場所を答えずに失敗を伝える', () async {
      final UramichiApi api = UramichiApi(
        baseUrl: 'http://test',
        idToken: () async => 'token',
        client: MockClient(
          (http.Request r) async => throw http.ClientException('圏外', r.url),
        ),
      );
      await expectLater(
        api.askAssistant('穴場', lat: 34.693, lng: 135.19),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('入力の誤り（400）はダミーに置き換えずに伝える', () async {
      final UramichiApi api = UramichiApi(
        baseUrl: 'http://test',
        idToken: () async => 'token',
        client: MockClient(
          (http.Request r) async => _json(<String, Object>{
            'error': <String, String>{
              'code': 'bad_request',
              'message': '200文字以内で話しかけてください',
            },
          }, 400),
        ),
      );
      final AssistantController c = AssistantController(api: api);
      await c.ask('長い');
      expect(c.error, '200文字以内で話しかけてください');
      expect(c.answer, isNull);
    });
  });

  test('直前のやり取りは新しいものから6件だけ送る', () async {
    final List<List<Object?>> histories = <List<Object?>>[];
    final UramichiApi api = UramichiApi(
      baseUrl: 'http://test',
      idToken: () async => 'token',
      client: MockClient((http.Request r) async {
        histories.add(
          (jsonDecode(r.body) as Map<String, dynamic>)['history']
              as List<Object?>,
        );
        return _json(_answer);
      }),
    );
    final AssistantController c = AssistantController(api: api);
    for (int i = 0; i < 5; i++) {
      await c.ask('質問$i');
    }
    expect(histories.first, isEmpty);
    expect(histories[1], hasLength(2));
    expect(histories.last, hasLength(AssistantController.maxHistory));
    expect((histories.last.first! as Map)['text'], '質問1');
    expect(c.message, '質問4');
    expect(c.answer!.reply, '清水寺の代わりを選びました');

    c.reset();
    expect(c.answer, isNull);
    await c.ask('もう一度');
    expect(histories.last, isEmpty);
  });

  group('実績', () {
    MemoryLog log(
      String placeId,
      int day, {
      Verdict verdict = Verdict.hit,
      int? order,
      bool isPublic = false,
    }) => MemoryLog(
      id: '$placeId-$day',
      placeId: placeId,
      placeName: placeId,
      verdict: verdict,
      createdAt: DateTime(2026, 11, day),
      order: order,
      isPublic: isPublic,
    );

    test('記録がなければどれも解除しない', () {
      final List<AchievementProgress> list = computeAchievements(
        const <MemoryLog>[],
      );
      expect(list, hasLength(achievementDefinitions.length));
      expect(list.any((AchievementProgress a) => a.unlocked), isFalse);
    });

    test('日時の順に数え、条件を満たした記録の日時を解除の日時にする', () {
      final Map<String, AchievementProgress> got =
          <String, AchievementProgress>{
            for (final AchievementProgress a in computeAchievements(<MemoryLog>[
              log('c', 5, order: 5, isPublic: true),
              log('b', 4, order: 30),
              log('a', 3, verdict: Verdict.miss, order: 2),
              log('a', 2, order: 2),
              log('d', 6, order: 1),
              log('e', 7), // 送信前でまだ順番がない
            ]))
              a.definition.id: a,
          };
      void check(String id, int progress, int? day) {
        final AchievementProgress a = got[id]!;
        expect(a.progress, progress, reason: id);
        expect(
          a.unlockedAt,
          day == null ? isNull : DateTime(2026, 11, day),
          reason: id,
        );
      }

      check('first_log', 1, 2);
      check('pioneer', 1, 6);
      check('veteran', 3, 6);
      check('honor_miss', 1, 3);
      check('connoisseur', 5, 7);
      check('wanderer', 5, 7);
      check('regular', 6, null);
      check('storyteller', 1, null);
    });
  });
}
