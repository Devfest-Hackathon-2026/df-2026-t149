import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uramichi/core/api/uramichi_api.dart';
import 'package:uramichi/core/data/api_checkin_repository.dart';
import 'package:uramichi/core/data/checkin_repository.dart';
import 'package:uramichi/core/models/memory_log.dart';
import 'package:uramichi/core/models/place.dart';

const Place _place = Place(
  id: 'place_01',
  name: '坂の上の小さな祠',
  lat: 34.697,
  lng: 135.192,
  userRatingCount: 0,
);

MemoryLog _log({Verdict verdict = Verdict.miss}) => MemoryLog(
  id: '',
  placeId: _place.id,
  placeName: _place.name,
  verdict: verdict,
  comment: '閉まってた',
  order: 1,
  createdAt: DateTime(2026, 11, 8, 12, 12, 45),
);

http.Response _json(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

http.Response _error(int status, String code, String message) =>
    _json(<String, Object>{
      'error': <String, String>{'code': code, 'message': message},
    }, status);

Map<String, Object> _serverLog(String id, String createdAt) => <String, Object>{
  'id': id,
  'placeId': 'place_01',
  'placeName': '坂の上の小さな祠',
  'verdict': 'miss',
  'comment': '閉まってた',
  'order': 1,
  'createdAt': createdAt,
};

ApiCheckinRepository _repo(
  Future<http.Response> Function(http.Request) handler, {
  bool mockOnly = false,
}) => ApiCheckinRepository(
  api: UramichiApi(
    baseUrl: mockOnly ? null : 'http://test',
    client: MockClient(handler),
  ),
  uid: 'u1',
  idTokenFor: (String _) async => 'token-1',
);

/// 保存の結果を [onSet] で決められる端末の保存先
class _FakePrefs extends Fake implements SharedPreferences {
  _FakePrefs(this.onSet);

  final Future<bool> Function() onSet;

  @override
  String? getString(String key) => null;

  @override
  Future<bool> setString(String key, String value) => onSet();

  @override
  Future<bool> remove(String key) async => true;
}

const Place _mockPlace = Place(
  id: 'mock_01',
  name: 'ダミーの祠',
  lat: 34.697,
  lng: 135.192,
);

void main() {
  group('Places API の内容を保存しない', () {
    test('思い出ログをサーバーへ送るときに場所の名前を含めない', () async {
      late Map<String, dynamic> body;
      final ApiCheckinRepository repo = _repo((http.Request r) async {
        body = jsonDecode(r.body) as Map<String, dynamic>;
        return _json(_serverLog('lg_1', '2026-11-08T03:12:45Z'), 201);
      });

      await repo.addLog(_log());

      expect(body.containsKey('placeName'), isFalse);
      expect(body['placeId'], 'place_01');
    });

    test('最後に読めた一覧を端末に保存するときに場所の名前を含めない', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ApiCheckinRepository repo = ApiCheckinRepository(
        api: UramichiApi(
          baseUrl: 'http://test',
          client: MockClient(
            (http.Request _) async => _json(<String, Object>{
              'logs': <Object>[_serverLog('lg_1', '2026-11-08T03:12:45Z')],
            }, 200),
          ),
        ),
        uid: 'u1',
        idTokenFor: (String _) async => 'token-1',
        prefs: prefs,
      );

      final List<MemoryLog> logs = await repo.watchLogs().first;
      await pumpEventQueue();

      expect(logs.single.placeName, '坂の上の小さな祠');
      expect(prefs.getString('cachedLogs.u1'), isNot(contains('坂の上の小さな祠')));
    });
  });

  group('ダミーの場所', () {
    late List<http.Request> sent;

    ApiCheckinRepository live() {
      sent = <http.Request>[];
      return ApiCheckinRepository(
        api: UramichiApi(
          baseUrl: 'http://test',
          client: MockClient((http.Request r) async {
            sent.add(r);
            return _json(<String, Object>{'logs': <Object>[]}, 200);
          }),
        ),
        uid: 'u1',
        idTokenFor: (String _) async => 'token-1',
      );
    }

    test('API の接続先が有効でも、チェックインをサーバーへ送らない', () async {
      final ApiCheckinRepository repo = live();

      final CheckinResult result = await repo.checkIn(
        _mockPlace,
        lat: 0,
        lng: 0,
      );

      expect(result.order, 1);
      expect(sent, isEmpty);
      expect(repo.pendingCount.value, 0);
    });

    test('訪問者数はサーバーに問い合わせず、端末の値を返す', () async {
      final ApiCheckinRepository repo = live();
      await repo.checkIn(_mockPlace, lat: 0, lng: 0);

      expect(await repo.visitorCount(_mockPlace.id), 1);
      expect(sent, isEmpty);
    });

    test('思い出ログはサーバーへ送らず、一覧には表示する', () async {
      final ApiCheckinRepository repo = live();
      await repo.checkIn(_mockPlace, lat: 0, lng: 0);

      await repo.addLog(
        MemoryLog(
          id: '',
          placeId: _mockPlace.id,
          placeName: _mockPlace.name,
          verdict: Verdict.hit,
          createdAt: DateTime(2026, 11, 8),
        ),
      );

      expect(sent, isEmpty);
      final List<MemoryLog> logs = await repo.watchLogs().first;
      expect(logs.single.placeName, 'ダミーの祠');
    });
  });

  group('端末への保存の結果', () {
    ApiCheckinRepository offline(Future<bool> Function() onSet) =>
        ApiCheckinRepository(
          api: UramichiApi(
            baseUrl: 'http://test',
            client: MockClient(
              (http.Request _) async => throw http.ClientException('圏外'),
            ),
          ),
          uid: 'u1',
          idTokenFor: (String _) async => 'token-1',
          prefs: _FakePrefs(onSet),
        );

    test('チェックインは端末への保存が終わるまで結果を返さない', () async {
      final Completer<bool> saving = Completer<bool>();
      bool finished = false;
      final Future<void> checkIn = offline(() => saving.future)
          .checkIn(_place, lat: _place.lat, lng: _place.lng)
          .then((CheckinResult _) => finished = true);

      await pumpEventQueue();
      expect(finished, isFalse);
      saving.complete(true);
      await checkIn;
      expect(finished, isTrue);
    });

    test('思い出ログは端末への保存が終わるまで完了しない', () async {
      final Completer<bool> saving = Completer<bool>();
      bool finished = false;
      final Future<void> addLog = offline(
        () => saving.future,
      ).addLog(_log()).then((void _) => finished = true);

      await pumpEventQueue();
      expect(finished, isFalse);
      saving.complete(true);
      await addLog;
      expect(finished, isTrue);
    });

    for (final (String name, Future<bool> Function() onSet)
        in <(String, Future<bool> Function())>[
          ('false を返す', () async => false),
          ('例外を投げる', () async => throw StateError('書き込めません')),
        ]) {
      test('保存が$nameときは失敗を伝え、未送信の件数に含めない', () async {
        final ApiCheckinRepository repo = offline(onSet);

        await expectLater(
          repo.checkIn(_place, lat: _place.lat, lng: _place.lng),
          throwsA(isA<LocalSaveException>()),
        );
        expect(repo.pendingCount.value, 0);

        await expectLater(
          repo.addLog(_log()),
          throwsA(isA<LocalSaveException>()),
        );
        expect(repo.pendingCount.value, 0);
      });
    }

    test('送信後に端末へ書き込めなくても、送信済みの記録は成功として扱う', () async {
      int setCalls = 0;
      bool online = false;
      final ApiCheckinRepository repo = ApiCheckinRepository(
        api: UramichiApi(
          baseUrl: 'http://test',
          client: MockClient((http.Request _) async {
            if (!online) {
              throw http.ClientException('圏外');
            }
            return _json(<String, Object>{'order': 1, 'isNew': true}, 200);
          }),
        ),
        uid: 'u1',
        idTokenFor: (String _) async => 'token-1',
        prefs: _FakePrefs(() async => ++setCalls == 1),
      );
      await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);
      online = true;

      final SyncReport report = await repo.sync();

      expect(report.checkins.single.order, 1);
      expect(repo.pendingCount.value, 0);
    });
  });

  group('チェックイン', () {
    test('POST /api/checkins に IDトークンと placeId を送り、順番を受け取る', () async {
      late http.Request sent;
      final ApiCheckinRepository repo = _repo((http.Request r) async {
        sent = r;
        return _json(<String, Object>{'order': 3, 'isNew': true}, 200);
      });

      final CheckinResult result = await repo.checkIn(
        _place,
        lat: _place.lat,
        lng: _place.lng,
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/checkins');
      expect(sent.headers['Authorization'], 'Bearer token-1');
      final Map<String, dynamic> body =
          jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['placeId'], 'place_01');
      expect(DateTime.parse(body['visitedAt'] as String), isA<DateTime>());
      expect(result.order, 3);
      expect(result.isNew, isTrue);
    });

    test('2回目の応答は isNew が false の結果になる', () async {
      final ApiCheckinRepository repo = _repo(
        (http.Request _) async =>
            _json(<String, Object>{'order': 1, 'isNew': false}, 200),
      );

      final CheckinResult result = await repo.checkIn(
        _place,
        lat: _place.lat,
        lng: _place.lng,
      );

      expect(result.order, 1);
      expect(result.isNew, isFalse);
    });

    test('401 はダミーに切り替えず、サーバーの文面を伝える', () async {
      final ApiCheckinRepository repo = _repo(
        (http.Request _) async =>
            _error(401, 'unauthenticated', 'ログインしてからやり直してください'),
      );

      await expectLater(
        repo.checkIn(_place, lat: _place.lat, lng: _place.lng),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.status, 'status', 401)
              .having(
                (ApiException e) => e.message,
                'message',
                'ログインしてからやり直してください',
              ),
        ),
      );
    });
  });

  group('訪問者数', () {
    test('GET /api/places/{placeId}/visitors を IDトークンを付けて呼ぶ', () async {
      late http.Request sent;
      final ApiCheckinRepository repo = _repo((http.Request r) async {
        sent = r;
        return _json(<String, int>{'visitorCount': 3}, 200);
      });

      expect(await repo.visitorCount('place_01'), 3);
      expect(sent.method, 'GET');
      expect(sent.url.path, '/api/places/place_01/visitors');
      expect(sent.url.hasQuery, isFalse);
      expect(sent.headers['Authorization'], 'Bearer token-1');
    });

    test('place ID に含まれる記号はパスの1区間として送る', () async {
      late http.Request sent;
      final ApiCheckinRepository repo = _repo((http.Request r) async {
        sent = r;
        return _json(<String, int>{'visitorCount': 0}, 200);
      });

      await repo.visitorCount('a/b');

      expect(sent.url.pathSegments, <String>[
        'api',
        'places',
        'a/b',
        'visitors',
      ]);
    });
  });

  group('思い出ログ', () {
    test('POST /api/logs の 201 を成功として扱い、IDトークンを付けて送る', () async {
      late http.Request sent;
      final ApiCheckinRepository repo = _repo((http.Request r) async {
        sent = r;
        return _json(_serverLog('lg_1', '2026-11-08T03:12:45Z'), 201);
      });

      await repo.addLog(_log());

      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/logs');
      expect(sent.headers['Authorization'], 'Bearer token-1');
      final Map<String, dynamic> body =
          jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['placeId'], 'place_01');
      expect(body['verdict'], 'miss');
      expect(body['comment'], '閉まってた');
    });

    test('チェックインしていない場所の 400 は、サーバーの文面を伝える', () async {
      final ApiCheckinRepository repo = _repo(
        (http.Request _) async =>
            _error(400, 'not_checked_in', '先にこの場所にチェックインしてください'),
      );

      await expectLater(
        repo.addLog(_log()),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.code,
            'code',
            'not_checked_in',
          ),
        ),
      );
    });

    test('GET /api/logs の一覧を、サーバーの順番と ID のまま読む', () async {
      late http.Request sent;
      final ApiCheckinRepository repo = _repo((http.Request r) async {
        sent = r;
        return _json(<String, Object>{
          'logs': <Object>[
            _serverLog('lg_2', '2026-11-08T03:12:45Z'),
            _serverLog('lg_1', '2026-11-07T03:12:45Z'),
          ],
        }, 200);
      });

      final List<MemoryLog> logs = await repo.watchLogs().first;

      expect(sent.url.path, '/api/logs');
      expect(sent.headers['Authorization'], 'Bearer token-1');
      expect(logs.map((MemoryLog l) => l.id), <String>['lg_2', 'lg_1']);
      expect(logs.first.verdict, Verdict.miss);
      expect(logs.first.order, 1);
    });

    test('UTC で返る日時は、端末の時刻として読む', () async {
      final ApiCheckinRepository repo = _repo(
        (http.Request _) async => _json(<String, Object>{
          'logs': <Object>[_serverLog('lg_1', '2026-11-08T23:30:00Z')],
        }, 200),
      );

      final DateTime createdAt =
          (await repo.watchLogs().first).single.createdAt;

      expect(createdAt.isUtc, isFalse);
      expect(createdAt, DateTime.utc(2026, 11, 8, 23, 30).toLocal());
    });

    test('ログを残すと、購読中の一覧を読み直す', () async {
      final List<Object> stored = <Object>[];
      final ApiCheckinRepository repo = _repo((http.Request r) async {
        if (r.method == 'POST') {
          stored.insert(0, _serverLog('lg_1', '2026-11-08T03:12:45Z'));
          return _json(stored.first, 201);
        }
        return _json(<String, Object>{'logs': stored}, 200);
      });

      final StreamIterator<List<MemoryLog>> logs =
          StreamIterator<List<MemoryLog>>(repo.watchLogs());
      expect(await logs.moveNext(), isTrue);
      expect(logs.current, isEmpty);

      await repo.addLog(_log());

      expect(await logs.moveNext(), isTrue);
      expect(logs.current.single.id, 'lg_1');
      await logs.cancel();
    });
  });

  group('API サーバーを使わない設定のとき', () {
    test('接続先のない開発用のビルドでは、API サーバーを呼ばない', () async {
      final List<Uri> calls = <Uri>[];
      final ApiCheckinRepository repo = _repo((http.Request r) async {
        calls.add(r.url);
        return _json(<String, Object>{'order': 9, 'isNew': true}, 200);
      }, mockOnly: true);

      final CheckinResult result = await repo.checkIn(
        _place,
        lat: _place.lat,
        lng: _place.lng,
      );

      expect(result.order, 1);
      expect(calls, isEmpty);
    });

    test('接続先がないときは、IDトークンを取得せずに端末へ保存する', () async {
      bool tokenRequested = false;
      final ApiCheckinRepository repo = ApiCheckinRepository(
        api: UramichiApi(baseUrl: null),
        uid: 'u1',
        idTokenFor: (String _) async {
          tokenRequested = true;
          return 'token-1';
        },
      );

      expect(
        (await repo.checkIn(_place, lat: _place.lat, lng: _place.lng)).order,
        1,
      );
      expect(tokenRequested, isFalse);
    });
  });

  group('通信できないとき', () {
    late bool online;
    late List<http.Request> sent;
    late SharedPreferences prefs;

    ApiCheckinRepository offlineRepo({
      Future<http.Response> Function(http.Request)? handler,
    }) => ApiCheckinRepository(
      api: UramichiApi(
        baseUrl: 'http://test',
        client: MockClient((http.Request r) async {
          if (!online) {
            throw http.ClientException('x', r.url);
          }
          sent.add(r);
          if (handler != null) {
            return handler(r);
          }
          return r.url.path == '/api/checkins'
              ? _json(<String, Object>{'order': 4, 'isNew': true}, 200)
              : _json(_serverLog('lg_1', '2026-11-08T03:12:45Z'), 201);
        }),
      ),
      uid: 'u1',
      idTokenFor: (String _) async => 'token-1',
      prefs: prefs,
    );

    setUp(() async {
      online = false;
      sent = <http.Request>[];
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
    });

    test('圏外で保存したチェックインは、再起動後も位置を付けて送る', () async {
      await offlineRepo().checkIn(_place, lat: 34.5, lng: 135.5);

      online = true;
      await offlineRepo().sync();

      final Map<String, dynamic> body =
          jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body['lat'], 34.5);
      expect(body['lng'], 135.5);
    });

    test('チェックインを端末に保存し、順番のない結果を返す', () async {
      final ApiCheckinRepository repo = offlineRepo();

      final CheckinResult result = await repo.checkIn(
        _place,
        lat: _place.lat,
        lng: _place.lng,
      );

      expect(result.isPending, isTrue);
      expect(result.order, isNull);
      expect(repo.pendingCount.value, 1);
    });

    test('同じ場所のチェックインは 1 件だけ保存する', () async {
      final ApiCheckinRepository repo = offlineRepo();

      await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);
      await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);

      expect(repo.pendingCount.value, 1);
    });

    test('アプリを開き直しても保存した記録が残り、通信できるようになると記録した順に送る', () async {
      final ApiCheckinRepository before = offlineRepo();
      await before.checkIn(_place, lat: _place.lat, lng: _place.lng);
      await before.addLog(_log());

      final ApiCheckinRepository after = offlineRepo();
      expect(after.pendingCount.value, 2);
      online = true;
      final SyncReport report = await after.sync();

      expect(sent.map((http.Request r) => r.url.path), <String>[
        '/api/checkins',
        '/api/logs',
      ]);
      expect(report.checkins.single.order, 4);
      expect(report.checkins.single.placeName, _place.name);
      expect(after.pendingCount.value, 0);
      expect(offlineRepo().pendingCount.value, 0);
    });

    test('送る前の記録を直すと、直した内容で送る', () async {
      final ApiCheckinRepository repo = offlineRepo();
      await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);
      await repo.addLog(_log());
      final MemoryLog pending = (await repo.watchLogs().first).firstWhere(
        (MemoryLog l) => l.isPending,
      );

      await repo.editLog(pending, rating: 2, comment: '直した');
      online = true;
      await repo.sync();

      final Map<String, dynamic> body =
          jsonDecode(sent.last.body) as Map<String, dynamic>;
      expect(sent.last.url.path, '/api/logs');
      expect(body['rating'], 2);
      expect(body['comment'], '直した');
    });

    test('公開の記録を送る前に自分だけにしてから直しても、自分だけのまま送る', () async {
      final ApiCheckinRepository repo = offlineRepo();
      await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);
      await repo.addLog(_log().copyWith(isPublic: true));
      // 画面は読み込んだ時点の記録を持ったまま、公開状態と中身を別々に変える
      final MemoryLog shown = (await repo.watchLogs().first).firstWhere(
        (MemoryLog l) => l.isPending,
      );

      await repo.setLogPublic(shown, isPublic: false);
      final MemoryLog edited = await repo.editLog(
        shown,
        rating: 4,
        comment: '直した',
      );
      online = true;
      await repo.sync();

      final Map<String, dynamic> body =
          jsonDecode(sent.last.body) as Map<String, dynamic>;
      expect(body['public'], isFalse);
      expect(body['rating'], 4);
      expect(edited.isPublic, isFalse);
    });

    test('送る前の記録を直してから公開状態を変えても、直した中身のまま送る', () async {
      final ApiCheckinRepository repo = offlineRepo();
      await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);
      await repo.addLog(_log());
      final MemoryLog shown = (await repo.watchLogs().first).firstWhere(
        (MemoryLog l) => l.isPending,
      );

      await repo.editLog(shown, rating: 5, comment: '直した');
      await repo.setLogPublic(shown, isPublic: true);
      online = true;
      await repo.sync();

      final Map<String, dynamic> body =
          jsonDecode(sent.last.body) as Map<String, dynamic>;
      expect(body['public'], isTrue);
      expect(body['rating'], 5);
      expect(body['comment'], '直した');
    });

    test('直している間に送り終えていたら、サーバーの記録を直す', () async {
      final ApiCheckinRepository repo = offlineRepo();
      await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);
      await repo.addLog(_log());
      final MemoryLog pending = (await repo.watchLogs().first).firstWhere(
        (MemoryLog l) => l.isPending,
      );
      online = true;
      await repo.sync();

      final MemoryLog edited = await repo.editLog(
        pending,
        rating: 3,
        comment: '',
      );

      expect(sent.last.method, 'PATCH');
      expect(sent.last.url.path, '/api/logs/lg_${pending.clientId}');
      expect(edited.id, 'lg_${pending.clientId}');
    });

    test('通信できないままなら記録を残す', () async {
      final ApiCheckinRepository repo = offlineRepo();
      await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);

      final SyncReport report = await repo.sync();

      expect(report.checkins, isEmpty);
      expect(repo.pendingCount.value, 1);
    });

    test('未送信のチェックインがあるときの思い出ログは、チェックインの後に送る', () async {
      final ApiCheckinRepository repo = offlineRepo();
      await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);
      online = true;

      await repo.addLog(_log());

      expect(sent.map((http.Request r) => r.url.path), <String>[
        '/api/checkins',
        '/api/logs',
      ]);
      expect(repo.pendingCount.value, 0);
    });

    test('サーバーが断る記録は送るのをやめ、後ろの記録を送る', () async {
      final ApiCheckinRepository repo = offlineRepo(
        handler: (http.Request r) async => r.url.path == '/api/checkins'
            ? _error(400, 'bad_request', 'placeId の形が正しくありません')
            : _json(_serverLog('lg_1', '2026-11-08T03:12:45Z'), 201),
      );
      await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);
      await repo.addLog(_log());
      online = true;

      final SyncReport report = await repo.sync();

      expect(report.rejected, 1);
      expect(repo.pendingCount.value, 0);
      expect(sent.last.url.path, '/api/logs');
    });

    for (final int status in <int>[401, 403, 429, 500]) {
      test('$status の応答では記録を消さず、次の機会に送る', () async {
        final ApiCheckinRepository repo = offlineRepo(
          handler: (http.Request r) async => _error(status, 'x', 'x'),
        );
        await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);
        online = true;

        final SyncReport report = await repo.sync();

        expect(report.rejected, 0);
        expect(repo.pendingCount.value, 1);
      });
    }

    test('圏外で保存したチェックインは、再起動後も訪問した日時を付けて送る', () async {
      final DateTime stayedAt = DateTime.utc(2026, 11, 5, 1, 30);
      await offlineRepo().checkIn(
        _place,
        lat: _place.lat,
        lng: _place.lng,
        visitedAt: stayedAt,
      );
      online = true;

      await offlineRepo().sync();

      final Map<String, dynamic> body =
          jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body['placeId'], _place.id);
      expect(DateTime.parse(body['visitedAt'] as String), stayedAt);
    });

    test('応答を受け取れなかった思い出ログは、同じ clientId と訪問した日時で送り直す', () async {
      bool loseResponse = true;
      final ApiCheckinRepository repo = offlineRepo(
        handler: (http.Request r) async {
          if (loseResponse) {
            throw TimeoutException('応答が届かない');
          }
          return _json(_serverLog('lg_1', '2026-11-08T03:12:45Z'), 201);
        },
      );
      online = true;

      await repo.addLog(_log());
      expect(repo.pendingCount.value, 1);

      loseResponse = false;
      await repo.sync();

      expect(repo.pendingCount.value, 0);
      expect(sent, hasLength(2));
      final Map<String, dynamic> first =
          jsonDecode(sent[0].body) as Map<String, dynamic>;
      final Map<String, dynamic> second =
          jsonDecode(sent[1].body) as Map<String, dynamic>;
      expect(first['clientId'], isNotEmpty);
      expect(second['clientId'], first['clientId']);
      expect(
        DateTime.parse(second['visitedAt'] as String),
        _log().createdAt.toUtc(),
      );
    });

    test('別の思い出ログには別の clientId を付ける', () async {
      final ApiCheckinRepository repo = offlineRepo();
      online = true;

      await repo.addLog(_log());
      await repo.addLog(_log());

      final Iterable<Object?> ids = sent.map(
        (http.Request r) => (jsonDecode(r.body) as Map)['clientId'],
      );
      expect(ids.toSet(), hasLength(2));
    });

    test('思い出ログは、未送信の記録を上に、最後に読めた一覧を下に並べる', () async {
      final ApiCheckinRepository repo = offlineRepo(
        handler: (http.Request r) async => _json(<String, Object>{
          'logs': <Object>[_serverLog('lg_old', '2026-11-07T03:12:45Z')],
        }, 200),
      );
      online = true;
      await repo.watchLogs().first;
      online = false;

      await repo.addLog(_log());
      final List<MemoryLog> logs = await repo.watchLogs().first;

      expect(logs.first.isPending, isTrue);
      expect(logs.last.id, 'lg_old');
      expect(logs, hasLength(2));
    });

    test('訪問者数は読めないことを例外で伝え、誤った人数を表示させない', () async {
      await expectLater(
        offlineRepo().visitorCount(_place.id),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  group('利用者ごとの記録', () {
    late bool online;
    late List<http.Request> sent;
    late SharedPreferences prefs;

    /// ログインしている利用者。この利用者の ID トークンだけを作れる
    late String? signedIn;

    ApiCheckinRepository repoFor(String? uid) => ApiCheckinRepository(
      api: UramichiApi(
        baseUrl: 'http://test',
        client: MockClient((http.Request r) async {
          if (!online) {
            throw http.ClientException('x', r.url);
          }
          sent.add(r);
          return switch (r.url.path) {
            '/api/checkins' => _json(<String, Object>{
              'order': 4,
              'isNew': true,
            }, 200),
            '/api/logs' when r.method == 'GET' => _json(<String, Object>{
              'logs': <Object>[_serverLog('lg_1', '2026-11-08T03:12:45Z')],
            }, 200),
            _ => _json(_serverLog('lg_1', '2026-11-08T03:12:45Z'), 201),
          };
        }),
      ),
      uid: uid,
      idTokenFor: (String uid) async =>
          uid == signedIn ? 'token-$uid' : throw ApiException.signedOut,
      prefs: prefs,
    );

    setUp(() async {
      online = false;
      sent = <http.Request>[];
      signedIn = 'u1';
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
    });

    test('別の利用者に切り替えると、前の利用者の未送信の記録を送らず、件数にも含めない', () async {
      final ApiCheckinRepository repo = repoFor('u1');
      await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);

      signedIn = 'u2';
      repo.setUser('u2');
      online = true;
      await repo.sync();

      expect(sent, isEmpty);
      expect(repo.pendingCount.value, 0);
    });

    test('記録した利用者に戻ると、その利用者の ID トークンで送る', () async {
      final ApiCheckinRepository repo = repoFor('u1');
      await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);
      repo.setUser('u2');

      repo.setUser('u1');
      online = true;
      final SyncReport report = await repo.sync();

      expect(report.checkins.single.order, 4);
      expect(sent.single.headers['Authorization'], 'Bearer token-u1');
      expect(repo.pendingCount.value, 0);
    });

    test('記録した利用者と別の利用者がログインしていれば、送らずに残す', () async {
      final ApiCheckinRepository repo = repoFor('u1');
      await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);

      signedIn = 'u2';
      online = true;
      await repo.sync();

      expect(sent, isEmpty);
      expect(repo.pendingCount.value, 1);
    });

    test('ログインしていないときは送らない', () async {
      final ApiCheckinRepository repo = repoFor('u1');
      await repo.checkIn(_place, lat: _place.lat, lng: _place.lng);

      repo.setUser(null);
      online = true;
      await repo.sync();

      expect(sent, isEmpty);
      expect(repo.pendingCount.value, 0);
    });

    test('通信できないとき、別の利用者には前の利用者の最後に読めた一覧を表示しない', () async {
      online = true;
      expect(await repoFor('u1').watchLogs().first, hasLength(1));
      await pumpEventQueue();

      online = false;
      signedIn = 'u2';

      expect(await repoFor('u2').watchLogs().first, isEmpty);
    });

    test('利用者を切り替えると、購読中の一覧を切り替えた利用者の記録で読み直す', () async {
      online = true;
      final ApiCheckinRepository repo = repoFor('u1');
      final List<List<MemoryLog>> seen = <List<MemoryLog>>[];
      final StreamSubscription<List<MemoryLog>> sub = repo.watchLogs().listen(
        seen.add,
      );
      await pumpEventQueue();

      repo.setUser(null);
      await pumpEventQueue();
      await sub.cancel();

      expect(seen.map((List<MemoryLog> l) => l.length), <int>[1, 0]);
    });

    test('利用者を区別していなかった版の記録は、誰にも送らずに消す', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pendingCheckins': jsonEncode(<Object>[
          <String, Object>{
            'placeId': 'place_01',
            'placeName': '坂の上の小さな祠',
            'lat': 34.697,
            'lng': 135.192,
            'visitedAt': '2026-11-08T03:12:45Z',
          },
        ]),
        'cachedLogs': '[]',
      });
      prefs = await SharedPreferences.getInstance();

      final ApiCheckinRepository repo = repoFor('u1');

      expect(repo.pendingCount.value, 0);
      expect(prefs.containsKey('pendingCheckins'), isFalse);
      expect(prefs.containsKey('cachedLogs'), isFalse);
    });
  });
}
