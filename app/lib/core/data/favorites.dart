import 'package:flutter/foundation.dart';

import '../api/uramichi_api.dart';
import '../models/place.dart';

/// お気に入りの1件。[place] は場所の名前と位置を読めなかったとき null
@immutable
class FavoriteEntry {
  const FavoriteEntry({required this.placeId, this.place});

  final String placeId;
  final Place? place;
}

/// お気に入りの場所（担当：C）。
///
/// 本物の場所はサーバーに place ID だけを保存し、名前と位置は一覧を開いたときに読み直す
/// （Google Maps の規約で、place ID のほかは保存しないため）。
/// ダミーの場所（[Place.isMock]）は本物の Places API で読めないので、この端末の中だけで覚える。
/// どの場所に★を付けたかは [isFavorite] で、Places API を呼ばずに分かる
class FavoritesController extends ChangeNotifier {
  FavoritesController({required this.api});

  final UramichiApi api;

  final Set<String> _ids = <String>{};

  /// ダミーの場所。場所の内容は自分たちが作ったデータなので、名前と位置も覚えてよい
  final Map<String, Place> _mockPlaces = <String, Place>{};

  /// 切り替えの途中の場所
  final Set<String> _changing = <String>{};

  String? _uid;
  int _generation = 0;

  bool isFavorite(String placeId) => _ids.contains(placeId);

  bool isChanging(String placeId) => _changing.contains(placeId);

  int get count => _ids.length;

  /// 利用者を切り替えて、お気に入りの place ID を読み直す。ログアウトしたときは null を渡す
  Future<void> setUser(String? uid) async {
    if (uid == _uid) {
      return;
    }
    _uid = uid;
    final int generation = ++_generation;
    _ids.clear();
    _mockPlaces.clear();
    _changing.clear();
    notifyListeners();
    if (uid == null || api.usesMockOnly) {
      return;
    }
    try {
      final List<String> ids = await api.fetchFavoriteIds();
      if (generation != _generation) {
        return;
      }
      _ids.addAll(ids);
      notifyListeners();
    } catch (error) {
      // 読めなくても場所は探せる。★は次に開いたときに読み直す
      debugPrint('お気に入りを読めません: $error');
    }
  }

  /// ★を付け外しする。サーバーに送れなかったら元に戻して例外を投げる
  Future<void> toggle(Place place) async {
    final String id = place.id;
    if (_changing.contains(id)) {
      return;
    }
    final bool next = !_ids.contains(id);
    _set(id, next, place);
    if (place.isMock || api.usesMockOnly) {
      notifyListeners();
      return;
    }
    final int generation = _generation;
    _changing.add(id);
    notifyListeners();
    try {
      if (next) {
        await api.putFavorite(id);
      } else {
        await api.deleteFavorite(id);
      }
    } catch (_) {
      // 送っている間に利用者が切り替わっていたら、今の利用者のお気に入りは戻さない
      if (generation == _generation) {
        _set(id, !next, place);
      }
      rethrow;
    } finally {
      if (generation == _generation) {
        _changing.remove(id);
        notifyListeners();
      }
    }
  }

  void _set(String id, bool on, Place place) {
    if (on) {
      _ids.add(id);
      if (place.isMock) {
        _mockPlaces[id] = place;
      }
    } else {
      _ids.remove(id);
      _mockPlaces.remove(id);
    }
  }

  /// お気に入りの一覧（新しい順）。本物の場所は名前と位置をサーバーから読む
  Future<List<FavoriteEntry>> list() async {
    final List<FavoriteEntry> mock = <FavoriteEntry>[
      for (final MapEntry<String, Place> e
          in _mockPlaces.entries.toList().reversed)
        FavoriteEntry(placeId: e.key, place: e.value),
    ];
    if (api.usesMockOnly || _uid == null) {
      return mock;
    }
    final int generation = _generation;
    final List<FavoriteEntry> remote = await api.fetchFavorites();
    // 読んでいる間に利用者が切り替わっていたら、前の利用者の一覧を返さず、今の利用者のお気に入りも変えない
    if (generation != _generation) {
      return const <FavoriteEntry>[];
    }
    // ほかの端末で付け外ししたものも反映する
    _ids
      ..removeWhere((String id) => !_mockPlaces.containsKey(id))
      ..addAll(<String>[for (final FavoriteEntry e in remote) e.placeId]);
    notifyListeners();
    return <FavoriteEntry>[...mock, ...remote];
  }
}
