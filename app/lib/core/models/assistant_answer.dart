import 'package:flutter/foundation.dart';

import 'place.dart';
import 'place_genre.dart';

/// Geminiちゃんに話しかけた一言と答えの1往復分。直前のやり取りとしてサーバーに送る
class AssistantTurn {
  const AssistantTurn.user(this.text) : fromUser = true;
  const AssistantTurn.assistant(this.text) : fromUser = false;

  final bool fromUser;
  final String text;

  Map<String, String> toJson() => <String, String>{
    'role': fromUser ? 'user' : 'assistant',
    'text': text,
  };
}

/// Geminiちゃんが読み取った意図
enum AssistantIntent {
  /// 穴場のおすすめ
  recommend,

  /// 有名スポットの代わり
  alternatives,

  /// 地図の移動
  locate,

  /// 会話
  chat;

  static AssistantIntent of(String? value) => AssistantIntent.values.firstWhere(
    (AssistantIntent i) => i.name == value,
    orElse: () => chat,
  );
}

/// おすすめ1件。[reason] は Gemini（または簡易版）が書いた理由
class AssistantSuggestion {
  const AssistantSuggestion({required this.place, required this.reason});

  final Place place;
  final String reason;
}

/// 地図を移動する先、または探した中心
class AssistantCenter {
  const AssistantCenter({
    required this.name,
    required this.lat,
    required this.lng,
  });

  final String name;
  final double lat;
  final double lng;
}

/// Geminiちゃんの答え。サーバー（POST /api/assistant）と同じ JSON 形式
class AssistantAnswer {
  const AssistantAnswer({
    required this.reply,
    required this.intent,
    this.byGemini = false,
    this.isMock = false,
    this.center,
    this.genres = const <PlaceGenre>{},
    this.query,
    this.suggestions = const <AssistantSuggestion>[],
    this.targets = const <Place>[],
  });

  factory AssistantAnswer.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic>? c = (j['center'] as Map?)
        ?.cast<String, dynamic>();
    final Map<String, dynamic>? search = (j['search'] as Map?)
        ?.cast<String, dynamic>();
    final List<Object?> genreIds =
        (search?['genres'] as List<Object?>?) ?? const <Object?>[];
    return AssistantAnswer(
      reply: j['reply'] as String? ?? '',
      intent: AssistantIntent.of(j['intent'] as String?),
      byGemini: j['source'] == 'gemini',
      isMock: j['placesSource'] == 'mock',
      // 形の違う値（空の値など）が来ても、答え全体を読めなくしないよう、読める部分だけを使う
      center: c == null || c['lat'] is! num || c['lng'] is! num
          ? null
          : AssistantCenter(
              name: c['name'] as String? ?? '',
              lat: (c['lat'] as num).toDouble(),
              lng: (c['lng'] as num).toDouble(),
            ),
      genres: <PlaceGenre>{
        for (final PlaceGenre g in PlaceGenre.values)
          if (genreIds.contains(g.id)) g,
      },
      query: search?['query'] as String?,
      suggestions: <AssistantSuggestion>[
        for (final Object? s
            in (j['suggestions'] as List<Object?>?) ?? const <Object?>[])
          if (s is Map && s['place'] is Map)
            if (_place(s['place'] as Map) case final Place place)
              AssistantSuggestion(
                place: place,
                reason: s['reason'] as String? ?? '',
              ),
      ],
      targets: <Place>[
        for (final Object? p
            in (j['targets'] as List<Object?>?) ?? const <Object?>[])
          if (p is Map)
            if (_place(p) case final Place place) place,
      ],
    );
  }

  /// 利用者に見せる答え
  final String reply;
  final AssistantIntent intent;

  /// Gemini が書いた答えか。false ならキーワードで答える簡易版
  final bool byGemini;

  /// おすすめがダミーの場所か
  final bool isMock;

  /// 探した中心、または地図を移動する先
  final AssistantCenter? center;

  /// 地図で同じ条件を探すためのジャンル
  final Set<PlaceGenre> genres;

  /// 代わりを探した有名スポットの名前
  final String? query;
  final List<AssistantSuggestion> suggestions;

  /// 穴場ではなく、その場所そのものを探したとき（「近くの駅」など）に見つかった場所。近い順。
  /// [suggestions] は、そのうちいちばん近い場所のそばの穴場になる
  final List<Place> targets;

  /// Places API で見つけた場所を見せる答えか（出典を出すかの判断に使う）
  bool get mentionsPlaces => suggestions.isNotEmpty || targets.isNotEmpty;

  /// 読めない場所は飛ばす（必要な項目が欠けた場所で、答え全体を読めなくしないため）
  static Place? _place(Map<dynamic, dynamic> j) {
    try {
      return Place.fromJson(j.cast<String, dynamic>());
    } catch (error) {
      debugPrint('Geminiちゃんの答えの場所を読めません: $error');
      return null;
    }
  }
}
