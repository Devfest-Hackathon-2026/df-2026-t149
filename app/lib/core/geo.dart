import 'dart:math' as math;

/// チェックインできる、場所の代表地点からの距離（m）。サーバーの maxCheckinDistanceMeters と同じ値にする
const int checkinRangeMeters = 500;

/// 2点間の距離（m）。数 km の範囲なので、球面の大円距離で十分な精度になる
int distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const double earthRadius = 6371000;
  final double dLat = _rad(lat2 - lat1);
  final double dLng = _rad(lng2 - lng1);
  final double h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return (2 * earthRadius * math.asin(math.sqrt(h))).round();
}

double _rad(double degree) => degree * math.pi / 180;
