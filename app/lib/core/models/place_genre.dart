import 'place.dart';
import '../strings.dart';

/// 検索するジャンル。[id] はサーバー（backend/internal/places/genre.go）と同じ文字列
enum PlaceGenre {
  food('food', <String>['restaurant', 'cafe', 'coffee_shop', 'tea_house']),
  nature('nature', <String>['park', 'garden', 'hiking_area']),
  worship('worship', <String>['buddhist_temple', 'shinto_shrine']),
  culture('culture', <String>['museum', 'art_gallery', 'cultural_center']),
  view('view', <String>['observation_deck', 'tourist_attraction']),
  shopping('shopping', <String>['market', 'store', 'shopping_mall']),
  other('other', <String>[]);

  const PlaceGenre(this.id, this.types);

  final String id;
  String get label => switch (this) {
    food => l10n.genreFood,
    nature => l10n.genreNature,
    worship => l10n.genreWorship,
    culture => l10n.genreCulture,
    view => l10n.genreView,
    shopping => l10n.genreShopping,
    other => l10n.genreOther,
  };
  final List<String> types;

  bool _covers(Place place) =>
      types.contains(place.primaryType) || place.types.any(types.contains);

  /// [place] のジャンル。どのジャンルにも入らなければ null。
  /// 寺が観光名所を兼ねるように複数のジャンルに入る場所は、主な種類のジャンルを優先する
  static PlaceGenre? of(Place place) {
    for (final PlaceGenre genre in values) {
      if (genre.types.contains(place.primaryType)) {
        return genre;
      }
    }
    for (final PlaceGenre genre in values) {
      if (place.types.any(genre.types.contains)) {
        return genre;
      }
    }
    return null;
  }

  /// サーバーを呼ばないダミーデータを、選んだジャンルで絞るときに使う
  static bool matches(Place place, Set<PlaceGenre> selected) {
    if (selected.isEmpty) {
      return true;
    }
    final bool inOthers = PlaceGenre.values.any(
      (PlaceGenre g) => g != other && !selected.contains(g) && g._covers(place),
    );
    if (selected.contains(other)) {
      return !inOthers;
    }
    return selected.any((PlaceGenre g) => g._covers(place));
  }
}
