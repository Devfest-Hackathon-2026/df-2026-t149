import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/api/uramichi_api.dart';
import '../../core/geo.dart';
import '../../core/location/location_service.dart';
import '../../core/models/place.dart';
import '../../core/models/place_genre.dart';
import '../../core/settings.dart';
import '../../core/widgets/map_zoom.dart';
import '../../core/widgets/state_view.dart';
import '../regions/regions.dart';
import '../../core/strings.dart';

sealed class SearchState {
  const SearchState();
}

/// まだ探していない。地図には何も表示しない
final class SearchIdle extends SearchState {
  const SearchIdle();
}

final class SearchLoading extends SearchState {
  const SearchLoading();
}

final class SearchLoaded extends SearchState {
  const SearchLoaded({required this.places, required this.isMock});

  final List<Place> places;
  final bool isMock;
}

final class SearchFailed extends SearchState {
  const SearchFailed(this.message);

  final String message;
}

/// 探すボタンが行う操作
enum SearchAction {
  /// 結果が今の条件と一致していて、探す必要がない
  none,

  /// 探していない、または地図を動かした
  searchArea,

  /// ジャンルや半径を変えて、まだ探していない
  applyConditions,
}

/// 結果の並べ替え。すぐに反映し、サーバーを呼ばない
enum ResultSort {
  /// 知られていなくて近く、評判のよい順
  balanced(),

  /// 知られていない順
  obscure(),

  /// 近い順
  near();

  const ResultSort();
  String get label => switch (this) {
    balanced => l10n.sortBalanced,
    obscure => l10n.sortObscure,
    near => l10n.sortNear,
  };
  String get description => switch (this) {
    balanced => l10n.sortBalancedDescription,
    obscure => l10n.sortObscureDescription,
    near => l10n.sortNearDescription,
  };
}

/// 場所の評判のよさ（0〜1）。知られていなくても、評価の低い場所を上に出さないために使う。
///
/// - Google の★：口コミが少ないと数件で大きく振れるので、3.8 を5件分足した平均にする
/// - ウラミチの「当たり／ハズレ」：1件ずつ足した割合にする（記録がなければ 0.5）
/// - ウラミチの★：3.5 を2件分足した平均にする
double placeQuality(Place p) {
  const double googlePrior = 3.8;
  const int googleWeight = 5;
  final int n = p.rating == null ? 0 : p.userRatingCount;
  final double google =
      (googlePrior * googleWeight + (p.rating ?? googlePrior) * n) /
      (googleWeight + n);
  final double googleScore = ((google - 3.0) / 2.0).clamp(0.0, 1.0);
  final double community = (p.hits + 1) / (p.hits + p.misses + 2);
  const double starPrior = 3.5;
  final double stars =
      (starPrior * 2 + (p.stars ?? starPrior) * p.starCount) /
      (2 + p.starCount);
  final double starScore = ((stars - 1) / 4).clamp(0.0, 1.0);
  return googleScore * 0.6 + community * 0.25 + starScore * 0.15;
}

/// 評判が悪いとはっきりしている場所か。Google の★が 3.5 未満（口コミ3件以上）か、
/// ウラミチでハズレが当たりより多い（2件以上）
bool hasPoorReputation(Place p) =>
    (p.rating != null && p.rating! < 3.5 && p.userRatingCount >= 3) ||
    (p.misses >= 2 && p.misses > p.hits);

/// 「おすすめ順」の点数。知られていなさ・近さ・評判のよさを合わせ、評判の悪い場所は下げる。
/// [nearness] は近さ（0〜1、近いほど大きい）
double recommendScore(Place p, {required double nearness}) {
  final double score =
      (p.obscurity ?? 0) / 100 * 0.45 + nearness * 0.3 + placeQuality(p) * 0.25;
  return hasPoorReputation(p) ? score * 0.6 : score;
}

/// 地図の検索の条件と結果。
///
/// ジャンル、半径、地点は Places API の呼び出しが必要なので、変えただけでは探さず [action] で知らせる。
/// 称号と並べ替えは手元の結果に対する操作なので、すぐに反映する
class MapSearchController extends ChangeNotifier {
  MapSearchController({
    required this.api,
    required this.location,
    required this.settings,
    required LatLng start,
  }) : _center = switch (settings.lastMapCenter) {
         (final double lat, final double lng) => LatLng(lat, lng),
         null => start,
       } {
    _demoMode = settings.demoMode;
    settings.addListener(_onSettingsChanged);
  }

  bool _demoMode = false;

  /// デモデータの設定を切り替えたら、探した結果を新しいデータで探し直す
  void _onSettingsChanged() {
    if (settings.demoMode == _demoMode) {
      return;
    }
    _demoMode = settings.demoMode;
    if (_state is! SearchIdle) {
      search();
    }
  }

  final UramichiApi api;
  final LocationService location;
  final AppSettings settings;

  /// 地図の拡大率。ズームのスライダーと地図をつなぐ
  final MapZoomController zoom = MapZoomController();

  /// 半径の段階（m）。5km より広い範囲は、サーバーが複数の地点で探す。API の上限は 50km
  static const List<int> radiusSteps = <int>[
    1500,
    3000,
    5000,
    10000,
    20000,
    50000,
  ];

  /// この半径より広い範囲を「広い範囲」として扱う（地図を引いて地域を見るとき）
  static const int wideRadius = 5000;

  /// この距離より小さく地図を動かしても、探し直しを促さない
  static const int _movedThresholdMeters = 50;

  /// 表示中の検索結果を薄くする移動距離（m）
  static const int _staleThresholdMeters = 500;

  /// 探した地点が現在地からこの距離より遠ければ、下調べとして探した地点から距離を測る
  static const int _nearUserMeters = 10000;

  LatLng _center;
  int _radius = radiusSteps.first;
  final Set<PlaceGenre> _genres = <PlaceGenre>{};

  LatLng? _appliedCenter;
  int? _appliedRadius;
  Set<PlaceGenre> _appliedGenres = const <PlaceGenre>{};
  (int, int) _appliedPopularity = (0, 1);

  SearchState _state = const SearchIdle();
  final Set<PlaceTitle> _titles = <PlaceTitle>{
    PlaceTitle.untrodden,
    PlaceTitle.hidden,
  };
  ResultSort _sort = ResultSort.balanced;

  /// お気に入りだけを出すときの判定。null なら全部出す
  bool Function(String placeId)? _favoriteFilter;
  LatLng? _userLocation;
  LatLng? _jumpCenter;
  String? _jumpName;
  String? _jumpQuery;
  String? _selectedId;
  bool _locating = false;
  int _requestId = 0;
  (SearchLoaded, int, ResultSort, LatLng, int)? _visibleKey;
  List<Place> _visibleCache = const <Place>[];

  LatLng get center => _center;
  int get radius => _radius;
  Set<PlaceGenre> get genres => Set<PlaceGenre>.unmodifiable(_genres);
  SearchState get state => _state;
  Set<PlaceTitle> get titles => Set<PlaceTitle>.unmodifiable(_titles);
  ResultSort get sort => _sort;

  /// お気に入りだけを出しているか
  bool get favoritesOnly => _favoriteFilter != null;

  /// お気に入りだけを出す。[isFavorite] はお気に入りかの判定（FavoritesController.isFavorite）
  void setFavoritesOnly(bool on, {bool Function(String placeId)? isFavorite}) {
    _favoriteFilter = on ? isFavorite : null;
    _visibleKey = null;
    notifyListeners();
  }

  /// お気に入りを付け外ししたときに、絞り込みを作り直す
  void favoritesChanged() {
    if (favoritesOnly) {
      _visibleKey = null;
      notifyListeners();
    }
  }

  LatLng? get userLocation => _userLocation;
  bool get locating => _locating;

  /// 周辺のタイムラインの基準の地点。地図に表示している地点を使う
  LatLng get timelineCenter => _center;

  /// 周辺のタイムラインの基準の地点の呼び名
  String get timelineCenterLabel =>
      searchedPlaceName ??
      (_isNear(_userLocation, _center) ? l10n.currentLocation : l10n.mapCenter);

  /// 検索欄で移動した地点の名前。その後に地図を動かしたら null
  String? get searchedPlaceName =>
      _isNear(_jumpCenter, _center) ? _jumpName : null;

  /// 検索欄に入力した文字。その後に地図を動かしたら null
  String? get searchedQuery =>
      _isNear(_jumpCenter, _center) ? _jumpQuery : null;

  /// 距離を現在地から測っているか。false なら探した地点から測っている
  bool get measuresFromUser {
    final LatLng? user = _userLocation;
    return user != null &&
        _distance(user, _appliedCenter ?? _center) <= _nearUserMeters;
  }

  bool _isNear(LatLng? a, LatLng b) =>
      a != null && _distance(a, b) <= _movedThresholdMeters;

  static int _distance(LatLng a, LatLng b) =>
      distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude);

  /// このジャンルの選択が、表示中の結果と違うか
  bool isGenrePending(PlaceGenre genre) =>
      _state is SearchLoaded &&
      _genres.contains(genre) != _appliedGenres.contains(genre);

  bool get isRadiusPending =>
      _state is SearchLoaded && _radius != _appliedRadius;

  bool get _conditionsChanged =>
      _radius != _appliedRadius || !setEquals(_genres, _appliedGenres);

  /// 人気度の幅の端（称号の段階。0 未踏〜3 超有名）。称号を選んでいなければ全部
  (int, int) get popularity {
    if (_titles.isEmpty) {
      return (0, PlaceTitle.values.length - 1);
    }
    final List<int> levels = <int>[for (final PlaceTitle t in _titles) t.index]
      ..sort();
    return (levels.first, levels.last);
  }

  /// 有名な場所を含む幅か。含むときはサーバーが人気順でも探す
  static bool _wantsFamous((int, int) p) => p.$2 >= PlaceTitle.known.index;

  /// 知られていない場所を含む幅か。含むときはサーバーが近い順でも探す
  static bool _wantsObscure((int, int) p) => p.$1 <= PlaceTitle.hidden.index;

  /// 人気度の幅を、探し直さないと結果に出ない側へ広げたか
  bool get isPopularityPending {
    if (_state is! SearchLoaded) {
      return false;
    }
    final (int, int) now = popularity;
    return (_wantsFamous(now) && !_wantsFamous(_appliedPopularity)) ||
        (_wantsObscure(now) && !_wantsObscure(_appliedPopularity));
  }

  bool get _moved {
    final LatLng? applied = _appliedCenter;
    return applied == null || !_isNear(applied, _center);
  }

  SearchAction get action => switch (_state) {
    SearchIdle() || SearchFailed() => SearchAction.searchArea,
    SearchLoading() => SearchAction.none,
    SearchLoaded() when _conditionsChanged || isPopularityPending =>
      SearchAction.applyConditions,
    SearchLoaded() when _moved => SearchAction.searchArea,
    SearchLoaded() => SearchAction.none,
  };

  /// 表示中の結果が、今の条件の結果ではないか
  bool get isStale =>
      _state is SearchLoaded &&
      (_conditionsChanged ||
          (_appliedCenter != null &&
              _distance(_appliedCenter!, _center) > _staleThresholdMeters));

  /// 称号で絞り込み、並べ替えた場所
  List<Place> get visiblePlaces {
    final SearchState state = _state;
    if (state is! SearchLoaded) {
      return const <Place>[];
    }
    final int titles = _titles.fold<int>(
      0,
      (int mask, PlaceTitle title) => mask | (1 << title.index),
    );
    final key = (
      state,
      titles,
      _sort,
      _distanceBase,
      _appliedRadius ?? _radius,
    );
    if (key != _visibleKey) {
      _visibleKey = key;
      _visibleCache = List<Place>.unmodifiable(
        _ordered(<Place>[
          for (final Place p in state.places)
            if ((_titles.isEmpty || _titles.contains(PlaceTitle.of(p.title))) &&
                (_favoriteFilter?.call(p.id) ?? true))
              p,
        ]),
      );
    }
    return _visibleCache;
  }

  Place? get selected {
    for (final Place p in visiblePlaces) {
      if (p.id == _selectedId) {
        return p;
      }
    }
    return null;
  }

  /// 距離の基準の地点。現地にいるときは現在地、下調べのときは探した地点にする
  LatLng get _distanceBase =>
      measuresFromUser ? _userLocation! : (_appliedCenter ?? _center);

  /// 現在地から「いまここ」とみなす距離（チェックインのタブの候補と同じ）
  static const int hereRadius = 300;

  /// 現在地のそばにある、探した場所のうち最も近いもの。地図にもチェックインのタブと同じ「押してスタンプ」を出す
  Place? get placeHere {
    final LatLng? user = _userLocation;
    final SearchState state = _state;
    if (user == null || state is! SearchLoaded) {
      return null;
    }
    Place? best;
    int bestDistance = hereRadius + 1;
    for (final Place p in state.places) {
      final int d = distanceMeters(user.latitude, user.longitude, p.lat, p.lng);
      if (d < bestDistance) {
        best = p;
        bestDistance = d;
      }
    }
    return best;
  }

  int distanceTo(Place place) {
    final LatLng base = _distanceBase;
    return distanceMeters(base.latitude, base.longitude, place.lat, place.lng);
  }

  List<Place> _ordered(List<Place> places) {
    final int reach = _appliedRadius ?? _radius;
    double balanced(Place p) => recommendScore(
      p,
      nearness: 1 - (distanceTo(p) / reach).clamp(0.0, 1.0),
    );
    final List<Place> sorted = List<Place>.of(places);
    sorted.sort(
      (Place a, Place b) => switch (_sort) {
        ResultSort.balanced => balanced(b).compareTo(balanced(a)),
        ResultSort.obscure => (b.obscurity ?? 0).compareTo(a.obscurity ?? 0),
        ResultSort.near => distanceTo(a).compareTo(distanceTo(b)),
      },
    );
    return sorted;
  }

  /// 起動時に位置情報の許可を求める。許可されれば現在地へ移動し、それ以外は前回の地点のまま下調べに使える
  Future<void> start() async {
    await goToUserLocation();
  }

  /// 現在地を読んで地図を移動し、位置情報の状態を返す。測定できなければ例外を投げる
  Future<LocationAccess> goToUserLocation() async {
    _locating = true;
    notifyListeners();
    try {
      final LocationAccess access = await location.requestAccess();
      if (access == LocationAccess.granted) {
        final GeoSample here = await location.current();
        _userLocation = LatLng(here.lat, here.lng);
        _center = _userLocation!;
        settings.saveMapCenter(here.lat, here.lng);
      }
      return access;
    } finally {
      _locating = false;
      notifyListeners();
    }
  }

  void moveTo(LatLng center, {bool mapRendersMovement = false}) {
    final SearchAction previousAction = action;
    final bool previousStale = isStale;
    final String? previousName = searchedPlaceName;
    final String? previousQuery = searchedQuery;
    final bool previousDistanceBase = measuresFromUser;
    _center = center;
    // Google マップは自身で移動を描画するため、周囲の表示が変わるときだけ再描画する
    if (!mapRendersMovement ||
        action != previousAction ||
        isStale != previousStale ||
        searchedPlaceName != previousName ||
        searchedQuery != previousQuery ||
        measuresFromUser != previousDistanceBase) {
      notifyListeners();
    }
  }

  /// 検索欄の文字から地点を探し、地図を移動する。探す操作は利用者に任せる。
  /// 移動した先がダミーの地点なら true を返す。探せないときは例外を投げ、地図を動かさない
  Future<bool> jumpTo(String query) async {
    final LocateResult found = await api.locate(query);
    _center = LatLng(found.lat, found.lng);
    _jumpCenter = _center;
    _jumpName = found.name;
    _jumpQuery = query;
    settings.saveMapCenter(found.lat, found.lng);
    notifyListeners();
    return found.isMock;
  }

  /// Geminiちゃんの答えを地図に反映する。[center] へ移動してジャンルを置き換え、[search] が true ならその条件で探す。
  /// [name] は移動した先の名前で、null なら地図を動かしただけとして扱う。
  /// [query] は代わりを探した有名スポットの名前で、地図の上に「代わりを探す」を出すために使う
  void showAssistantResult({
    required LatLng center,
    required Set<PlaceGenre> genres,
    String? name,
    String? query,
    bool search = true,
  }) {
    _center = center;
    _jumpCenter = name == null ? null : center;
    _jumpName = name;
    _jumpQuery = query;
    _genres
      ..clear()
      ..addAll(genres);
    settings.saveMapCenter(center.latitude, center.longitude);
    if (search) {
      this.search();
    } else {
      notifyListeners();
    }
  }

  /// 広い範囲（遠くの地域を見るとき）で探しているか
  bool get isWide => _radius > wideRadius;

  /// 近くを気軽に探す。現在地へ戻り、いちばん狭い範囲で探す。位置情報の状態を返す
  Future<LocationAccess> searchNearby() async {
    final LocationAccess access = await goToUserLocation();
    _radius = radiusSteps.first;
    _jumpCenter = null;
    _jumpName = null;
    _jumpQuery = null;
    search();
    return access;
  }

  /// 遠くの地域を、広い範囲で探す
  void exploreRegion(Region region) {
    _center = LatLng(region.lat, region.lng);
    _jumpCenter = _center;
    _jumpName = region.label;
    _jumpQuery = null;
    _radius = region.radiusMeters;
    settings.saveMapCenter(region.lat, region.lng);
    search();
  }

  /// 地名で遠くの地域へ移動し、広い範囲で探す。移動した先がダミーの地点なら true を返す。
  /// 地名が見つからないときは例外を投げ、地図を動かさない
  Future<bool> exploreFar(String query, {int radius = 20000}) async {
    final bool isMock = await jumpTo(query);
    _radius = radius;
    search();
    return isMock;
  }

  /// Geminiちゃんのおすすめを、探し直さずにそのまま地図と一覧に出す
  void showPlaces({
    required List<Place> places,
    required LatLng center,
    String? name,
    bool isMock = false,
  }) {
    _requestId++;
    _center = center;
    _jumpCenter = name == null ? null : center;
    _jumpName = name;
    _jumpQuery = null;
    _appliedCenter = center;
    _appliedRadius = _radius;
    _appliedGenres = Set<PlaceGenre>.of(_genres);
    // おすすめには定番も入ることがあるので、人気度で隠さない
    _titles
      ..clear()
      ..addAll(PlaceTitle.values);
    _appliedPopularity = (0, PlaceTitle.values.length - 1);
    _selectedId = places.isEmpty ? null : places.first.id;
    _state = SearchLoaded(places: places, isMock: isMock);
    settings.saveMapCenter(center.latitude, center.longitude);
    notifyListeners();
  }

  /// 地点の名前と位置を受け取り、その地域を広い範囲で探す（Geminiちゃんが移動先を答えたとき）
  void exploreWide({
    required LatLng center,
    required String name,
    int radius = 20000,
  }) {
    _center = center;
    _jumpCenter = center;
    _jumpName = name;
    _jumpQuery = null;
    _radius = radius;
    settings.saveMapCenter(center.latitude, center.longitude);
    search();
  }

  void toggleGenre(PlaceGenre genre) {
    if (!_genres.remove(genre)) {
      _genres.add(genre);
    }
    notifyListeners();
  }

  void setRadius(int radius) {
    _radius = radius;
    notifyListeners();
  }

  void toggleTitle(PlaceTitle title) {
    if (!_titles.remove(title)) {
      _titles.add(title);
    }
    notifyListeners();
  }

  /// 人気度の幅を決める。結果の絞り込みはすぐに反映し、幅を広げて探し直しが要るときは [action] で知らせる
  void setPopularity(int min, int max) {
    _titles
      ..clear()
      ..addAll(<PlaceTitle>[
        for (final PlaceTitle t in PlaceTitle.values)
          if (t.index >= min && t.index <= max) t,
      ]);
    notifyListeners();
  }

  /// 人気度の幅を全部にする。有名な場所を探していなければ、そのまま探し直す
  void showAllPopularity() {
    setPopularity(0, PlaceTitle.values.length - 1);
    if (isPopularityPending) {
      search();
    }
  }

  void clearTitles() {
    _titles.clear();
    notifyListeners();
  }

  void setSort(ResultSort sort) {
    _sort = sort;
    notifyListeners();
  }

  void select(Place? place) {
    _selectedId = place?.id;
    notifyListeners();
  }

  /// 探した結果と、検索欄で移動した地点の名前を消し、探す前の状態に戻す。地図の位置は動かさない
  void clearResults() {
    // 探している途中に消したとき、遅れて届いた結果で一覧が戻らないようにする
    _requestId++;
    _state = const SearchIdle();
    _selectedId = null;
    _jumpCenter = null;
    _jumpName = null;
    _jumpQuery = null;
    _appliedCenter = null;
    _appliedRadius = null;
    _visibleKey = null;
    notifyListeners();
  }

  /// 範囲を広げて探す。0件のときの操作なので、確認を挟まずに探す
  void widenAndSearch(int radius) {
    _radius = radius;
    search();
  }

  Future<void> search() async {
    final int requestId = ++_requestId;
    final LatLng center = _center;
    final int radius = _radius;
    final Set<PlaceGenre> genres = Set<PlaceGenre>.of(_genres);
    final (int, int) popularity = this.popularity;
    _state = const SearchLoading();
    _appliedPopularity = popularity;
    _appliedCenter = center;
    _appliedRadius = radius;
    _appliedGenres = genres;
    _selectedId = null;
    settings.saveMapCenter(center.latitude, center.longitude);
    notifyListeners();
    try {
      final ExploreResult result = await api.explore(
        lat: center.latitude,
        lng: center.longitude,
        radius: radius,
        genres: genres,
        popularity: popularity,
      );
      if (requestId != _requestId) {
        return;
      }
      _state = SearchLoaded(places: result.places, isMock: result.isMock);
    } catch (error) {
      if (requestId != _requestId) {
        return;
      }
      _state = SearchFailed(describeError(error));
    }
    notifyListeners();
  }

  int? get nextRadius {
    for (final int step in radiusSteps) {
      if (step > _radius) {
        return step;
      }
    }
    return null;
  }

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    zoom.dispose();
    super.dispose();
  }
}
