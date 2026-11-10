import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uramichi/core/widgets/map_zoom.dart';
import 'package:uramichi/core/widgets/places_map.dart';

/// 簡易表示の地図（テストでは地図のキーがないので簡易表示になる）
Future<(MapZoomController, ValueNotifier<LatLng>)> _pumpMap(
  WidgetTester tester,
) async {
  final MapZoomController zoom = MapZoomController();
  final ValueNotifier<LatLng> center = ValueNotifier<LatLng>(
    const LatLng(35.68, 139.7),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<LatLng>(
          valueListenable: center,
          builder: (BuildContext context, LatLng c, Widget? _) => PlacesMap(
            places: const [],
            center: c,
            zoom: zoom,
            onCenterChanged: (LatLng next) => center.value = next,
            onTapPlace: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // 初めに半径に合わせた拡大率が入るので、きりのよい値にそろえる
  zoom.setByUser(15);
  await tester.pump();
  return (zoom, center);
}

Future<void> _tapAt(WidgetTester tester, Offset at) async {
  final TestGesture g = await tester.startGesture(at);
  await tester.pump(const Duration(milliseconds: 50));
  await g.up();
}

void main() {
  testWidgets('ダブルタップで1段拡大する', (WidgetTester tester) async {
    final (MapZoomController zoom, _) = await _pumpMap(tester);
    final Offset c = tester.getCenter(find.byType(PlacesMap));
    await _tapAt(tester, c);
    await tester.pump(const Duration(milliseconds: 100));
    await _tapAt(tester, c);
    await tester.pumpAndSettle();
    expect(zoom.zoom, 16);
  });

  testWidgets('2本の指で軽く叩くと1段縮小する', (WidgetTester tester) async {
    final (MapZoomController zoom, _) = await _pumpMap(tester);
    final Offset c = tester.getCenter(find.byType(PlacesMap));
    final TestGesture a = await tester.startGesture(c - const Offset(40, 0));
    final TestGesture b = await tester.startGesture(
      c + const Offset(40, 0),
      pointer: 2,
    );
    await tester.pump(const Duration(milliseconds: 60));
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(zoom.zoom, 14);
  });

  testWidgets('2本の指で広げると拡大し、狭めると縮小する', (WidgetTester tester) async {
    final (MapZoomController zoom, _) = await _pumpMap(tester);
    final Offset c = tester.getCenter(find.byType(PlacesMap));
    final TestGesture a = await tester.startGesture(c - const Offset(50, 0));
    final TestGesture b = await tester.startGesture(
      c + const Offset(50, 0),
      pointer: 2,
    );
    for (int i = 1; i <= 10; i++) {
      await a.moveTo(c - Offset(50.0 + i * 5, 0));
      await b.moveTo(c + Offset(50.0 + i * 5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    // 指の間隔が2倍になったので、1段拡大する
    expect(zoom.zoom, closeTo(16, 0.2));
  });

  testWidgets('ダブルタップしてそのまま下へなぞると拡大、上へなぞると縮小する', (WidgetTester tester) async {
    final (MapZoomController zoom, ValueNotifier<LatLng> center) =
        await _pumpMap(tester);
    final Offset c = tester.getCenter(find.byType(PlacesMap));
    final LatLng before = center.value;

    await _tapAt(tester, c);
    await tester.pump(const Duration(milliseconds: 100));
    TestGesture g = await tester.startGesture(c);
    for (int i = 1; i <= 10; i++) {
      await g.moveTo(c + Offset(0, i * 15.0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(zoom.zoom, closeTo(16, 0.1));
    // なぞっている間は地図を動かさない
    expect(center.value, before);

    await tester.pump(const Duration(milliseconds: 400));
    await _tapAt(tester, c);
    await tester.pump(const Duration(milliseconds: 100));
    g = await tester.startGesture(c);
    for (int i = 1; i <= 10; i++) {
      await g.moveTo(c - Offset(0, i * 30.0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(zoom.zoom, closeTo(14, 0.1));
  });

  testWidgets('指1本で動かすと、指の下の地点が指に付いてくる', (WidgetTester tester) async {
    final (MapZoomController zoom, ValueNotifier<LatLng> center) =
        await _pumpMap(tester);
    final Offset c = tester.getCenter(find.byType(PlacesMap));
    final LatLng before = center.value;
    await tester.dragFrom(c, const Offset(0, 100));
    await tester.pumpAndSettle();
    // 下へ動かすと、地図の中心は北へずれる。拡大率は変わらない
    expect(center.value.latitude, greaterThan(before.latitude));
    expect(center.value.longitude, closeTo(before.longitude, 1e-9));
    expect(zoom.zoom, 15);
  });
}
