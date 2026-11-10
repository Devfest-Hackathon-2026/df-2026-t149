import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../haptics.dart';
import '../strings.dart';

/// 地図の拡大率（Google マップのズームの段階と同じ尺度。大きいほど拡大）。
///
/// [ZoomLever] と [PlacesMap] をつなぐ。レバーやボタンで変えると地図を拡大・縮小し、
/// 指で地図を拡大・縮小すると、地図が止まったときにこの値へ戻す
class MapZoomController extends ChangeNotifier {
  MapZoomController({double zoom = 15}) : _zoom = zoom;

  static const double min = 5;
  static const double max = 19;

  double _zoom;

  /// 利用者がボタンや指で決めた値か。地図はこのときだけカメラを動かす
  bool _fromUser = false;

  /// 動きを付けて移るか（ボタンを1回押したとき）。長押しや指の操作のときは、そのまま移る
  bool _animate = false;

  /// ボタンを押し続けている間か。この間は地図からの知らせで値を戻さない（押し続けている間に、
  /// 少し前の拡大率が地図から戻ってきて、値が行き来するのを防ぐ）
  bool holding = false;

  double get zoom => _zoom;
  bool get fromUser => _fromUser;
  bool get animate => _animate;

  /// 利用者の操作で変える（長押し・指の操作）
  void setByUser(double value) {
    _set(value, fromUser: true, animate: false);
  }

  /// 1段ずつ変える（ボタンを1回押したとき、ダブルタップしたとき）。段の切れ目にそろえる
  void step(int delta) {
    final double base = delta > 0
        ? _zoom.floorToDouble()
        : _zoom.ceilToDouble();
    _set(base + delta, fromUser: true, animate: true);
  }

  /// 地図の側から知らせる（指での拡大・縮小、半径に合わせた拡大・縮小）
  void report(double value) {
    if (holding) {
      return;
    }
    _set(value, fromUser: false, animate: false);
  }

  void _set(double value, {required bool fromUser, required bool animate}) {
    final double v = value.clamp(min, max);
    if ((v - _zoom).abs() < 0.001 && fromUser == _fromUser) {
      return;
    }
    _zoom = v;
    _fromUser = fromUser;
    _animate = animate;
    notifyListeners();
  }

  /// 簡易表示で、中心から画面の短い辺の端までに見せる度数（緯度）。ズーム 15 で約 1.3km（±0.012 度）
  double get simpleSpan => 0.012 * math.pow(2, 15 - _zoom);

  /// 簡易表示で [spanDegrees] を見せるズーム
  static double zoomForSpan(double spanDegrees) =>
      15 - math.log(spanDegrees / 0.012) / math.ln2;
}

/// 地図の拡大・縮小のレバー。上に＋、下に－のボタン、その間にレバーを置く。
///
/// レバーを上へ倒すと拡大、下へ倒すと縮小し続け、大きく倒すほど速く変わる。指を離すとまん中に戻って止まる。
/// ＋と－は押すと1段ずつ、押し続けると続けて変える（Yahoo!マップと同じ）。
/// [compact] のときはレバーを出さず、＋と－だけにする（結果のシートを引き上げて場所が足りないとき）
class ZoomLever extends StatelessWidget {
  const ZoomLever({
    super.key,
    required this.controller,
    this.leverLength = 120,
    this.compact = false,
  });

  final MapZoomController controller;

  /// レバーの溝の長さ
  final double leverLength;
  final bool compact;

  /// ＋と－だけのときの高さ
  static const double compactHeight = _ZoomButton.size * 2 + 1;

  /// レバーを含めた高さ
  static double heightWith(double leverLength) =>
      _ZoomButton.size * 2 + leverLength;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _ZoomButton(
              controller: controller,
              direction: 1,
              tooltip: l10n.zoomIn,
              icon: Icons.add,
              enabled: controller.zoom < MapZoomController.max,
            ),
            if (compact)
              SizedBox(
                width: 32,
                child: Divider(height: 1, color: scheme.outlineVariant),
              )
            else
              _Lever(controller: controller, length: leverLength),
            _ZoomButton(
              controller: controller,
              direction: -1,
              tooltip: l10n.zoomOut,
              icon: Icons.remove,
              enabled: controller.zoom > MapZoomController.min,
            ),
          ],
        ),
      ),
    );
  }
}

/// 倒した分だけ拡大・縮小し続け、離すとまん中に戻るレバー
class _Lever extends StatefulWidget {
  const _Lever({required this.controller, required this.length});

  final MapZoomController controller;
  final double length;

  /// いちばん倒したときに、1秒で変える段の数
  static const double maxLevelsPerSecond = 4;

  /// まん中のあたりで反応しない幅（倒した割合）。触れただけで動かないようにする
  static const double deadZone = 0.12;

  /// つまみの直径
  static const double knob = 30;

  @override
  State<_Lever> createState() => _LeverState();
}

class _LeverState extends State<_Lever> with TickerProviderStateMixin {
  /// 倒した割合。上へ倒すと正（拡大）、下へ倒すと負（縮小）。-1〜1
  double _tilt = 0;
  bool _dragging = false;
  Duration? _lastTick;
  late final Ticker _ticker = createTicker(_onTick);

  /// 離したときに、まん中へ戻す動き
  late final AnimationController _spring =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 260),
      )..addListener(
        () => setState(
          () => _tilt =
              _springFrom * (1 - Curves.easeOutBack.transform(_spring.value)),
        ),
      );
  double _springFrom = 0;

  double get _travel => (widget.length - _Lever.knob) / 2;

  @override
  void dispose() {
    _ticker.dispose();
    _spring.dispose();
    widget.controller.holding = false;
    super.dispose();
  }

  /// 倒した割合から、1秒あたりに変える段の数。まん中の近くはゆっくり、端ほど速くする
  static double rateFor(double tilt) {
    final double t = tilt.abs();
    if (t <= _Lever.deadZone) {
      return 0;
    }
    final double x = (t - _Lever.deadZone) / (1 - _Lever.deadZone);
    return tilt.sign * x * x * _Lever.maxLevelsPerSecond;
  }

  void _onTick(Duration elapsed) {
    final Duration? last = _lastTick;
    _lastTick = elapsed;
    if (last == null) {
      return;
    }
    final double dt = (elapsed - last).inMicroseconds / 1e6;
    final double rate = rateFor(_tilt);
    if (rate == 0) {
      return;
    }
    final MapZoomController c = widget.controller;
    final double before = c.zoom;
    c.setByUser(before + rate * dt);
    if (before.floor() != c.zoom.floor()) {
      Haptics.select();
    }
  }

  void _start(DragStartDetails d) {
    _spring.stop();
    widget.controller.holding = true;
    _dragging = true;
    _lastTick = null;
    if (!_ticker.isActive) {
      _ticker.start();
    }
    Haptics.select();
    _update(d.localPosition.dy);
  }

  void _update(double y) {
    final double center = widget.length / 2;
    setState(() => _tilt = ((center - y) / _travel).clamp(-1.0, 1.0));
  }

  void _end() {
    _ticker.stop();
    _dragging = false;
    widget.controller.holding = false;
    _springFrom = _tilt;
    _spring.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double offset = -_tilt * _travel;
    final Color active = scheme.primary;
    return Semantics(
      label: l10n.zoomLever,
      value: l10n.zoomLevel(widget.controller.zoom.toStringAsFixed(0)),
      increasedValue: l10n.zoomLevel(
        (widget.controller.zoom.floor() + 1)
            .clamp(MapZoomController.min, MapZoomController.max)
            .toStringAsFixed(0),
      ),
      decreasedValue: l10n.zoomLevel(
        (widget.controller.zoom.ceil() - 1)
            .clamp(MapZoomController.min, MapZoomController.max)
            .toStringAsFixed(0),
      ),
      onIncrease: () => widget.controller.step(1),
      onDecrease: () => widget.controller.step(-1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _start,
        onVerticalDragUpdate: (DragUpdateDetails d) =>
            _update(d.localPosition.dy),
        onVerticalDragEnd: (_) => _end(),
        onVerticalDragCancel: _end,
        child: SizedBox(
          width: _ZoomButton.size,
          height: widget.length,
          child: CustomPaint(
            painter: _LeverPainter(
              offset: offset,
              track: scheme.surfaceContainerHighest,
              mark: scheme.outline,
              fill: active.withValues(alpha: 0.35),
              knob: _dragging || _tilt != 0 ? active : scheme.surface,
              knobRing: active,
            ),
          ),
        ),
      ),
    );
  }
}

/// レバーの溝・目盛り・まん中からつまみまでの柄・つまみを描く
class _LeverPainter extends CustomPainter {
  const _LeverPainter({
    required this.offset,
    required this.track,
    required this.mark,
    required this.fill,
    required this.knob,
    required this.knobRing,
  });

  /// つまみのまん中からのずれ（下が正）
  final double offset;
  final Color track;
  final Color mark;
  final Color fill;
  final Color knob;
  final Color knobRing;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    const double slot = 10;
    final RRect groove = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: slot, height: size.height - 8),
      const Radius.circular(slot / 2),
    );
    canvas.drawRRect(groove, Paint()..color = track);
    // まん中の目盛りと、上下の端の目盛り
    final Paint tick = Paint()
      ..color = mark
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c.translate(-12, 0), c.translate(12, 0), tick);
    for (final double dy in <double>[-1, 1]) {
      final double y = c.dy + dy * (size.height / 2 - _Lever.knob / 2);
      canvas.drawLine(
        Offset(c.dx - 6, y),
        Offset(c.dx + 6, y),
        tick..strokeWidth = 1.5,
      );
    }
    final Offset k = c.translate(0, offset);
    // まん中からつまみまでを色で満たし、どちらへ倒しているかを見せる
    if (offset.abs() > 0.5) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromPoints(c.translate(-slot / 2, 0), k.translate(slot / 2, 0)),
          const Radius.circular(slot / 2),
        ),
        Paint()..color = fill,
      );
    }
    canvas.drawCircle(
      k.translate(0, 1.5),
      _Lever.knob / 2,
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(k, _Lever.knob / 2, Paint()..color = knob);
    canvas.drawCircle(
      k,
      _Lever.knob / 2 - 1,
      Paint()
        ..color = knobRing
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_LeverPainter old) =>
      old.offset != offset ||
      old.track != track ||
      old.mark != mark ||
      old.fill != fill ||
      old.knob != knob ||
      old.knobRing != knobRing;
}

/// ＋か－の1つのボタン。押すと1段、押し続けると続けて変える
class _ZoomButton extends StatefulWidget {
  const _ZoomButton({
    required this.controller,
    required this.direction,
    required this.tooltip,
    required this.icon,
    required this.enabled,
  });

  final MapZoomController controller;

  /// 1 なら拡大、-1 なら縮小
  final int direction;
  final String tooltip;
  final IconData icon;
  final bool enabled;

  static const double size = 52;

  /// 押し続けたときに、1秒で変える段の数
  static const double levelsPerSecond = 3.5;

  /// 押し続けたと見なすまでの時間
  static const Duration holdDelay = Duration(milliseconds: 300);

  @override
  State<_ZoomButton> createState() => _ZoomButtonState();
}

class _ZoomButtonState extends State<_ZoomButton> {
  Timer? _repeat;
  bool _pressed = false;

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _tap() {
    if (!widget.enabled) {
      return;
    }
    Haptics.select();
    widget.controller.step(widget.direction);
  }

  void _start() {
    if (!widget.enabled) {
      return;
    }
    Haptics.select();
    final MapZoomController c = widget.controller..holding = true;
    setState(() => _pressed = true);
    const Duration frame = Duration(milliseconds: 16);
    final double delta =
        widget.direction *
        _ZoomButton.levelsPerSecond *
        frame.inMilliseconds /
        1000;
    _repeat = Timer.periodic(frame, (_) {
      final double before = c.zoom;
      c.setByUser(before + delta);
      if (before.floor() != c.zoom.floor()) {
        Haptics.select();
      }
      if (c.zoom <= MapZoomController.min || c.zoom >= MapZoomController.max) {
        _stop();
      }
    });
  }

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
    widget.controller.holding = false;
    if (_pressed && mounted) {
      setState(() => _pressed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.tooltip,
      onTap: widget.enabled ? _tap : null,
      excludeSemantics: true,
      // 長押しでは続けて動かすので、ふきだしは長押しで出さない
      child: Tooltip(
        message: widget.tooltip,
        triggerMode: TooltipTriggerMode.manual,
        excludeFromSemantics: true,
        child: RawGestureDetector(
          gestures: <Type, GestureRecognizerFactory>{
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(
                  () => LongPressGestureRecognizer(
                    duration: _ZoomButton.holdDelay,
                  ),
                  (LongPressGestureRecognizer r) => r
                    ..onLongPressStart = ((_) => _start())
                    ..onLongPressEnd = ((_) => _stop())
                    ..onLongPressCancel = _stop,
                ),
          },
          child: InkWell(
            onTap: widget.enabled ? _tap : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _ZoomButton.size,
              height: _ZoomButton.size,
              color: _pressed
                  ? scheme.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              child: Icon(
                widget.icon,
                color: widget.enabled
                    ? scheme.onSurface
                    : scheme.onSurface.withValues(alpha: 0.38),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
