import 'dart:convert';

import 'package:flutter/services.dart';

import '../geo.dart';
import '../models/assistant_answer.dart';
import '../models/place.dart';
import 'uramichi_api.dart';

/// アプリに同梱したダミーデータ（assets/mock/）。
///
/// API サーバーに接続できないとき、API がまだ実装されていないとき、ダミーデータを使う設定のときに返す。
/// 中身は `dart run tool/update_mock_assets.dart` で、ダミーデータで起動した API サーバーの応答から作る。
class MockData {
  MockData({Future<String> Function(String path)? load})
    // 読んだ JSON はこのクラスで保持するので、rootBundle の側では保持しない
    : _load =
          load ?? ((String path) => rootBundle.loadString(path, cache: false));

  final Future<String> Function(String path) _load;
  final Map<String, Map<String, dynamic>> _cache =
      <String, Map<String, dynamic>>{};

  Future<Map<String, dynamic>> _json(String path) async {
    final Map<String, dynamic>? cached = _cache[path];
    if (cached != null) {
      return cached;
    }
    final Map<String, dynamic> json =
        jsonDecode(await _load(path)) as Map<String, dynamic>;
    _cache[path] = json;
    return json;
  }

  /// 指定した地点の周りのダミーの場所。地図を動かしても周りに表示されるよう、
  /// ダミーデータの中心からの位置関係を保って、指定した地点の周りに置き直す
  Future<ExploreResult> explore({
    required double lat,
    required double lng,
    required int radius,
  }) async {
    final Map<String, dynamic> json = await _json('assets/mock/explore.json');
    final Map<String, dynamic> center = (json['center'] as Map)
        .cast<String, dynamic>();
    final double dLat = lat - (center['lat'] as num).toDouble();
    final double dLng = lng - (center['lng'] as num).toDouble();
    final List<Place> places = <Place>[
      for (final Place p in _places(json['places']))
        if (distanceMeters(lat, lng, p.lat + dLat, p.lng + dLng) <= radius)
          Place.fromJson(<String, dynamic>{
            ...p.toJson(),
            'lat': p.lat + dLat,
            'lng': p.lng + dLng,
          }),
    ];
    return ExploreResult(places: places, isMock: true);
  }

  /// どの名前で探しても、ダミーの場所がある地点を返す
  Future<LocateResult> locate(String query) async {
    final Map<String, dynamic> json = await _json('assets/mock/explore.json');
    final Map<String, dynamic> center = (json['center'] as Map)
        .cast<String, dynamic>();
    return LocateResult(
      name: query,
      lat: (center['lat'] as num).toDouble(),
      lng: (center['lng'] as num).toDouble(),
      isMock: true,
    );
  }

  /// どの名前で探しても、同じダミーの有名スポットと候補を返す
  Future<AlternativesResult> alternatives({required int radius}) async {
    final Map<String, dynamic> json = await _json(
      'assets/mock/alternatives.json',
    );
    return AlternativesResult(
      origin: Place.fromJson((json['origin'] as Map).cast<String, dynamic>()),
      alternatives: <Place>[
        for (final Place p in _places(json['alternatives']))
          if ((p.distanceMeters ?? 0) <= radius) p,
      ],
      isMock: true,
    );
  }

  /// サーバーに接続できないときの Geminiちゃんの答え。地図の中心の周りのダミーの場所から、未知度の高い順に3件選ぶ
  Future<AssistantAnswer> assistant({double? lat, double? lng}) async {
    final Map<String, dynamic> json = await _json('assets/mock/explore.json');
    final Map<String, dynamic> center = (json['center'] as Map)
        .cast<String, dynamic>();
    final double cLat = lat ?? (center['lat'] as num).toDouble();
    final double cLng = lng ?? (center['lng'] as num).toDouble();
    final List<Place> places =
        (await explore(lat: cLat, lng: cLng, radius: 1500)).places
            .where((Place p) => p.title != PlaceTitle.famous.value)
            .toList()
          ..sort((Place a, Place b) => (b.obscurity ?? 0) - (a.obscurity ?? 0));
    return AssistantAnswer(
      reply: 'いまはサーバーにつながらないので、ダミーの場所から穴場を選びました。',
      intent: AssistantIntent.recommend,
      isMock: true,
      center: AssistantCenter(name: '地図の中心', lat: cLat, lng: cLng),
      suggestions: <AssistantSuggestion>[
        for (final Place p in places.take(3))
          AssistantSuggestion(
            place: p,
            reason: '口コミが${p.userRatingCount}件と少なく、まだ知る人ぞ知る場所です。',
          ),
      ],
    );
  }

  static List<Place> _places(Object? list) => <Place>[
    for (final Object? e in (list as List<Object?>?) ?? const <Object?>[])
      Place.fromJson((e! as Map).cast<String, dynamic>()),
  ];
}
