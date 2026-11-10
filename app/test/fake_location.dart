import 'dart:async';

import 'package:uramichi/core/location/location_service.dart';

/// テスト用の位置情報。[access] と [position] を書き換えて状況を作る
class FakeLocationService implements LocationService {
  LocationAccess access = LocationAccess.granted;
  GeoSample? position = GeoSample(
    lat: 34.697,
    lng: 135.192,
    accuracyMeters: 10,
    at: DateTime(2026, 11, 8, 12),
  );
  @override
  bool canTrack = true;
  bool? lastAsk;

  /// バックグラウンドの位置情報の許可の結果
  LocationAccess backgroundAccess = LocationAccess.granted;
  bool backgroundRunning = false;

  @override
  Future<LocationAccess> requestAccess({bool ask = true}) async {
    lastAsk = ask;
    return access;
  }

  @override
  Future<LocationAccess> requestBackgroundAccess({bool ask = true}) async {
    lastAsk = ask;
    return access == LocationAccess.granted ? backgroundAccess : access;
  }

  @override
  Future<GeoSample> current() async {
    final GeoSample? p = position;
    if (p == null) {
      throw TimeoutException('測定できません');
    }
    return p;
  }

  @override
  Future<void> startBackground() async => backgroundRunning = true;

  @override
  Future<void> stopBackground() async => backgroundRunning = false;

  @override
  Future<void> openSettings(LocationAccess access) async {}
}
