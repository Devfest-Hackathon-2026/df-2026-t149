import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' show PermissionDeniedException;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/api/uramichi_api.dart';
import '../../core/geo.dart';
import '../../core/location/location_service.dart';
import '../../core/location/visit_recorder.dart';
import '../../core/models/place.dart';
import '../../core/widgets/state_view.dart';

/// チェックインのタブの現在地まわりの状態
sealed class NearbyState {
  const NearbyState();
}

/// タブをまだ開いていない
final class NearbyIdle extends NearbyState {
  const NearbyIdle();
}

final class NearbyLocating extends NearbyState {
  const NearbyLocating();
}

/// 位置情報を使えない
final class NearbyNoAccess extends NearbyState {
  const NearbyNoAccess(this.access);

  final LocationAccess access;
}

/// 現在地を測定できない
final class NearbyNoFix extends NearbyState {
  const NearbyNoFix();
}

/// 候補を読み込み中
final class NearbySearching extends NearbyState {
  const NearbySearching(this.position);

  final GeoSample position;
}

final class NearbyLoaded extends NearbyState {
  const NearbyLoaded({
    required this.position,
    required this.places,
    required this.selectedId,
    required this.isMock,
    required this.isOffline,
  });

  final GeoSample position;

  /// 近い順に並べた候補
  final List<Place> places;
  final String selectedId;
  final bool isMock;

  /// 通信できず、先に読み込んでおいた場所から候補を出している
  final bool isOffline;

  Place get selected => places.firstWhere((Place p) => p.id == selectedId);
}

/// 近くに候補がない
final class NearbyEmpty extends NearbyState {
  const NearbyEmpty(this.position);

  final GeoSample position;
}

/// 通信できず、候補を出せない
final class NearbyOffline extends NearbyState {
  const NearbyOffline(this.position);

  final GeoSample position;
}

/// 近くのスポットを探す1日の上限に達し、候補を出せない
final class NearbyLimited extends NearbyState {
  const NearbyLimited(this.position);

  final GeoSample position;
}

final class NearbyFailed extends NearbyState {
  const NearbyFailed(this.message);

  final String message;
}

/// 行ったかもしれない場所の、スポットの候補の読み込み状態
sealed class VisitSpots {
  const VisitSpots();
}

/// まだ読み込んでいない。位置を不必要にサーバーへ送らないよう、利用者がタブを開くまで読み込まない
final class VisitSpotsIdle extends VisitSpots {
  const VisitSpotsIdle();
}

final class VisitSpotsLoading extends VisitSpots {
  const VisitSpotsLoading();
}

final class VisitSpotsLoaded extends VisitSpots {
  const VisitSpotsLoaded({required this.places, required this.selectedId});

  /// 近い順に並べた候補。0 件のときは [selectedId] が null
  final List<Place> places;
  final String? selectedId;

  Place? get selected {
    for (final Place p in places) {
      if (p.id == selectedId) {
        return p;
      }
    }
    return null;
  }
}

final class VisitSpotsOffline extends VisitSpots {
  const VisitSpotsOffline();
}

/// チェックインのタブの状態。現在地に最も近いスポットを選び、候補の変更を受け付ける
class CheckinTabController extends ChangeNotifier {
  CheckinTabController({
    required this.api,
    required this.location,
    required this.visits,
    required this.start,
    required this.knownPlaces,
    DateTime Function() now = DateTime.now,
  }) : _now = now {
    visits.addListener(_notify);
  }

  /// 候補を探す半径（m）。GPS の誤差があるので、最も近いスポットの隣まで候補に入る広さにする
  static const int searchRadius = 300;

  /// 候補として並べる数
  static const int maxCandidates = 8;

  /// 開くたびに自動で探し直さない間隔。Places API の呼び出しはクレジットを消費する
  static const Duration staleAfter = Duration(minutes: 2);

  /// 開いたときに自動で候補を読み込む、行ったかもしれない場所の数
  static const int autoResolveVisits = 3;

  final UramichiApi api;
  final LocationService location;
  final VisitRecorder visits;

  /// ダミーデータだけで動いていて現在地を使えないときの基準の地点
  final LatLng start;

  /// 別の画面で読み込み済みの場所。圏外でも、これらは候補に出せる
  final List<Place> Function() knownPlaces;
  final DateTime Function() _now;

  NearbyState _state = const NearbyIdle();
  DateTime? _searchedAt;
  int _requestId = 0;
  bool _disposed = false;
  final Map<String, VisitSpots> _spots = <String, VisitSpots>{};

  NearbyState get state => _state;

  VisitSpots spotsOf(Visit visit) => _spots[visit.id] ?? const VisitSpotsIdle();

  void _emit(NearbyState state) {
    _state = state;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// タブを開いたときに呼ぶ。少し前に探したばかりなら、探し直さない
  void open() {
    final DateTime? searchedAt = _searchedAt;
    final bool fresh =
        searchedAt != null &&
        _state is NearbyLoaded &&
        !(_state as NearbyLoaded).isOffline &&
        _now().difference(searchedAt) < staleAfter;
    if (!fresh) {
      refresh();
    }
    _spots.removeWhere((String _, VisitSpots s) => s is VisitSpotsOffline);
    _resolveRecent();
  }

  /// 現在地を読み直し、候補を探し直す
  Future<void> refresh() async {
    final int id = ++_requestId;
    _emit(const NearbyLocating());
    final GeoSample? position = await _readPosition(id);
    if (position == null || id != _requestId) {
      return;
    }
    _emit(NearbySearching(position));
    try {
      final ExploreResult result = await api.exploreForCheckin(
        lat: position.lat,
        lng: position.lng,
        radius: searchRadius,
      );
      if (id != _requestId) {
        return;
      }
      _searchedAt = _now();
      _publish(position, result.places, result.isMock, false);
    } catch (error) {
      if (id != _requestId) {
        return;
      }
      // 上限に達したときは、通信はできるので、地図で読み込んだ場所からならチェックインできる
      final bool limited = isDailyLimit(error);
      if (!limited && !UramichiApi.isUnavailable(error)) {
        _emit(NearbyFailed(describeError(error)));
        return;
      }
      final List<Place> known = <Place>[
        for (final Place p in knownPlaces())
          if (distanceMeters(position.lat, position.lng, p.lat, p.lng) <=
              searchRadius)
            p,
      ];
      if (known.isNotEmpty) {
        _publish(position, known, false, !limited);
      } else {
        _emit(limited ? NearbyLimited(position) : NearbyOffline(position));
      }
    }
  }

  /// Places API の1日の上限に達したという答えか（429 daily_limit）
  static bool isDailyLimit(Object error) =>
      error is ApiException && error.code == 'daily_limit';

  Future<GeoSample?> _readPosition(int id) async {
    final GeoSample fallback = GeoSample(
      lat: start.latitude,
      lng: start.longitude,
      accuracyMeters: 0,
      at: _now(),
    );
    try {
      final LocationAccess access = await location.requestAccess();
      if (access != LocationAccess.granted) {
        if (api.usesMockOnly) {
          return fallback;
        }
        if (id == _requestId) {
          _emit(NearbyNoAccess(access));
        }
        return null;
      }
      return await location.current();
    } catch (error) {
      if (api.usesMockOnly) {
        return fallback;
      }
      debugPrint('現在地を測定できません: $error');
      if (id == _requestId) {
        // Web 版はブラウザで拒否されると、測定の失敗として返る
        _emit(
          error is PermissionDeniedException
              ? const NearbyNoAccess(LocationAccess.denied)
              : const NearbyNoFix(),
        );
      }
      return null;
    }
  }

  void _publish(
    GeoSample position,
    List<Place> places,
    bool isMock,
    bool isOffline,
  ) {
    final List<Place> sorted = _nearestFirst(
      position.lat,
      position.lng,
      places,
    );
    if (sorted.isEmpty) {
      _emit(NearbyEmpty(position));
      return;
    }
    // 探し直しても、利用者が選び直した場所が候補に残っていれば選択を保つ
    final NearbyState previous = _state;
    final String? kept = previous is NearbyLoaded ? previous.selectedId : null;
    _emit(
      NearbyLoaded(
        position: position,
        places: sorted,
        selectedId: sorted.any((Place p) => p.id == kept)
            ? kept!
            : sorted.first.id,
        isMock: isMock,
        isOffline: isOffline,
      ),
    );
  }

  static List<Place> _nearestFirst(double lat, double lng, List<Place> places) {
    final List<Place> sorted = List<Place>.of(places)
      ..sort(
        (Place a, Place b) => distanceMeters(
          lat,
          lng,
          a.lat,
          a.lng,
        ).compareTo(distanceMeters(lat, lng, b.lat, b.lng)),
      );
    return sorted.take(maxCandidates).toList();
  }

  /// 現在地の候補からスポットを選び直す
  void select(String placeId) {
    final NearbyState state = _state;
    if (state is NearbyLoaded) {
      _emit(
        NearbyLoaded(
          position: state.position,
          places: state.places,
          selectedId: placeId,
          isMock: state.isMock,
          isOffline: state.isOffline,
        ),
      );
    }
  }

  /// 行ったかもしれない場所のスポットを選び直す
  void selectForVisit(Visit visit, String placeId) {
    final VisitSpots? spots = _spots[visit.id];
    if (spots is VisitSpotsLoaded) {
      _spots[visit.id] = VisitSpotsLoaded(
        places: spots.places,
        selectedId: placeId,
      );
      _notify();
    }
  }

  void _resolveRecent() {
    for (final Visit visit in visits.visits.take(autoResolveVisits)) {
      if (!_spots.containsKey(visit.id)) {
        resolve(visit);
      }
    }
  }

  /// 行ったかもしれない場所の周りのスポットを読み込む
  Future<void> resolve(Visit visit) async {
    _spots[visit.id] = const VisitSpotsLoading();
    _notify();
    try {
      final ExploreResult result = await api.exploreForCheckin(
        lat: visit.lat,
        lng: visit.lng,
        radius: searchRadius,
      );
      final List<Place> sorted = _nearestFirst(
        visit.lat,
        visit.lng,
        result.places,
      );
      _spots[visit.id] = VisitSpotsLoaded(
        places: sorted,
        selectedId: sorted.isEmpty ? null : sorted.first.id,
      );
    } catch (error) {
      debugPrint('滞在した場所の候補を読み込めません: $error');
      _spots[visit.id] = const VisitSpotsOffline();
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    visits.removeListener(_notify);
    super.dispose();
  }
}
