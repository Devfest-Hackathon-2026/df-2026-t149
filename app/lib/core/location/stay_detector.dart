import 'package:flutter/foundation.dart';

import '../geo.dart';
import 'location_service.dart';

/// 同じ場所にとどまっていた区間
@immutable
class Stay {
  const Stay({
    required this.lat,
    required this.lng,
    required this.startedAt,
    required this.endedAt,
  });

  final double lat;
  final double lng;
  final DateTime startedAt;
  final DateTime endedAt;
}

/// 位置情報の測定値の並びから、同じ場所での滞在を見つける
///
/// 最初の測定値を基準の点にし、そこから [radiusMeters] 以内の測定値が [minDwell] 以上続くと滞在とみなす
class StayDetector {
  StayDetector();

  factory StayDetector.fromJson(Map<String, dynamic>? json) =>
      StayDetector().._anchor = json == null ? null : _Anchor.fromJson(json);

  /// 小さな祠や公園でも拾えるよう短めにする。誤りは利用者が候補から外せる
  static const Duration minDwell = Duration(minutes: 10);

  /// 屋内の GPS の揺れを同じ場所として扱える広さ
  static const double radiusMeters = 100;

  /// これより粗い測定値は、別の場所に移動したように見えるため使わない
  static const double maxAccuracyMeters = 100;

  /// 測定の間がこれより空くと、その間も同じ場所にいたとは言えないため数え直す
  static const Duration maxGap = Duration(hours: 1);

  _Anchor? _anchor;

  /// 判定の途中の状態。保存しておくと、アプリを開き直しても滞在の続きから数えられる
  Map<String, dynamic>? toJson() => _anchor?.toJson();

  /// 測定値を加える。滞在とみなせる間は、その時点までの滞在を返す
  Stay? add(GeoSample sample) {
    if (sample.accuracyMeters > maxAccuracyMeters) {
      return null;
    }
    final _Anchor? anchor = _anchor;
    if (anchor == null || sample.at.difference(anchor.lastAt) > maxGap) {
      _anchor = _Anchor(sample.lat, sample.lng, sample.at, sample.at);
      return null;
    }
    final bool inside =
        distanceMeters(anchor.lat, anchor.lng, sample.lat, sample.lng) <=
        radiusMeters;
    if (inside) {
      anchor
        ..lastAt = sample.at
        ..outside = false;
    } else if (anchor.outside) {
      // 2 回続けて外れたら移動したとみなす。1 回だけなら GPS の飛びとして無視する
      _anchor = _Anchor(sample.lat, sample.lng, sample.at, sample.at);
      return null;
    } else {
      anchor.outside = true;
      return null;
    }
    if (anchor.lastAt.difference(anchor.startedAt) < minDwell) {
      return null;
    }
    return Stay(
      lat: anchor.lat,
      lng: anchor.lng,
      startedAt: anchor.startedAt,
      endedAt: anchor.lastAt,
    );
  }
}

class _Anchor {
  _Anchor(
    this.lat,
    this.lng,
    this.startedAt,
    this.lastAt, {
    this.outside = false,
  });

  factory _Anchor.fromJson(Map<String, dynamic> j) => _Anchor(
    (j['lat'] as num).toDouble(),
    (j['lng'] as num).toDouble(),
    DateTime.parse(j['startedAt'] as String),
    DateTime.parse(j['lastAt'] as String),
    outside: j['outside'] as bool? ?? false,
  );

  final double lat;
  final double lng;
  final DateTime startedAt;
  DateTime lastAt;
  bool outside;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'lat': lat,
    'lng': lng,
    'startedAt': startedAt.toIso8601String(),
    'lastAt': lastAt.toIso8601String(),
    'outside': outside,
  };
}
