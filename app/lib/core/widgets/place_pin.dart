import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/place.dart';
import '../models/place_genre.dart';
import 'place_labels.dart';

/// ジャンルを表すアイコン。地図の絞り込みのチップと、種類が分からない場所のピンに使う
const Map<PlaceGenre, IconData> genreIcons = <PlaceGenre, IconData>{
  PlaceGenre.food: Icons.restaurant,
  PlaceGenre.nature: Icons.park_outlined,
  PlaceGenre.worship: Icons.temple_buddhist_outlined,
  PlaceGenre.culture: Icons.museum_outlined,
  PlaceGenre.view: Icons.landscape_outlined,
  PlaceGenre.shopping: Icons.shopping_bag_outlined,
  PlaceGenre.other: Icons.more_horiz,
};

/// 地図のピンに描く、場所の種類のアイコン。
/// 一覧のカードと同じアイコン（[placeTypeIcon]）を使い、表にない種類はジャンルのアイコンにする
IconData pinIconFor(Place place) {
  final IconData byType = placeTypeIcon(place.primaryType);
  if (byType != Icons.place_outlined) {
    return byType;
  }
  for (final String t in place.types) {
    final IconData i = placeTypeIcon(t);
    if (i != Icons.place_outlined) {
      return i;
    }
  }
  return switch (PlaceGenre.of(place)) {
    final PlaceGenre g when g != PlaceGenre.other => genreIcons[g]!,
    _ => Icons.place,
  };
}

/// しずく形のピンの見た目
@immutable
class PinStyle {
  const PinStyle({
    required this.icon,
    required this.fill,
    required this.onFill,
    required this.ring,
    this.selected = false,
  });

  final IconData icon;

  /// ピンの地の色（称号の色）
  final Color fill;

  /// アイコンの色
  final Color onFill;

  /// ふちの色
  final Color ring;
  final bool selected;

  /// 論理ピクセルでの大きさ。先端が地点に来る
  Size get size => selected ? const Size(46, 58) : const Size(36, 46);

  @override
  bool operator ==(Object other) =>
      other is PinStyle &&
      other.icon == icon &&
      other.fill == fill &&
      other.onFill == onFill &&
      other.ring == ring &&
      other.selected == selected;

  @override
  int get hashCode => Object.hash(icon, fill, onFill, ring, selected);
}

/// しずく形のピンを描く。丸い頭に種類のアイコンを入れ、先端を地点に合わせる
void paintPin(Canvas canvas, Size size, PinStyle style) {
  final double w = size.width;
  final double h = size.height;
  final double r = w / 2 - 2;
  final Offset head = Offset(w / 2, r + 2);
  final Offset tip = Offset(w / 2, h - 1.5);
  final Path path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..cubicTo(
      tip.dx - r * 0.35,
      tip.dy - r * 0.55,
      head.dx - r,
      head.dy + r * 0.75,
      head.dx - r,
      head.dy,
    )
    ..arcToPoint(Offset(head.dx + r, head.dy), radius: Radius.circular(r))
    ..cubicTo(
      head.dx + r,
      head.dy + r * 0.75,
      tip.dx + r * 0.35,
      tip.dy - r * 0.55,
      tip.dx,
      tip.dy,
    )
    ..close();
  canvas.drawShadow(path, const Color(0xFF000000), 2, false);
  canvas.drawPath(path, Paint()..color = style.fill);
  canvas.drawPath(
    path,
    Paint()
      ..color = style.ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.selected ? 3 : 2,
  );
  final TextPainter text = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: String.fromCharCode(style.icon.codePoint),
      style: TextStyle(
        fontFamily: style.icon.fontFamily,
        package: style.icon.fontPackage,
        fontSize: r * 1.15,
        color: style.onFill,
        height: 1,
      ),
    ),
  )..layout();
  text.paint(canvas, head - Offset(text.width / 2, text.height / 2));
  text.dispose();
}

/// 簡易表示の地図に置くピン
class PlacePin extends StatelessWidget {
  const PlacePin({super.key, required this.style});

  final PinStyle style;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: style.size, painter: _PinPainter(style));
}

class _PinPainter extends CustomPainter {
  const _PinPainter(this.style);

  final PinStyle style;

  @override
  void paint(Canvas canvas, Size size) => paintPin(canvas, size, style);

  @override
  bool shouldRepaint(_PinPainter oldDelegate) => oldDelegate.style != style;
}

/// Google マップのマーカーの画像。同じ見た目は一度だけ描いて使い回す
abstract final class PinBitmaps {
  static final Map<(PinStyle, double), BitmapDescriptor> _done =
      <(PinStyle, double), BitmapDescriptor>{};
  static final Map<(PinStyle, double), Future<BitmapDescriptor>> _drawing =
      <(PinStyle, double), Future<BitmapDescriptor>>{};

  /// 描き終えていれば画像を返す。まだなら null
  static BitmapDescriptor? cached(PinStyle style, double pixelRatio) =>
      _done[(style, pixelRatio)];

  /// 画像を描く。描き終えたら [cached] でも返る
  static Future<BitmapDescriptor> draw(PinStyle style, double pixelRatio) =>
      _drawing[(style, pixelRatio)] ??= _draw(style, pixelRatio);

  static Future<BitmapDescriptor> _draw(
    PinStyle style,
    double pixelRatio,
  ) async {
    final Size size = style.size;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder)..scale(pixelRatio);
    paintPin(canvas, size, style);
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(
      (size.width * pixelRatio).ceil(),
      (size.height * pixelRatio).ceil(),
    );
    picture.dispose();
    final ByteData? png = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    final BitmapDescriptor out = BitmapDescriptor.bytes(
      png!.buffer.asUint8List(),
      width: size.width,
      height: size.height,
    );
    _done[(style, pixelRatio)] = out;
    return out;
  }
}
