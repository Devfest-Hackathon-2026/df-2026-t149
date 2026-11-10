import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uramichi/core/geo.dart';
import 'package:uramichi/core/widgets/map_zoom.dart';
import 'package:uramichi/core/widgets/places_map.dart';
import 'package:uramichi/features/map/map_search_controller.dart';

void main() {
  test('半径は 50km まで広げられる', () {
    expect(MapSearchController.radiusSteps.last, 50000);
    expect(
      MapSearchController.radiusSteps,
      orderedEquals(List<int>.of(MapSearchController.radiusSteps)..sort()),
    );
  });

  test('円を囲む範囲は、中心から半径の距離にある', () {
    const LatLng center = LatLng(36.65, 138.18);
    final LatLngBounds b = radiusBounds(center, 30000);
    int d(double lat, double lng) =>
        distanceMeters(center.latitude, center.longitude, lat, lng);
    expect(d(b.northeast.latitude, center.longitude), closeTo(30000, 300));
    expect(d(center.latitude, b.northeast.longitude), closeTo(30000, 300));
    expect(d(b.southwest.latitude, center.longitude), closeTo(30000, 300));
  });

  test('簡易表示は、半径が広いほど広い範囲を見せる', () {
    expect(simpleMapSpan(null), 0.012);
    expect(simpleMapSpan(1000), 0.012);
    expect(simpleMapSpan(50000), greaterThan(0.45));
    // 円が表示の範囲に収まる
    for (final int r in MapSearchController.radiusSteps) {
      expect(simpleMapSpan(r) * 111000, greaterThanOrEqualTo(r));
    }
  });

  test('ズームは範囲の中に収め、簡易表示の広さと行き来できる', () {
    final MapZoomController z = MapZoomController();
    expect(z.simpleSpan, closeTo(0.012, 1e-9));
    z.setByUser(16);
    expect(z.simpleSpan, closeTo(0.006, 1e-9));
    expect(z.fromUser, isTrue);
    z.report(99);
    expect(z.zoom, MapZoomController.max);
    expect(z.fromUser, isFalse);
    expect(MapZoomController.zoomForSpan(0.024), closeTo(14, 1e-9));
  });

  testWidgets('＋と－を押すと1段ずつ、押し続けると離すまで続けて拡大・縮小する', (WidgetTester tester) async {
    final MapZoomController z = MapZoomController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: ZoomLever(controller: z)),
        ),
      ),
    );
    await tester.tap(find.byTooltip('拡大'));
    await tester.pump();
    expect(z.zoom, 16);
    expect(z.animate, isTrue);
    await tester.tap(find.byTooltip('縮小'));
    await tester.tap(find.byTooltip('縮小'));
    await tester.pump();
    expect(z.zoom, 14);

    // 押し続けると、離すまで少しずつ拡大する
    final TestGesture hold = await tester.startGesture(
      tester.getCenter(find.byTooltip('拡大')),
    );
    await tester.pump(const Duration(milliseconds: 350));
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(z.holding, isTrue);
    expect(z.zoom, greaterThan(16));
    expect(z.animate, isFalse);
    // 押している間は、地図から戻ってきた古い値で戻さない
    z.report(14);
    expect(z.zoom, greaterThan(16));
    await hold.up();
    await tester.pump();
    final double released = z.zoom;
    await tester.pump(const Duration(milliseconds: 300));
    expect(z.zoom, released);
    expect(z.holding, isFalse);
  });

  testWidgets('レバーを上へ倒すと拡大し続け、離すとまん中に戻って止まる。下へ倒すと縮小する', (
    WidgetTester tester,
  ) async {
    final MapZoomController z = MapZoomController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: ZoomLever(controller: z)),
        ),
      ),
    );
    final Finder lever = find.bySemanticsLabel('ズームのレバー');
    final Offset center = tester.getCenter(lever);

    Future<void> hold(Offset by, int frames) async {
      final TestGesture g = await tester.startGesture(center);
      await g.moveBy(by / 2);
      await g.moveBy(by / 2);
      for (int i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(z.holding, isTrue);
      await g.up();
      await tester.pump();
    }

    // 少しだけ動かしても（まん中のあたりでは）変えない
    await hold(const Offset(0, -4), 30);
    expect(z.zoom, 15);

    // 上へ大きく倒すと、倒している間ずっと拡大する
    await hold(const Offset(0, -80), 30);
    final double afterUp = z.zoom;
    expect(afterUp, greaterThan(16));
    expect(z.holding, isFalse);
    // 離したら止まる
    await tester.pumpAndSettle();
    expect(z.zoom, afterUp);

    // 下へ倒すと縮小する。倒し方が小さいほどゆっくり
    await hold(const Offset(0, 30), 30);
    final double slow = afterUp - z.zoom;
    expect(slow, greaterThan(0));
    await tester.pumpAndSettle();
    final double before = z.zoom;
    await hold(const Offset(0, 80), 30);
    expect(before - z.zoom, greaterThan(slow));
  });

  testWidgets('場所が足りないときは、レバーを出さずに＋と－だけにする', (WidgetTester tester) async {
    final MapZoomController z = MapZoomController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: ZoomLever(controller: z, compact: true)),
        ),
      ),
    );
    expect(find.bySemanticsLabel('ズームのレバー'), findsNothing);
    expect(
      tester.getSize(find.byType(ZoomLever)).height,
      closeTo(ZoomLever.compactHeight, 0.5),
    );
    await tester.tap(find.byTooltip('拡大'));
    await tester.pump();
    expect(z.zoom, 16);
  });

  test('1段ずつ変えるときは、段の切れ目にそろえる', () {
    final MapZoomController z = MapZoomController(zoom: 14.6);
    z.step(1);
    expect(z.zoom, 15);
    z.step(-1);
    expect(z.zoom, 14);
  });

  test('簡易表示は、東西と南北で1ピクセルあたりの距離が同じ（円が楕円にならない）', () {
    for (final double lat in <double>[0, 35.68, 43.06, 60]) {
      final SimpleProjection p = SimpleProjection(
        center: LatLng(lat, 139.7),
        size: const Size(400, 900),
        span: 0.012,
      );
      // 中心から北へ 1km と東へ 1km の地点は、画面でも同じ距離になる
      const double km = 1000;
      final Offset north = p.toPx(lat + km / 111000, 139.7);
      final Offset east = p.toPx(
        lat,
        139.7 + km / (111000 * math.cos(lat * math.pi / 180)),
      );
      final Offset c = p.toPx(lat, 139.7);
      expect((north - c).distance, closeTo((east - c).distance, 0.01));
      // 画面の位置から地点に戻せる
      final LatLng back = p.fromPx(const Offset(123, 456));
      expect(p.toPx(back.latitude, back.longitude).dx, closeTo(123, 1e-6));
      expect(p.toPx(back.latitude, back.longitude).dy, closeTo(456, 1e-6));
    }
  });

  test('簡易表示は、探す範囲の円を画面の短い辺に収める', () {
    for (final int r in MapSearchController.radiusSteps) {
      final SimpleProjection p = SimpleProjection(
        center: const LatLng(35.68, 139.7),
        size: const Size(400, 900),
        span: simpleMapSpan(r),
      );
      expect(r * p.pxPerMeter, lessThanOrEqualTo(200));
    }
  });
}
