import '../strings.dart';

/// 場所 1 件。サーバー（backend/internal/places/place.go）と同じ JSON 形式。
///
/// 項目を増やすときは、サーバー側と docs/data-model.md も一緒に直すこと。
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.address,
    this.primaryType,
    this.types = const [],
    this.userRatingCount = 0,
    this.reviewCountKnown = true,
    this.rating,
    this.obscurity,
    this.title,
    this.distanceMeters,
    this.hits = 0,
    this.misses = 0,
    this.stars,
    this.starCount = 0,
  });

  final String id;
  final String name;
  final double lat;
  final double lng;
  final String? address;
  final String? primaryType;
  final List<String> types;
  final int userRatingCount;

  /// 口コミ数を取得したか。お気に入りの一覧は料金を抑えるため口コミ数を取得しないので false になり、
  /// そのときは [userRatingCount] を 0 件として扱わず、口コミ数と称号を表示しない
  final bool reviewCountKnown;

  final double? rating;

  /// 未知度スコア（0〜100。大きいほど知られていない）
  final int? obscurity;

  /// 称号。[PlaceTitle] の値が入る
  final String? title;

  /// 基準地点からの距離（代替提案のときだけ入る）
  final int? distanceMeters;

  /// ウラミチの利用者が付けた当たりの数
  final int hits;

  /// ウラミチの利用者が付けたハズレの数
  final int misses;

  /// ウラミチの利用者が付けた★評価の平均（1〜5）。★評価がなければ null
  final double? stars;

  /// ★評価の数
  final int starCount;

  /// [placeId] がダミーの場所の ID か。サーバーと同梱のダミーデータは全て `mock_` で始まる ID を使う
  // 画面と未送信の記録を通して isMock を引き継ぐと渡し忘れが起きるため、place ID だけで判定する
  static bool isMockId(String placeId) => placeId.startsWith('mock_');

  /// 実在しないダミーの場所か
  bool get isMock => isMockId(id);

  factory Place.fromJson(Map<String, dynamic> j) => Place(
    id: j['id'] as String,
    name: j['name'] as String,
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    address: j['address'] as String?,
    primaryType: j['primaryType'] as String?,
    types: ((j['types'] as List?) ?? const []).cast<String>(),
    userRatingCount: (j['userRatingCount'] as num?)?.toInt() ?? 0,
    reviewCountKnown: j['userRatingCount'] != null,
    rating: (j['rating'] as num?)?.toDouble(),
    obscurity: (j['obscurity'] as num?)?.toInt(),
    title: j['title'] as String?,
    distanceMeters: (j['distanceMeters'] as num?)?.toInt(),
    hits: (j['hits'] as num?)?.toInt() ?? 0,
    misses: (j['misses'] as num?)?.toInt() ?? 0,
    stars: (j['stars'] as num?)?.toDouble(),
    starCount: (j['starCount'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lat': lat,
    'lng': lng,
    if (address != null) 'address': address,
    if (primaryType != null) 'primaryType': primaryType,
    'types': types,
    if (reviewCountKnown) 'userRatingCount': userRatingCount,
    if (rating != null) 'rating': rating,
    if (obscurity != null) 'obscurity': obscurity,
    if (title != null) 'title': title,
    if (distanceMeters != null) 'distanceMeters': distanceMeters,
    if (hits > 0) 'hits': hits,
    if (misses > 0) 'misses': misses,
    if (stars != null) 'stars': stars,
    if (starCount > 0) 'starCount': starCount,
  };
}

/// 称号。サーバーの `PlaceTitle` と同じ文字列。
enum PlaceTitle {
  untrodden('untrodden'),
  hidden('hidden'),
  known('known'),
  famous('famous');

  const PlaceTitle(this.value);
  final String value;
  String get label => switch (this) {
    untrodden => l10n.titleUntrodden,
    hidden => l10n.titleHidden,
    known => l10n.titleKnown,
    famous => l10n.titleFamous,
  };

  static PlaceTitle? of(String? value) {
    for (final t in values) {
      if (t.value == value) return t;
    }
    return null;
  }
}
