import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/achievement_stats.dart';
import '../models/assistant_answer.dart';
import '../data/favorites.dart';
import '../models/memory_log.dart';
import '../models/place.dart';
import '../models/place_genre.dart';
import '../models/place_photo.dart';
import '../models/profile.dart';
import '../models/timeline_entry.dart';
import 'mock_data.dart';
import '../strings.dart';

/// API サーバー（backend/）を呼ぶクライアント。画面からは直接 http を使わず、これを使う。
///
/// 接続先（[baseUrl]）がない開発用のビルドだけ、アプリに同梱したダミーデータ（[MockData]）を返す。
/// 接続先があれば、API サーバーに接続できなくてもダミーに切り替えず、エラーを返す。
/// 架空の場所を本物のように見せないため
class UramichiApi {
  UramichiApi({
    required this.baseUrl,
    http.Client? client,
    MockData? mock,
    Future<String> Function()? idToken,
  }) : _http = client ?? http.Client(),
       _mock = mock ?? MockData(),
       _idToken = idToken;

  /// API サーバーの URL。空の文字列は同じオリジン（Web の公開版）、null は接続先がないことを表す
  final String? baseUrl;
  final http.Client _http;
  final MockData _mock;

  /// 検索に付ける ID トークンを返す。Places API を呼ぶ検索はログインが必要である
  final Future<String> Function()? _idToken;

  /// 受け取った場所の名前（place ID → 名前）。記録やタイムラインを読むときに `known` で送り、
  /// サーバーが同じ名前を Places API から読み直さないようにする（1日の上限があるため）。
  /// 端末には保存せず、アプリを閉じると消える
  final PlaceNames placeNames = PlaceNames();

  static const Duration _timeout = Duration(seconds: 10);

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
    String? idToken,
  }) async {
    final Uri uri = Uri.parse(
      '${baseUrl ?? ''}$path',
    ).replace(queryParameters: query);
    return _decode(
      await _http.get(uri, headers: _headers(idToken)).timeout(_timeout),
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    required String idToken,
  }) => _send('POST', path, body, idToken: idToken);

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, Object?> body, {
    required String idToken,
  }) async {
    final http.Request request =
        http.Request(method, Uri.parse('${baseUrl ?? ''}$path'))
          ..headers.addAll(<String, String>{
            ..._headers(idToken),
            'Content-Type': 'application/json; charset=utf-8',
          })
          ..body = jsonEncode(body);
    final http.Response res = await http.Response.fromStream(
      await _http.send(request),
    ).timeout(_timeout);
    return _decode(res);
  }

  static Map<String, String> _headers(String? idToken) => <String, String>{
    if (idToken != null) 'Authorization': 'Bearer $idToken',
  };

  static Map<String, dynamic> _decode(http.Response res) {
    final Map<String, dynamic> body =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final Map<String, dynamic>? err = (body['error'] as Map?)
          ?.cast<String, dynamic>();
      throw ApiException(
        res.statusCode,
        err?['code'] as String? ?? 'unknown',
        err?['message'] as String? ?? l10n.errorGeneric,
      );
    }
    return body;
  }

  /// 設定の「デモデータで動かす」。オンのあいだは API サーバーを呼ばず、ダミーデータだけで動く
  bool demoMode = false;

  /// API サーバーを呼ばずにダミーデータだけで動いているか（デモデータの設定か、接続先のない開発用のビルド）
  bool get usesMockOnly => demoMode || baseUrl == null;

  /// ふだんは [live] で API を呼ぶ。デモデータの設定のときと、接続先がない開発用のビルドだけ [mock] のダミーデータを返す。
  /// API を使えなくてもダミーには切り替えない（デモデータを使うのは、利用者が設定で選んだときだけ）
  Future<T> withFallback<T>(
    Future<T> Function() live,
    Future<T> Function() mock,
  ) => usesMockOnly ? mock() : live();

  /// API を使えない失敗か。接続できない、応答がない、API がない（JSON でない応答や 404 の未定義の経路）、
  /// サーバーが応答できない（501〜504）ときに true を返す。
  /// 有名スポットが見つからない（404 origin_not_found）のような API の答えと、
  /// サーバーの処理の失敗（500）は、画面でエラーとして見せるため false を返す
  static bool isUnavailable(Object error) => switch (error) {
    http.ClientException() || TimeoutException() || FormatException() => true,
    ApiException(status: 404, code: 'unknown' || 'not_found') => true,
    ApiException(:final int status) => status >= 501 && status <= 504,
    _ => false,
  };

  /// 未踏サーチ（担当：A）
  Future<ExploreResult> explore({
    required double lat,
    required double lng,
    int radius = 1500,
    Set<PlaceGenre> genres = const <PlaceGenre>{},
    (int, int)? popularity,
  }) => withFallback(
    () => _exploreLive(
      lat: lat,
      lng: lng,
      radius: radius,
      genres: genres,
      popularity: popularity,
    ),
    () async {
      final ExploreResult all = await _mock.explore(
        lat: lat,
        lng: lng,
        radius: radius,
      );
      return ExploreResult(
        places: <Place>[
          for (final Place p in all.places)
            if (PlaceGenre.matches(p, genres)) p,
        ],
        isMock: true,
      );
    },
  );

  /// 地図を移動する先を探す。
  // 通信できないときにダミーの地点を返すと、入力と別の地点へ気付かずに移動するため、ダミーは利用者が選んだときだけ返す
  Future<LocateResult> locate(String query) async {
    if (usesMockOnly) {
      return _mock.locate(query);
    }
    final Map<String, dynamic> j = await _get(
      '/api/locate',
      query: <String, String>{'q': query},
      idToken: await _idToken?.call(),
    );
    return LocateResult(
      name: j['name'] as String,
      lat: (j['lat'] as num).toDouble(),
      lng: (j['lng'] as num).toDouble(),
      isMock: j['source'] == 'mock',
    );
  }

  /// チェックインの候補を探す。[explore] と違い、通信できないときはダミーを返さずに例外を投げる。
  /// 現在地の近くに存在しないスポットへ、チェックインできてしまうのを防ぐため
  Future<ExploreResult> exploreForCheckin({
    required double lat,
    required double lng,
    required int radius,
  }) => usesMockOnly
      ? _mock.explore(lat: lat, lng: lng, radius: radius)
      : _exploreLive(lat: lat, lng: lng, radius: radius, purpose: 'checkin');

  Future<ExploreResult> _exploreLive({
    required double lat,
    required double lng,
    required int radius,
    String? purpose,
    Set<PlaceGenre> genres = const <PlaceGenre>{},
    (int, int)? popularity,
  }) async {
    final Map<String, dynamic> j = await _get(
      '/api/explore',
      query: <String, String>{
        'lat': '$lat',
        'lng': '$lng',
        'radius': '$radius',
        'purpose': ?purpose,
        if (genres.isNotEmpty)
          'genre': genres.map((PlaceGenre g) => g.id).join(','),
        if (popularity case (final int lo, final int hi))
          'popularity': '$lo,$hi',
      },
      idToken: await _idToken?.call(),
    );
    return ExploreResult(
      places: _places(j['places']),
      isMock: j['source'] == 'mock',
    );
  }

  /// 代わりに行くならここ（担当：B）
  Future<AlternativesResult> alternatives(String query, {int radius = 3000}) =>
      withFallback(() async {
        final Map<String, dynamic> j = await _get(
          '/api/alternatives',
          query: <String, String>{'q': query, 'radius': '$radius'},
          idToken: await _idToken?.call(),
        );
        return AlternativesResult(
          origin: _place((j['origin'] as Map).cast<String, dynamic>()),
          alternatives: _places(j['alternatives']),
          isMock: j['source'] == 'mock',
        );
      }, () => _mock.alternatives(radius: radius));

  /// Geminiちゃんに話しかける。[lat] と [lng] は地図の中心で、場所の名前がない依頼のときにサーバーが使う。
  /// [history] は直前のやり取り（古い順）。サーバーに接続できないときは、ダミーの場所から選んだ答えを返す
  Future<AssistantAnswer> askAssistant(
    String message, {
    double? lat,
    double? lng,
    List<AssistantTurn> history = const <AssistantTurn>[],
    Map<String, Object>? context,
  }) => withFallback(
    () async => _rememberAnswer(
      AssistantAnswer.fromJson(
        await _post('/api/assistant', <String, Object>{
          'message': message,
          'lat': ?lat,
          'lng': ?lng,
          'history': <Map<String, String>>[
            for (final AssistantTurn t in history) t.toJson(),
          ],
          'context': ?context,
        }, idToken: await _requireIdToken()),
      ),
    ),
    () => _mock.assistant(lat: lat, lng: lng),
  );

  /// Places API や Gemini を呼ぶ API に付けるトークン。トークンを作れない設定では、サーバーが 401 を返す
  Future<String> _requireIdToken() async =>
      await _idToken?.call() ?? (throw ApiException.signedOut);

  /// 古参チェックイン。2 回目以降は 1 回目の順番と `isNew: false` を返す
  Future<CheckinResult> postCheckin(
    String placeId, {
    required double lat,
    required double lng,
    required DateTime visitedAt,
    required String idToken,
  }) async {
    final Map<String, dynamic> j =
        await _post('/api/checkins', <String, Object>{
          'placeId': placeId,
          'lat': lat,
          'lng': lng,
          'visitedAt': visitedAt.toUtc().toIso8601String(),
        }, idToken: idToken);
    return CheckinResult(
      order: (j['order'] as num).toInt(),
      isNew: j['isNew'] as bool,
    );
  }

  /// その場所の訪問者数
  Future<int> fetchVisitorCount(
    String placeId, {
    required String idToken,
  }) async {
    final Map<String, dynamic> j = await _get(
      '/api/places/${Uri.encodeComponent(placeId)}/visitors',
      idToken: idToken,
    );
    return (j['visitorCount'] as num).toInt();
  }

  /// 思い出ログを残す。`order` はサーバーが決めるので、応答の値を正として返す。
  /// 場所の名前はサーバーに保存しないので送らない
  Future<MemoryLog> postLog(MemoryLog log, {required String idToken}) async =>
      _memoryLog(
        await _post(
          '/api/logs',
          log.toJson()..remove('placeName'),
          idToken: idToken,
        ),
      );

  /// 自分の記録の公開状態を変える
  Future<void> patchLogPublic(
    String logId, {
    required bool isPublic,
    required String idToken,
  }) async {
    await _send(
      'PATCH',
      '/api/logs/${Uri.encodeComponent(logId)}',
      <String, bool>{'public': isPublic},
      idToken: idToken,
    );
  }

  /// 自分の記録の★評価とひとことを直す
  Future<void> patchLog(
    String logId, {
    required int rating,
    required String comment,
    required String idToken,
  }) async {
    await _send(
      'PATCH',
      '/api/logs/${Uri.encodeComponent(logId)}',
      <String, Object>{'rating': rating, 'comment': comment},
      idToken: idToken,
    );
  }

  /// 指定した地点の周辺で公開された記録（新しい順）
  Future<List<TimelineEntry>> fetchTimeline({
    required double lat,
    required double lng,
    required String idToken,
    bool nationwide = false,
  }) async {
    final Map<String, dynamic> j = await _get(
      '/api/timeline',
      query: <String, String>{
        // 全国の新着は場所を問わないので、地点を送らない
        if (nationwide)
          'scope': 'all'
        else ...<String, String>{'lat': '$lat', 'lng': '$lng'},
        ...placeNames.knownQuery(),
      },
      idToken: idToken,
    );
    return <TimelineEntry>[
      for (final Object? e
          in (j['entries'] as List<Object?>?) ?? const <Object?>[])
        TimelineEntry.fromJson(
          placeNames.fill((e! as Map).cast<String, dynamic>()),
        ),
    ];
  }

  /// 記録に付ける写真を上げ、写真の ID を返す。[bytes] は縮小した JPEG・PNG・WebP
  Future<String> uploadPhoto(
    Uint8List bytes, {
    required String contentType,
    required String idToken,
  }) async {
    final http.Response res = await _http
        .post(
          Uri.parse('${baseUrl ?? ''}/api/photos'),
          headers: <String, String>{
            ..._headers(idToken),
            'Content-Type': contentType,
          },
          body: bytes,
        )
        // 写真は大きいので、ほかの呼び出しより長く待つ
        .timeout(const Duration(seconds: 30));
    return _decode(res)['id'] as String;
  }

  /// 写真の中身。ID は変わらないので、一度読んだ写真はアプリを閉じるまで手元に残す
  Future<Uint8List> fetchPhoto(String photoId, {required String idToken}) {
    return _photos[photoId] ??= () async {
      try {
        final http.Response res = await _http
            .get(
              Uri.parse(
                '${baseUrl ?? ''}/api/photos/${Uri.encodeComponent(photoId)}',
              ),
              headers: _headers(idToken),
            )
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) {
          _decode(res);
          throw ApiException(res.statusCode, 'unknown', l10n.errorGeneric);
        }
        return res.bodyBytes;
      } catch (_) {
        // 読めなかった写真は、次に表示するときに読み直す
        _photos.remove(photoId);
        rethrow;
      }
    }();
  }

  final Map<String, Future<Uint8List>> _photos = <String, Future<Uint8List>>{};

  /// 公開された記録に反応を付け外しし、反応した後の数を返す
  Future<TimelineEntry> react(
    TimelineEntry entry,
    ReactionKind kind, {
    required bool on,
    required String idToken,
  }) async {
    final Map<String, dynamic> j = await _send(
      on ? 'PUT' : 'DELETE',
      '/api/timeline/${Uri.encodeComponent(entry.id)}/reactions/${kind.value}',
      const <String, Object>{},
      idToken: idToken,
    );
    return entry.withReaction(
      kind,
      on: on,
      wantCount: (j['wantCount'] as num?)?.toInt(),
      helpfulCount: (j['helpfulCount'] as num?)?.toInt(),
      myWant: j['myWant'] as bool?,
      myHelpful: j['myHelpful'] as bool?,
    );
  }

  /// 公開された記録を理由つきで報告する
  Future<void> reportEntry(
    String entryId, {
    required ReportReason reason,
    String note = '',
    required String idToken,
  }) async {
    await _send(
      'POST',
      '/api/timeline/${Uri.encodeComponent(entryId)}/report',
      <String, Object>{
        'reason': reason.value,
        if (note.trim().isNotEmpty) 'note': note.trim(),
      },
      idToken: idToken,
    );
  }

  /// 自分のプロフィール。まだ保存していなければ null を返す
  Future<Profile?> fetchProfile({required String idToken}) async {
    final Map<String, dynamic> j = await _get('/api/me', idToken: idToken);
    final Object? profile = j['profile'];
    return profile == null
        ? null
        : Profile.fromJson((profile as Map).cast<String, dynamic>());
  }

  /// 自分のプロフィールを保存し、サーバーが保存した値（前後の空白を除いたもの）を返す
  Future<Profile> saveProfile(
    Profile profile, {
    required String idToken,
  }) async {
    final Map<String, dynamic> j = await _send(
      'PUT',
      '/api/me',
      profile.toJson(),
      idToken: idToken,
    );
    return Profile.fromJson((j['profile'] as Map).cast<String, dynamic>());
  }

  /// 場所の写真（Google マップの写真）。ダミーの場所と、ダミーデータだけで動くときは写真がない
  Future<List<PlacePhoto>> fetchPlacePhotos(String placeId) async {
    if (usesMockOnly || Place.isMockId(placeId)) {
      return const <PlacePhoto>[];
    }
    final Map<String, dynamic> j = await _get(
      '/api/places/${Uri.encodeComponent(placeId)}/photos',
      idToken: await _requireIdToken(),
    );
    return <PlacePhoto>[
      for (final Object? e
          in (j['photos'] as List<Object?>?) ?? const <Object?>[])
        PlacePhoto.fromJson((e! as Map).cast<String, dynamic>()),
    ];
  }

  /// お気に入りの place ID（Places API を呼ばない）
  Future<List<String>> fetchFavoriteIds() async {
    final Map<String, dynamic> j = await _get(
      '/api/favorites/ids',
      idToken: await _requireIdToken(),
    );
    return <String>[
      for (final Object? e
          in (j['placeIds'] as List<Object?>?) ?? const <Object?>[])
        e! as String,
    ];
  }

  /// お気に入りの一覧（新しい順）。場所の名前と位置はサーバーが Places API から読む
  Future<List<FavoriteEntry>> fetchFavorites() async {
    final Map<String, dynamic> j = await _get(
      '/api/favorites',
      idToken: await _requireIdToken(),
    );
    return <FavoriteEntry>[
      for (final Object? e
          in (j['favorites'] as List<Object?>?) ?? const <Object?>[])
        _favorite((e! as Map).cast<String, dynamic>()),
    ];
  }

  FavoriteEntry _favorite(Map<String, dynamic> j) => FavoriteEntry(
    placeId: j['placeId'] as String,
    place: j['place'] == null
        ? null
        : _place((j['place'] as Map).cast<String, dynamic>()),
  );

  Future<void> putFavorite(String placeId) async {
    await _send(
      'PUT',
      '/api/favorites/${Uri.encodeComponent(placeId)}',
      const <String, Object?>{},
      idToken: await _requireIdToken(),
    );
  }

  Future<void> deleteFavorite(String placeId) async {
    await _send(
      'DELETE',
      '/api/favorites/${Uri.encodeComponent(placeId)}',
      const <String, Object?>{},
      idToken: await _requireIdToken(),
    );
  }

  /// 自分が解除した実績と段階を知らせる。ダミーデータだけで動くときは送らない
  Future<void> putAchievements(Map<String, int> tiers) async {
    if (usesMockOnly) {
      return;
    }
    await _send('PUT', '/api/me/achievements', <String, Object?>{
      'tiers': tiers,
    }, idToken: await _requireIdToken());
  }

  /// 利用者全体で、それぞれの実績を解除した人数。ダミーデータだけで動くときは null
  Future<AchievementStats?> fetchAchievementStats() async {
    if (usesMockOnly) {
      return null;
    }
    return AchievementStats.fromJson(
      await _get('/api/achievements/stats', idToken: await _requireIdToken()),
    );
  }

  /// 自分の思い出ログの一覧（新しい順）
  /// [withNames] が false なら、サーバーは場所の名前を読まない（Places API の上限を使わない）
  Future<List<MemoryLog>> fetchLogs({
    required String idToken,
    bool withNames = true,
  }) async {
    final Map<String, dynamic> j = await _get(
      '/api/logs',
      query: withNames
          ? placeNames.knownQuery()
          : const <String, String>{'names': '0'},
      idToken: idToken,
    );
    return <MemoryLog>[
      for (final Object? e
          in (j['logs'] as List<Object?>?) ?? const <Object?>[])
        _memoryLog(placeNames.fill((e! as Map).cast<String, dynamic>())),
    ];
  }

  static MemoryLog _memoryLog(Map<String, dynamic> j) =>
      MemoryLog.fromJson(j['id'] as String, j);

  Place _place(Map<String, dynamic> j) {
    final Place p = Place.fromJson(j);
    placeNames.remember(p.id, p.name);
    return p;
  }

  List<Place> _places(Object? list) => <Place>[
    for (final Object? e in (list as List<Object?>?) ?? const <Object?>[])
      _place((e! as Map).cast<String, dynamic>()),
  ];

  AssistantAnswer _rememberAnswer(AssistantAnswer a) {
    for (final AssistantSuggestion s in a.suggestions) {
      placeNames.remember(s.place.id, s.place.name);
    }
    return a;
  }
}

/// 受け取った場所の名前を、アプリを閉じるまで覚えておく。新しく覚えた順に [capacity] 件まで
class PlaceNames {
  PlaceNames({this.capacity = 200});

  /// サーバーが known で受け取る件数（maxKnownPlaces）と同じにする
  final int capacity;

  // 挿入順を保つ Map。古いものから消す
  final Map<String, String> _names = <String, String>{};

  String? operator [](String placeId) => _names[placeId];

  void remember(String placeId, String name) {
    if (placeId.isEmpty || name.isEmpty || Place.isMockId(placeId)) {
      return;
    }
    _names.remove(placeId);
    _names[placeId] = name;
    while (_names.length > capacity) {
      _names.remove(_names.keys.first);
    }
  }

  /// サーバーに送る known。覚えていなければ空
  Map<String, String> knownQuery() => _names.isEmpty
      ? const <String, String>{}
      : <String, String>{'known': _names.keys.join(',')};

  /// サーバーの記録の JSON の placeName を埋め、受け取った名前を覚える
  Map<String, dynamic> fill(Map<String, dynamic> j) {
    final String id = j['placeId'] as String? ?? '';
    final String name = j['placeName'] as String? ?? '';
    if (name.isNotEmpty) {
      remember(id, name);
      return j;
    }
    final String? known = _names[id];
    return known == null ? j : <String, dynamic>{...j, 'placeName': known};
  }
}

class ExploreResult {
  const ExploreResult({required this.places, required this.isMock});
  final List<Place> places;
  final bool isMock;
}

class AlternativesResult {
  const AlternativesResult({
    required this.origin,
    required this.alternatives,
    required this.isMock,
  });
  final Place origin;
  final List<Place> alternatives;
  final bool isMock;
}

class LocateResult {
  const LocateResult({
    required this.name,
    required this.lat,
    required this.lng,
    required this.isMock,
  });
  final String name;
  final double lat;
  final double lng;

  /// 検索した地点ではなく、ダミーの地点か
  final bool isMock;
}

class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message);

  /// ログインしていないか、記録した利用者と別の利用者がログインしていること
  static final ApiException signedOut = ApiException(
    401,
    'unauthenticated',
    l10n.errorLoginRequired,
  );

  final int status;
  final String code;
  final String message;
  @override
  String toString() => message;
}
