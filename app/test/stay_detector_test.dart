import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/core/location/location_service.dart';
import 'package:uramichi/core/location/stay_detector.dart';

const double _lat = 34.697;
const double _lng = 135.192;

/// 緯度 0.001 度はおよそ 111 m
GeoSample _at(int minutes, {double dLat = 0, double accuracy = 10}) =>
    GeoSample(
      lat: _lat + dLat,
      lng: _lng,
      accuracyMeters: accuracy,
      at: DateTime(2026, 11, 8, 12).add(Duration(minutes: minutes)),
    );

void main() {
  group('滞在の判定', () {
    test('同じ場所に 10 分未満なら滞在としない', () {
      final StayDetector d = StayDetector();
      expect(d.add(_at(0)), isNull);
      expect(d.add(_at(9)), isNull);
    });

    test('同じ場所に 10 分いると、始まりからの滞在を返す', () {
      final StayDetector d = StayDetector()..add(_at(0));
      final Stay? stay = d.add(_at(10));
      expect(stay?.startedAt, _at(0).at);
      expect(stay?.endedAt, _at(10).at);
    });

    test('とどまり続けると滞在の終わりが延びる', () {
      final StayDetector d = StayDetector()
        ..add(_at(0))
        ..add(_at(10));
      expect(d.add(_at(30))?.endedAt, _at(30).at);
    });

    test('精度の粗い測定値は使わない', () {
      final StayDetector d = StayDetector()..add(_at(0));
      expect(d.add(_at(10, dLat: 0.01, accuracy: 500)), isNull);
      expect(d.add(_at(12))?.startedAt, _at(0).at);
    });

    test('1 回だけ外れた測定値は GPS の飛びとして無視する', () {
      final StayDetector d = StayDetector()..add(_at(0));
      expect(d.add(_at(5, dLat: 0.01)), isNull);
      expect(d.add(_at(10))?.startedAt, _at(0).at);
    });

    test('2 回続けて外れると移動したとみなし、新しい場所で数え直す', () {
      final StayDetector d = StayDetector()
        ..add(_at(0))
        ..add(_at(5, dLat: 0.01));
      expect(d.add(_at(10, dLat: 0.01)), isNull);
      expect(d.add(_at(20, dLat: 0.01))?.startedAt, _at(10).at);
    });

    test('測定の間が 1 時間を超えると数え直す', () {
      final StayDetector d = StayDetector()..add(_at(0));
      expect(d.add(_at(61)), isNull);
      expect(d.add(_at(71))?.startedAt, _at(61).at);
    });

    test('保存した状態から続きを数えられる', () {
      final StayDetector before = StayDetector()..add(_at(0));
      final StayDetector after = StayDetector.fromJson(before.toJson());
      expect(after.add(_at(10))?.startedAt, _at(0).at);
    });
  });
}
