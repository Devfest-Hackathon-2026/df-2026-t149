import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../haptics.dart';
import '../maps/maps_support.dart';
import '../models/place.dart';
import '../theme.dart';
import 'map_zoom.dart';
import 'place_labels.dart';
import 'place_pin.dart';
import '../strings.dart';

/// 地図の共通部品。
///
/// 地図のキーが設定されていれば Google マップ、なければ API キーなしで動く簡易表示（[MapsSupport]）。
/// Google マップは地図が止まったときに、簡易表示はドラッグの間に、[onCenterChanged] で新しい中心を知らせる。
class PlacesMap extends StatefulWidget {
  const PlacesMap({
    super.key,
    required this.places,
    required this.center,
    required this.onCenterChanged,
    required this.onTapPlace,
    this.searchRadiusMeters,
    this.selectedPlaceId,
    this.userLocation,
    this.dimmed = false,
    this.showZoomControls = true,
    this.zoom,
  });

  final List<Place> places;

  /// 地図の中心。利用者の操作以外で値が変わると、地図をその地点へ移動する
  final LatLng center;
  final ValueChanged<LatLng> onCenterChanged;
  final ValueChanged<Place> onTapPlace;

  /// 探した範囲の半径。null でなければ、中心からこの半径の円を地図に描く
  final int? searchRadiusMeters;

  /// 選択中の場所。ピンを大きく表示する
  final String? selectedPlaceId;

  /// 現在地。null でなければ青い点を描く
  final LatLng? userLocation;

  /// true なら、今の条件の結果ではないピンとして灰色で表示する
  final bool dimmed;

  /// false なら拡大縮小のボタンを消す。下から引き上げる一覧やタブと重なる画面で使う
  final bool showZoomControls;

  /// 拡大率を拡大・縮小のボタン（[ZoomLever]）とつなぐ。null なら地図だけで拡大・縮小する
  final MapZoomController? zoom;

  @override
  State<PlacesMap> createState() => _PlacesMapState();
}

class _PlacesMapState extends State<PlacesMap> {
  GoogleMapController? _map;
  late LatLng _reportedCenter = widget.center;

  /// 拡大率をつなぐ先がないときに、簡易表示の指での拡大・縮小に使う
  late final MapZoomController _ownZoom = MapZoomController(
    zoom: MapZoomController.zoomForSpan(
      simpleMapSpan(widget.searchRadiusMeters),
    ),
  );

  MapZoomController get _zoom => widget.zoom ?? _ownZoom;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_onZoom);
    _fitSimpleZoom();
  }

  @override
  void dispose() {
    _zoom.removeListener(_onZoom);
    _ownZoom.dispose();
    super.dispose();
  }

  /// ボタンや指で変えたときだけ、Google マップのカメラを動かす
  void _onZoom() {
    final MapZoomController zoom = _zoom;
    if (zoom.fromUser) {
      final CameraUpdate update = CameraUpdate.zoomTo(zoom.zoom);
      if (zoom.animate) {
        _map?.animateCamera(update);
      } else {
        _map?.moveCamera(update);
      }
    }
    if (!MapsSupport.available) {
      setState(() {});
    }
  }

  /// 簡易表示で、探す範囲の円が収まる拡大率にする。作り直しの途中で知らせないよう、描いた後に知らせる
  void _fitSimpleZoom() {
    if (MapsSupport.available) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _zoom.report(
          MapZoomController.zoomForSpan(
            simpleMapSpan(widget.searchRadiusMeters),
          ),
        );
      }
    });
  }

  @override
  void didUpdateWidget(PlacesMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 利用者が動かした値が戻ってきただけならカメラを動かさない。動かすと操作と競合する
    if (widget.center != _reportedCenter) {
      _reportedCenter = widget.center;
      _map?.animateCamera(CameraUpdate.newLatLng(widget.center));
    }
    if (widget.zoom != oldWidget.zoom) {
      (oldWidget.zoom ?? _ownZoom).removeListener(_onZoom);
      _zoom.addListener(_onZoom);
    }
    if (widget.searchRadiusMeters != oldWidget.searchRadiusMeters) {
      _fitRadius();
      _fitSimpleZoom();
    }
  }

  /// 探す範囲の円が収まるように地図を拡大・縮小する
  void _fitRadius() {
    final int? radius = widget.searchRadiusMeters;
    final GoogleMapController? map = _map;
    if (radius == null || map == null) {
      return;
    }
    map.animateCamera(
      CameraUpdate.newLatLngBounds(
        radiusBounds(widget.center, radius.toDouble()),
        32,
      ),
    );
  }

  // onCameraMove を渡すと、Android のプラグインが移動中の毎フレームにカメラの位置を Dart へ送り、慣性で流れる地図の描画と同じフレームを奪い合う。そのため中心は地図が止まったときに読む
  Future<void> _onCameraIdle() async {
    final GoogleMapController? map = _map;
    if (map == null) {
      return;
    }
    final LatLngBounds bounds = await map.getVisibleRegion();
    final double level = await map.getZoomLevel();
    if (!mounted) {
      return;
    }
    // 指での拡大・縮小と、半径に合わせた拡大・縮小をスライダーに戻す
    widget.zoom?.report(level);
    final LatLng center = LatLng(
      (bounds.northeast.latitude + bounds.southwest.latitude) / 2,
      (bounds.northeast.longitude + bounds.southwest.longitude) / 2,
    );
    _reportedCenter = center;
    widget.onCenterChanged(center);
  }

  /// 描いている途中のピンの画像。描き終えたら作り直してマーカーに使う
  final Set<PinStyle> _pendingPins = <PinStyle>{};

  /// ピンの画像。まだ描いていなければ描き始め、描き終えるまでは称号の色の標準のマーカーを使う
  BitmapDescriptor _markerIcon(PinStyle style, double pixelRatio) {
    final BitmapDescriptor? cached = PinBitmaps.cached(style, pixelRatio);
    if (cached != null) {
      return cached;
    }
    if (_pendingPins.add(style)) {
      PinBitmaps.draw(style, pixelRatio).then(
        (_) {
          _pendingPins.remove(style);
          if (mounted) {
            setState(() {});
          }
        },
        onError: (Object _) {
          _pendingPins.remove(style);
        },
      );
    }
    return BitmapDescriptor.defaultMarkerWithHue(
      HSVColor.fromColor(style.fill).hue,
    );
  }

  @override
  Widget build(BuildContext context) {
    final LatLng? user = widget.userLocation;
    if (MapsSupport.available) {
      final TitleColors titleColors = TitleColors.of(context);
      final ColorScheme scheme = Theme.of(context).colorScheme;
      final double pixelRatio = MediaQuery.devicePixelRatioOf(context);
      return GoogleMap(
        initialCameraPosition: CameraPosition(target: widget.center, zoom: 15),
        onMapCreated: (GoogleMapController c) {
          _map = c;
          _fitRadius();
        },
        onCameraIdle: _onCameraIdle,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: widget.showZoomControls,
        // Web 版の Google マップは右下に移動用のボタンを出し、アプリの拡大・縮小やGeminiちゃんのボタンの下に重なるため消す
        webCameraControlEnabled: false,
        circles: <Circle>{
          if (widget.searchRadiusMeters case final int radius)
            Circle(
              circleId: const CircleId('search-radius'),
              center: widget.center,
              radius: radius.toDouble(),
              strokeWidth: 2,
              strokeColor: scheme.primary,
              fillColor: scheme.primary.withValues(alpha: 0.08),
            ),
          if (user != null)
            Circle(
              circleId: const CircleId('user-location'),
              center: user,
              radius: 25,
              strokeWidth: 3,
              strokeColor: Colors.white,
              fillColor: _userColor,
              zIndex: 2,
            ),
        },
        markers: <Marker>{
          for (final Place p in widget.places)
            Marker(
              markerId: MarkerId(p.id),
              position: LatLng(p.lat, p.lng),
              alpha: widget.dimmed ? 0.45 : 1,
              icon: _markerIcon(
                pinStyleFor(
                  p,
                  titleColors.forTitle(PlaceTitle.of(p.title)),
                  selected: p.id == widget.selectedPlaceId,
                  selectedRing: scheme.onSurface,
                ),
                pixelRatio,
              ),
              zIndexInt: p.id == widget.selectedPlaceId ? 1 : 0,
              infoWindow: InfoWindow(
                title: p.name,
                onTap: () => widget.onTapPlace(p),
              ),
              onTap: () => widget.onTapPlace(p),
            ),
        },
      );
    }
    return _SimpleMap(
      places: widget.places,
      center: widget.center,
      onCenterChanged: (LatLng c) {
        _reportedCenter = c;
        widget.onCenterChanged(c);
      },
      onTapPlace: widget.onTapPlace,
      searchRadiusMeters: widget.searchRadiusMeters,
      zoom: _zoom,
      selectedPlaceId: widget.selectedPlaceId,
      userLocation: user,
      dimmed: widget.dimmed,
    );
  }
}

/// 場所のピンの見た目。地の色で称号を、アイコンで種類を表す
PinStyle pinStyleFor(
  Place place,
  TitleColor color, {
  required bool selected,
  required Color selectedRing,
}) => PinStyle(
  icon: pinIconFor(place),
  fill: color.color,
  onFill: color.onColor,
  ring: selected ? selectedRing : Colors.white,
  selected: selected,
);

/// [center] から [radiusMeters] の円を囲む範囲
LatLngBounds radiusBounds(LatLng center, double radiusMeters) {
  final double dLat = radiusMeters / 111000;
  final double dLng =
      radiusMeters /
      (111000 * math.max(0.01, math.cos(center.latitude * math.pi / 180)));
  return LatLngBounds(
    southwest: LatLng(center.latitude - dLat, center.longitude - dLng),
    northeast: LatLng(center.latitude + dLat, center.longitude + dLng),
  );
}

/// 簡易表示で中心から画面の短い辺の端までに見せる度数（緯度）。半径がなければ約 1.3km、あれば円が収まる広さにする
double simpleMapSpan(int? radiusMeters) =>
    math.max(0.012, (radiusMeters ?? 0) / 111000 * 1.25);

/// 現在地の点の色。Google マップの現在地と同じ青にして、ピンと区別する
const Color _userColor = Color(0xFF266EEB);

/// 簡易表示の地図の投影。東西も南北も、1ピクセルあたりの距離を同じにする（円が楕円にならない）。
///
/// 緯度1度は約 111km、経度1度は緯度に応じて cos(緯度) 倍に縮むので、経度は cos(緯度) を掛けて広げる
@immutable
class SimpleProjection {
  SimpleProjection({
    required this.center,
    required this.size,
    required double span,
  }) : pxPerLat = math.min(size.width, size.height) / 2 / span,
       pxPerLng =
           math.min(size.width, size.height) /
           2 /
           span *
           math.max(0.01, math.cos(center.latitude * math.pi / 180));

  final LatLng center;
  final Size size;

  /// 緯度1度あたりのピクセル
  final double pxPerLat;

  /// 経度1度あたりのピクセル
  final double pxPerLng;

  /// 1メートルあたりのピクセル
  double get pxPerMeter => pxPerLat / 111000;

  Offset toPx(double lat, double lng) => Offset(
    size.width / 2 + (lng - center.longitude) * pxPerLng,
    size.height / 2 - (lat - center.latitude) * pxPerLat,
  );

  LatLng fromPx(Offset px) => LatLng(
    center.latitude - (px.dy - size.height / 2) / pxPerLat,
    center.longitude + (px.dx - size.width / 2) / pxPerLng,
  );

  /// [point] が画面の [px] に来るときの、地図の中心
  LatLng centerPlacing(LatLng point, Offset px) => LatLng(
    point.latitude + (px.dy - size.height / 2) / pxPerLat,
    point.longitude - (px.dx - size.width / 2) / pxPerLng,
  );
}

/// Google マップを使わない簡易表示。探す範囲の円が収まる広さに、種類のアイコンのピンを打つ。
///
/// 指1本で動かし、2本の指で広げる・狭めると拡大・縮小する。ダブルタップで拡大、2本指で軽く叩くと縮小、
/// ダブルタップしてそのまま下へなぞると拡大・上へなぞると縮小する（Yahoo!マップと同じ）
class _SimpleMap extends StatefulWidget {
  const _SimpleMap({
    required this.places,
    required this.center,
    required this.onCenterChanged,
    required this.onTapPlace,
    required this.searchRadiusMeters,
    required this.zoom,
    required this.selectedPlaceId,
    required this.userLocation,
    required this.dimmed,
  });

  final List<Place> places;
  final LatLng center;
  final ValueChanged<LatLng> onCenterChanged;
  final ValueChanged<Place> onTapPlace;
  final int? searchRadiusMeters;
  final MapZoomController zoom;
  final String? selectedPlaceId;
  final LatLng? userLocation;
  final bool dimmed;

  @override
  State<_SimpleMap> createState() => _SimpleMapState();
}

class _SimpleMapState extends State<_SimpleMap> {
  /// ダブルタップと見なす、1回目を離してから2回目を押すまでの時間と距離
  static const Duration _doubleTapTime = Duration(milliseconds: 300);
  static const double _doubleTapSlop = 40;

  /// 叩いたと見なす、押してから離すまでの時間と動いた距離
  static const Duration _tapTime = Duration(milliseconds: 250);
  static const double _tapSlop = 12;

  /// ダブルタップしてなぞったとき、この距離（論理ピクセル）で1段変える
  static const double _quickZoomPixelsPerLevel = 150;

  Size _size = Size.zero;

  // 押している指（位置と時刻）
  final Map<int, (Offset, Duration)> _down = <int, (Offset, Duration)>{};
  bool _moved = false;
  Duration? _lastTapUp;
  Offset? _lastTapAt;

  // ダブルタップしてなぞる拡大・縮小
  bool _quick = false;
  bool _quickMoved = false;
  double _quickStartY = 0;
  double _quickStartZoom = 0;

  // 2本指で軽く叩く縮小
  bool _twoFinger = false;
  Duration _twoFingerAt = Duration.zero;

  // 動かす・2本指で拡大・縮小する
  double _scaleStartZoom = 0;
  LatLng? _scaleAnchor;

  SimpleProjection _projection({LatLng? center, double? zoom}) =>
      SimpleProjection(
        center: center ?? widget.center,
        size: _size,
        span: zoom == null
            ? widget.zoom.simpleSpan
            : 0.012 * math.pow(2, 15 - zoom),
      );

  /// 地図の [px] の地点を動かさずに、拡大率を [zoom] にする
  void _zoomAround(Offset px, double zoom, {bool step = false}) {
    final LatLng anchor = _projection().fromPx(px);
    final double z = zoom.clamp(MapZoomController.min, MapZoomController.max);
    if (step) {
      widget.zoom.step((z - widget.zoom.zoom).round());
    } else {
      widget.zoom.setByUser(z);
    }
    widget.onCenterChanged(
      _projection(zoom: widget.zoom.zoom).centerPlacing(anchor, px),
    );
  }

  void _onPointerDown(PointerDownEvent e) {
    _down[e.pointer] = (e.localPosition, e.timeStamp);
    if (_down.length == 1) {
      _moved = false;
      _twoFinger = false;
      final Duration? lastUp = _lastTapUp;
      final Offset? lastAt = _lastTapAt;
      if (lastUp != null &&
          lastAt != null &&
          e.timeStamp - lastUp < _doubleTapTime &&
          (e.localPosition - lastAt).distance < _doubleTapSlop) {
        _quick = true;
        _quickMoved = false;
        _quickStartY = e.localPosition.dy;
        _quickStartZoom = widget.zoom.zoom;
      }
    } else if (_down.length == 2) {
      _quick = false;
      _twoFinger = !_moved;
      _twoFingerAt = e.timeStamp;
    } else {
      _twoFinger = false;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    final (Offset, Duration)? start = _down[e.pointer];
    if (start != null && (e.localPosition - start.$1).distance > _tapSlop) {
      _moved = true;
    }
    if (_quick && _down.length == 1) {
      final double dy = e.localPosition.dy - _quickStartY;
      if (dy.abs() > _tapSlop) {
        _quickMoved = true;
      }
      if (_quickMoved) {
        // 下へなぞると拡大、上へなぞると縮小する
        widget.zoom.setByUser(_quickStartZoom + dy / _quickZoomPixelsPerLevel);
      }
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    final (Offset, Duration)? start = _down.remove(e.pointer);
    if (_down.isNotEmpty || start == null) {
      return;
    }
    if (_quick) {
      _quick = false;
      _lastTapUp = null;
      if (!_quickMoved) {
        Haptics.select();
        _zoomAround(
          e.localPosition,
          widget.zoom.zoom.floorToDouble() + 1,
          step: true,
        );
      }
      return;
    }
    if (_twoFinger) {
      _twoFinger = false;
      if (!_moved && e.timeStamp - _twoFingerAt < _tapTime) {
        Haptics.select();
        widget.zoom.step(-1);
      }
      return;
    }
    if (!_moved && e.timeStamp - start.$2 < _tapTime) {
      _lastTapUp = e.timeStamp;
      _lastTapAt = e.localPosition;
    } else {
      _lastTapUp = null;
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _down.remove(e.pointer);
    if (_down.isEmpty) {
      _quick = false;
      _twoFinger = false;
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _scaleStartZoom = widget.zoom.zoom;
    _scaleAnchor = _projection().fromPx(d.localFocalPoint);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final LatLng? anchor = _scaleAnchor;
    // ダブルタップしてなぞっている間は、地図を動かさずに拡大・縮小だけする
    if (anchor == null || _quick) {
      return;
    }
    // 指の下の地点が指に付いてくるように、中心と拡大率を決める
    if (d.pointerCount >= 2) {
      widget.zoom.setByUser(_scaleStartZoom + math.log(d.scale) / math.ln2);
    }
    widget.onCenterChanged(
      _projection(
        zoom: widget.zoom.zoom,
      ).centerPlacing(anchor, d.localFocalPoint),
    );
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _scaleAnchor = null;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TitleColors titleColors = TitleColors.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        _size = Size(box.maxWidth, box.maxHeight);
        final SimpleProjection proj = _projection();
        final double w = _size.width;
        final double h = _size.height;
        // 選択中のピンを最後に描き、ほかのピンの下に隠れないようにする
        final List<Place> ordered = <Place>[
          ...widget.places.where((Place p) => p.id != widget.selectedPlaceId),
          ...widget.places.where((Place p) => p.id == widget.selectedPlaceId),
        ];
        return Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: ColoredBox(
              color: scheme.surfaceContainer,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GridPainter(
                        color: scheme.outlineVariant,
                        projection: proj,
                      ),
                    ),
                  ),
                  if (widget.searchRadiusMeters case final int radius)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RadiusPainter(
                          radiusPx: radius * proj.pxPerMeter,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  Center(child: _CenterDot(color: scheme.primary)),
                  if (widget.userLocation case final LatLng user)
                    Builder(
                      builder: (BuildContext context) {
                        final Offset o = proj.toPx(
                          user.latitude,
                          user.longitude,
                        );
                        return Positioned(
                          left: o.dx - 8,
                          top: o.dy - 8,
                          child: const _UserDot(),
                        );
                      },
                    ),
                  for (final Place p in ordered)
                    Builder(
                      builder: (BuildContext context) {
                        final Offset o = proj.toPx(p.lat, p.lng);
                        if (o.dx < 0 || o.dy < 0 || o.dx > w || o.dy > h) {
                          return const SizedBox.shrink();
                        }
                        final bool selected = p.id == widget.selectedPlaceId;
                        final TitleColor color = widget.dimmed
                            ? TitleColor(
                                color: scheme.outline,
                                onColor: scheme.surface,
                                container: scheme.surfaceContainer,
                              )
                            : titleColors.forTitle(PlaceTitle.of(p.title));
                        final PinStyle style = pinStyleFor(
                          p,
                          color,
                          selected: selected,
                          selectedRing: scheme.onSurface,
                        );
                        final Size size = style.size;
                        final String type =
                            placeTypeLabel(p.primaryType) ?? l10n.place;
                        final String label = p.reviewCountKnown
                            ? l10n.mapPinLabel(
                                p.name,
                                type,
                                formatCount(p.userRatingCount),
                              )
                            : l10n.mapPinLabelNoReviews(p.name, type);
                        // ピンの先端を地点に合わせる。右上にレビュー数の小さな札を付けるので、その分だけ広げる。
                        // 地図を動かしたときに遅れて付いてこないよう、動きは付けない
                        return Positioned(
                          key: ValueKey<String>(p.id),
                          left: o.dx - size.width / 2,
                          top: o.dy - size.height - 8,
                          width: size.width + 16,
                          height: size.height + 8,
                          child: Semantics(
                            button: true,
                            label: label,
                            child: Tooltip(
                              message: label,
                              triggerMode: TooltipTriggerMode.longPress,
                              showDuration: const Duration(seconds: 2),
                              excludeFromSemantics: true,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => widget.onTapPlace(p),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: <Widget>[
                                    Positioned(
                                      left: 0,
                                      top: 8,
                                      child: PlacePin(style: style),
                                    ),
                                    if (p.reviewCountKnown)
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: _CountBadge(
                                          count: p.userRatingCount,
                                          color: color,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// ピンの右上に付ける、レビュー数の小さな札
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});

  final int count;
  final TitleColor color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.color, width: 1.5),
      ),
      child: Text(
        formatCompactCount(count),
        style: AppTheme.number(10, color: scheme.onSurface),
      ),
    );
  }
}

/// 現在地を表す青い点
class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      color: _userColor,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: <BoxShadow>[
        BoxShadow(color: _userColor.withValues(alpha: 0.25), spreadRadius: 6),
      ],
    ),
  );
}

/// 探す地点の中心を表す点
class _CenterDot extends StatelessWidget {
  const _CenterDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: 0.18),
    ),
    alignment: Alignment.center,
    child: Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2),
      ),
    ),
  );
}

/// 探した範囲を、地図の中心を中心とする円で描く
class _RadiusPainter extends CustomPainter {
  const _RadiusPainter({required this.radiusPx, required this.color});

  final double radiusPx;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      radiusPx,
      Paint()..color = color.withValues(alpha: 0.08),
    );
    canvas.drawCircle(
      c,
      radiusPx,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RadiusPainter oldDelegate) =>
      oldDelegate.radiusPx != radiusPx || oldDelegate.color != color;
}

/// 方眼。きりのよい距離（100m・200m・500m・1km…）ごとに東西と南北の線を引き、正方形のます目にする。
/// 地図と一緒に動き、拡大・縮小する
class _GridPainter extends CustomPainter {
  const _GridPainter({required this.color, required this.projection});

  final Color color;
  final SimpleProjection projection;

  /// 線の間隔の目安（論理ピクセル）
  static const double _targetGap = 48;

  /// 線の間隔をきりのよい値（1・2・5 の 10 のべき乗倍）にする
  static double _niceStep(double value) {
    final double p = math
        .pow(10, (math.log(value) / math.ln10).floor())
        .toDouble();
    for (final double m in <double>[1, 2, 5, 10]) {
      if (p * m >= value) {
        return p * m;
      }
    }
    return p * 10;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final double meters = _niceStep(_targetGap / projection.pxPerMeter);
    final double latStep = meters * projection.pxPerMeter / projection.pxPerLat;
    final double lngStep = meters * projection.pxPerMeter / projection.pxPerLng;
    final LatLng topLeft = projection.fromPx(Offset.zero);
    final LatLng bottomRight = projection.fromPx(
      Offset(size.width, size.height),
    );
    for (
      double lng = (topLeft.longitude / lngStep).floor() * lngStep;
      lng <= bottomRight.longitude;
      lng += lngStep
    ) {
      final double x = projection.toPx(0, lng).dx;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (
      double lat = (bottomRight.latitude / latStep).floor() * latStep;
      lat <= topLeft.latitude;
      lat += latStep
    ) {
      final double y = projection.toPx(lat, projection.center.longitude).dy;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.projection.center != projection.center ||
      oldDelegate.projection.pxPerLat != projection.pxPerLat ||
      oldDelegate.projection.size != projection.size;
}
