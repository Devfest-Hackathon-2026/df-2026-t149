import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../haptics.dart';
import '../sounds.dart';
import '../models/place_genre.dart';
import '../theme.dart';
import '../strings.dart';

/// チェックインを祝う「チェックインスタンプ」。御朱印のような朱色のスタンプが、上から画面に押される。
///
/// [level] が上がるほど派手にする。
/// - 前にも来た場所：スタンプが押され、衝撃の輪が1つ広がる
/// - はじめての場所：スタンプが大きく押され、画面が揺れ、朱肉が飛び散り、輪が2つ広がる
/// - 1人目：金色のスタンプになり、後ろで光の筋が回り、「一番乗り」の帯が付く
///
/// 押された後も、画面を閉じるまで動き続ける（光の筋が回り、スタンプが脈打ち、輪が広がり、光が横切り、星がまたたく）。
///
/// スタンプが押された瞬間に [Haptics.checkin] で振動させる。端末でアニメーションを減らす設定のときは、押された後の姿だけを出す
/// チェックインスタンプの種類。場所のジャンルごとに、形・色・模様を変える。
/// 色は御朱印や和の色から選び、1人目（[CelebrationLevel.pioneer]）はどの種類も金色にする
enum StampDesign {
  /// 寺社：朱色の丸いスタンプ（御朱印の形）
  worship(Color(0xFFC53D2B), Icons.temple_buddhist_outlined),

  /// 飲食：藍色の角スタンプ
  food(Color(0xFF2E4B8F), Icons.restaurant),

  /// 公園・庭園：苔色の八角形
  nature(Color(0xFF3F7A3A), Icons.park_outlined),

  /// 美術館：古代紫の角を落としたスタンプ
  culture(Color(0xFF6E3FA3), Icons.museum_outlined),

  /// 展望：浅葱色の六角形
  view(Color(0xFF16788F), Icons.landscape_outlined),

  /// 買い物：琥珀色の角の丸いスタンプ
  shopping(Color(0xFFA65E1A), Icons.shopping_bag_outlined),

  /// どのジャンルにも入らない場所：朱色の丸
  plain(Color(0xFFC53D2B), Icons.place_outlined);

  const StampDesign(this.ink, this.motif);

  String get label => switch (this) {
    worship => l10n.genreWorship,
    food => l10n.genreFood,
    nature => l10n.genreNature,
    culture => l10n.genreCulture,
    view => l10n.genreView,
    shopping => l10n.genreShopping,
    plain => l10n.appTitle,
  };

  /// スタンプの色
  final Color ink;

  /// スタンプの中に薄く描く模様
  final IconData motif;

  /// 文字を置ける幅（スタンプの大きさに対する割合）。丸や多角形は角の内側が狭いので、四角より狭くする
  double get textWidth => switch (this) {
    worship || plain => 0.58,
    nature => 0.6,
    view => 0.56,
    culture => 0.64,
    food || shopping => 0.66,
  };

  static StampDesign of(PlaceGenre? genre) => switch (genre) {
    PlaceGenre.worship => worship,
    PlaceGenre.food => food,
    PlaceGenre.nature => nature,
    PlaceGenre.culture => culture,
    PlaceGenre.view => view,
    PlaceGenre.shopping => shopping,
    PlaceGenre.other || null => plain,
  };

  /// スタンプの形。[side] は枠の線
  OutlinedBorder shape(BorderSide side, double size) => switch (this) {
    worship || plain => CircleBorder(side: side),
    food => RoundedRectangleBorder(
      side: side,
      borderRadius: BorderRadius.circular(size * 0.14),
    ),
    nature => StarBorder.polygon(side: side, sides: 8, pointRounding: 0.2),
    culture => BeveledRectangleBorder(
      side: side,
      borderRadius: BorderRadius.circular(size * 0.2),
    ),
    view => StarBorder.polygon(
      side: side,
      sides: 6,
      rotation: 30,
      pointRounding: 0.15,
    ),
    shopping => RoundedRectangleBorder(
      side: side,
      borderRadius: BorderRadius.circular(size * 0.32),
    ),
  };
}

class StampCelebration extends StatefulWidget {
  const StampCelebration({
    super.key,
    required this.level,
    required this.label,
    this.caption,
    this.size = 220,
    this.haptics = true,
    this.design = StampDesign.plain,
  });

  final CelebrationLevel level;

  /// スタンプの種類（場所のジャンルで決める）
  final StampDesign design;

  /// スタンプの真ん中の大きな文字（「12人目」など）
  final String label;

  /// スタンプの上の小さな文字。null ならアプリの名前を出す
  final String? caption;

  String get captionText => caption ?? l10n.appTitle;

  final double size;

  /// 押された瞬間に振動させるか
  final bool haptics;

  /// 押された後も動き続けるか。ウィジェットのテストでは、終わらないアニメーションで待ち続けないよう false にする
  static bool loop = true;

  @override
  State<StampCelebration> createState() => _StampCelebrationState();
}

class _StampCelebrationState extends State<StampCelebration>
    with TickerProviderStateMixin {
  /// 押された後に繰り返す動きの1回の長さ
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: switch (widget.level) {
        CelebrationLevel.revisit => 1100,
        CelebrationLevel.newPlace => 1500,
        CelebrationLevel.pioneer => 2200,
      },
    ),
  );

  /// スタンプが紙に当たる位置（全体に対する割合）
  static const double _impact = 0.28;
  bool _impacted = false;
  late final List<_Drop> _drops = _makeDrops();

  List<_Drop> _makeDrops() {
    final math.Random r = math.Random(widget.label.hashCode);
    final int n = switch (widget.level) {
      CelebrationLevel.revisit => 0,
      CelebrationLevel.newPlace => 14,
      CelebrationLevel.pioneer => 22,
    };
    return <_Drop>[
      for (int i = 0; i < n; i++)
        _Drop(
          angle: r.nextDouble() * math.pi * 2,
          distance: 0.55 + r.nextDouble() * 0.45,
          size: 3 + r.nextDouble() * 6,
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _c
      ..addListener(_onTick)
      ..addStatusListener((AnimationStatus status) {
        final bool reduced =
            MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        if (status == AnimationStatus.completed &&
            StampCelebration.loop &&
            !reduced &&
            mounted) {
          _idle.repeat();
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_c.status == AnimationStatus.dismissed) {
      if (reduced) {
        _c.value = 1;
        _hitHaptics();
      } else {
        _c.forward();
      }
    }
  }

  void _onTick() {
    if (!_impacted && _c.value >= _impact) {
      _hitHaptics();
    }
  }

  void _hitHaptics() {
    if (_impacted) {
      return;
    }
    _impacted = true;
    if (widget.haptics) {
      Haptics.checkin(widget.level);
      Sounds.stamp();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool gold = widget.level == CelebrationLevel.pioneer;
    final Color ink = gold ? AppTheme.sealGold : widget.design.ink;
    final double strength = switch (widget.level) {
      CelebrationLevel.revisit => 0.6,
      CelebrationLevel.newPlace => 1,
      CelebrationLevel.pioneer => 1.4,
    };
    return Semantics(
      label: l10n.stampLabel(widget.captionText, widget.label),
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_c, _idle]),
          builder: (BuildContext context, Widget? _) {
            final double t = _c.value;
            // 押された後に繰り返す動き（0〜1）。動いていなければ 0
            final double idle = _idle.isAnimating ? _idle.value : 0;
            // スタンプが落ちてくる間（0〜_impact）と、当たった後（_impact〜1）
            final double fall = (t / _impact).clamp(0.0, 1.0);
            final double after = ((t - _impact) / (1 - _impact)).clamp(
              0.0,
              1.0,
            );
            final double breathe = 1 + 0.035 * math.sin(idle * 2 * math.pi);
            final double scale = t < _impact
                ? 3.2 - 2.2 * Curves.easeIn.transform(fall)
                : (1 + 0.1 * math.sin(after * math.pi) * (1 - after)) * breathe;
            final double shake = widget.level == CelebrationLevel.revisit
                ? math.sin(after * 30) * 4 * math.pow(1 - after, 3)
                : math.sin(after * 40) * 14 * math.pow(1 - after, 3);
            return Transform.translate(
              offset: Offset(shake, 0),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RaysPainter(
                        appear: after,
                        // 1回の繰り返しで光の筋1本分だけ回し、つなぎ目なく回り続ける
                        angle: after * math.pi / 6 + idle * math.pi / 6,
                        strength: strength,
                        color: ink,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ImpactPainter(
                        progress: after,
                        rings: switch (widget.level) {
                          CelebrationLevel.revisit => 1,
                          CelebrationLevel.newPlace => 2,
                          CelebrationLevel.pioneer => 3,
                        },
                        drops: _drops,
                        color: ink,
                        pulse: idle,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TwinklePainter(
                        idle: idle,
                        count: switch (widget.level) {
                          CelebrationLevel.revisit => 4,
                          CelebrationLevel.newPlace => 6,
                          CelebrationLevel.pioneer => 9,
                        },
                        color: ink,
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: t < _impact ? 0.3 + 0.7 * fall : 1,
                    child: Transform.rotate(
                      angle: t < _impact ? -0.6 + 0.48 * fall : -0.12,
                      child: Transform.scale(
                        scale: scale,
                        child: Stack(
                          alignment: Alignment.center,
                          children: <Widget>[
                            StampSeal(
                              size: widget.size * 0.62,
                              ink: ink,
                              caption: widget.captionText,
                              label: widget.label,
                              ribbon: gold ? l10n.stampFirst : null,
                              design: widget.design,
                            ),
                            // 繰り返しの前半に、光がスタンプを横切る
                            if (idle > 0 && idle < 0.4)
                              SizedBox.square(
                                dimension: widget.size * 0.62,
                                child: ClipPath(
                                  clipper: ShapeBorderClipper(
                                    shape: widget.design.shape(
                                      BorderSide.none,
                                      widget.size * 0.62,
                                    ),
                                  ),
                                  child: FractionalTranslation(
                                    translation: Offset(-1.2 + 6 * idle, 0),
                                    child: Transform.rotate(
                                      angle: 0.5,
                                      child: const DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: <Color>[
                                              Color(0x00FFFFFF),
                                              Color(0x88FFFFFF),
                                              Color(0x00FFFFFF),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// スタンプの絵（動きのない姿）。チェックインの演出と、実績のページのスタンプ帳で使う。
/// 二重の枠（形は [design] で決める）の中に、薄い模様、上に小さな文字、真ん中に大きな文字を置く
class StampSeal extends StatelessWidget {
  const StampSeal({
    super.key,
    required this.size,
    required this.ink,
    required this.caption,
    required this.label,
    required this.design,
    this.ribbon,
    this.glow = true,
  });

  final StampDesign design;

  /// 周りを朱肉の色でぼかすか。小さく並べるスタンプ帳では、にじんで見えないよう false にする
  final bool glow;

  final double size;
  final Color ink;
  final String caption;
  final String label;
  final String? ribbon;

  @override
  Widget build(BuildContext context) {
    final Color paper = Theme.of(context).colorScheme.surface;
    final String? ribbon = this.ribbon;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            decoration: ShapeDecoration(
              color: paper,
              shape: design.shape(
                BorderSide(color: ink, width: size * 0.045),
                size,
              ),
              shadows: <BoxShadow>[
                if (glow)
                  BoxShadow(color: ink.withValues(alpha: 0.35), blurRadius: 18),
              ],
            ),
            padding: EdgeInsets.all(size * 0.05),
            child: Container(
              decoration: ShapeDecoration(
                shape: design.shape(
                  BorderSide(color: ink, width: size * 0.018),
                  size * 0.9,
                ),
              ),
              alignment: Alignment.center,
              child: Stack(
                alignment: Alignment.center,
                // 飾りをスタンプの内側の全体に描くよう、文字の大きさではなく内側いっぱいに広げる
                fit: StackFit.expand,
                children: <Widget>[
                  // 種類ごとの飾り（数珠・市松・葉・額縁・山並み・暖簾・波）
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _OrnamentPainter(design: design, ink: ink),
                    ),
                  ),
                  // ジャンルの模様
                  Icon(
                    design.motif,
                    size: size * 0.46,
                    color: ink.withValues(alpha: 0.16),
                  ),
                  // 文字の幅は形の内側に収まる広さにし、桁数が増えたら縮める。
                  // 上の小さな文字と真ん中の大きな文字は高さを決めておき、縮めても位置を動かさない
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      SizedBox(
                        width: size * design.textWidth * 0.86,
                        height: size * 0.13,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            caption,
                            maxLines: 1,
                            style: TextStyle(
                              color: ink,
                              fontSize: size * 0.1,
                              fontWeight: FontWeight.w700,
                              letterSpacing: size * 0.02,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: size * design.textWidth,
                        height: size * 0.3,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: AppTheme.number(size * 0.24, color: ink),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (ribbon != null)
            Positioned(
              bottom: -size * 0.06,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: size * 0.1,
                  vertical: size * 0.025,
                ),
                decoration: BoxDecoration(
                  color: ink,
                  borderRadius: BorderRadius.circular(size),
                ),
                child: Text(
                  ribbon,
                  style: TextStyle(
                    color: paper,
                    fontSize: size * 0.09,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Drop {
  const _Drop({
    required this.angle,
    required this.distance,
    required this.size,
  });

  final double angle;

  /// 飛ぶ距離（半径に対する割合）
  final double distance;
  final double size;
}

/// スタンプが当たった衝撃の輪と、飛び散る朱肉
class _ImpactPainter extends CustomPainter {
  _ImpactPainter({
    required this.progress,
    required this.rings,
    required this.drops,
    required this.color,
    this.pulse = 0,
  });

  /// 押された後に繰り返す輪（0〜1）。0 なら描かない
  final double pulse;
  final double progress;
  final int rings;
  final List<_Drop> drops;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) {
      return;
    }
    final Offset c = size.center(Offset.zero);
    final double r = size.shortestSide / 2;
    if (pulse > 0) {
      final double eased = Curves.easeOut.transform(pulse);
      canvas.drawCircle(
        c,
        r * (0.34 + 0.64 * eased),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * (1 - pulse) + 1
          ..color = color.withValues(alpha: (1 - pulse) * 0.45),
      );
    }
    for (int i = 0; i < rings; i++) {
      // 後の輪ほど遅れて広がり、どの輪も最後には消えきる
      final double delay = i * 0.12;
      final double p = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) {
        continue;
      }
      final double eased = Curves.easeOutCubic.transform(p);
      canvas.drawCircle(
        c,
        r * (0.32 + 0.68 * eased),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 * (1 - p) + 1
          ..color = color.withValues(alpha: (1 - p) * 0.7),
      );
    }
    final double fly = Curves.easeOutQuart.transform(progress.clamp(0.0, 1.0));
    final Paint dot = Paint()
      ..color = color.withValues(alpha: (1 - progress).clamp(0.0, 1.0));
    for (final _Drop d in drops) {
      final double dist = r * (0.3 + d.distance * 0.7 * fly);
      canvas.drawCircle(
        c + Offset(math.cos(d.angle) * dist, math.sin(d.angle) * dist),
        d.size * (1 - progress * 0.6),
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(_ImpactPainter old) =>
      old.progress != progress || old.pulse != pulse;
}

/// スタンプの後ろで回る光の筋。祝い方が強いほど濃く長い
class _RaysPainter extends CustomPainter {
  _RaysPainter({
    required this.appear,
    required this.angle,
    required this.strength,
    required this.color,
  });

  /// 光の筋が伸びる進み具合（0〜1）
  final double appear;
  final double angle;
  final double strength;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (appear <= 0) {
      return;
    }
    final Offset c = size.center(Offset.zero);
    final double r =
        size.shortestSide / 2 * (0.75 + 0.25 * strength.clamp(0, 1));
    final double grow = Curves.easeOut.transform((appear * 2).clamp(0.0, 1.0));
    final Paint paint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          color.withValues(alpha: (0.30 * strength).clamp(0.0, 0.45)),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    const int n = 12;
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(angle);
    for (int i = 0; i < n; i++) {
      final double a = i * 2 * math.pi / n;
      final double len = r * grow;
      final Path ray = Path()
        ..moveTo(0, 0)
        ..lineTo(math.cos(a - 0.12) * len, math.sin(a - 0.12) * len)
        ..lineTo(math.cos(a + 0.12) * len, math.sin(a + 0.12) * len)
        ..close();
      canvas.drawPath(ray, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RaysPainter old) =>
      old.appear != appear || old.angle != angle;
}

/// 押された後に、スタンプのまわりでまたたく星
class _TwinklePainter extends CustomPainter {
  _TwinklePainter({
    required this.idle,
    required this.count,
    required this.color,
  });

  final double idle;
  final int count;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (idle <= 0) {
      return;
    }
    final Offset c = size.center(Offset.zero);
    final double r = size.shortestSide * 0.42;
    for (int i = 0; i < count; i++) {
      final double phase = (idle + i / count) % 1;
      final double twinkle = math.sin(phase * math.pi);
      final double a = i * 2 * math.pi / count + idle * math.pi / 3;
      final Offset o = c + Offset(math.cos(a) * r, math.sin(a) * r);
      final double s = 3 + 5 * twinkle;
      final Paint paint = Paint()
        ..color = Color.lerp(
          color,
          AppTheme.starColor,
          0.5,
        )!.withValues(alpha: twinkle.clamp(0.0, 1.0));
      final Path star = Path();
      for (int k = 0; k < 8; k++) {
        final double ang = k * math.pi / 4;
        final double len = k.isEven ? s : s * 0.3;
        final Offset p = o + Offset(math.cos(ang) * len, math.sin(ang) * len);
        k == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(star..close(), paint);
    }
  }

  @override
  bool shouldRepaint(_TwinklePainter old) => old.idle != idle;
}

/// スタンプの種類ごとの飾り。形と色だけでなく、ひと目で種類がわかる模様を、文字の邪魔にならない縁に描く
class _OrnamentPainter extends CustomPainter {
  _OrnamentPainter({required this.design, required this.ink});

  final StampDesign design;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Offset c = size.center(Offset.zero);
    final Paint fill = Paint()..color = ink.withValues(alpha: 0.55);
    final Paint soft = Paint()..color = ink.withValues(alpha: 0.28);
    switch (design) {
      case StampDesign.worship:
        // 数珠：縁に沿って玉を並べ、上に大きな玉（宝珠）を置く
        for (int i = 0; i < 24; i++) {
          final double a = 2 * math.pi * i / 24 - math.pi / 2;
          final Offset p = c + Offset(math.cos(a), math.sin(a)) * w * 0.41;
          canvas.drawCircle(p, i == 0 ? w * 0.035 : w * 0.017, fill);
        }
      case StampDesign.food:
        // 市松：下に、色と白の四角を互い違いに並べた帯（文字に重ねない）
        final double cell = w * 0.07;
        for (final double y in <double>[h * 0.92 - cell * 2]) {
          for (int row = 0; row < 2; row++) {
            for (int col = 0; col * cell < w * 0.7; col++) {
              if ((row + col).isEven) {
                canvas.drawRect(
                  Rect.fromLTWH(
                    w * 0.15 + col * cell,
                    y + row * cell,
                    cell,
                    cell,
                  ),
                  soft,
                );
              }
            }
          }
        }
      case StampDesign.nature:
        // 葉：八角形の角ごとに、外を向いた葉を置く。真ん中の文字にかからないよう、縁に寄せる
        for (int i = 0; i < 8; i++) {
          final double a = 2 * math.pi * i / 8 + math.pi / 8;
          final Offset p = c + Offset(math.cos(a), math.sin(a)) * w * 0.42;
          canvas
            ..save()
            ..translate(p.dx, p.dy)
            ..rotate(a);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: w * 0.09,
              height: w * 0.045,
            ),
            fill,
          );
          canvas.restore();
        }
      case StampDesign.culture:
        // 額縁：四隅に鉤の形の飾り
        final Paint line = Paint()
          ..color = ink.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.025;
        final double m = w * 0.16;
        final double l = w * 0.13;
        for (final (double x, double y, double dx, double dy)
            in <(double, double, double, double)>[
              (m, m, 1, 1),
              (w - m, m, -1, 1),
              (m, h - m, 1, -1),
              (w - m, h - m, -1, -1),
            ]) {
          canvas.drawPath(
            Path()
              ..moveTo(x, y + dy * l)
              ..lineTo(x, y)
              ..lineTo(x + dx * l, y),
            line,
          );
          canvas.drawCircle(
            Offset(x + dx * l * 0.45, y + dy * l * 0.45),
            w * 0.015,
            fill,
          );
        }
      case StampDesign.view:
        // 山並みと日：下に重なる山、右上に丸い日
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.12, h * 0.82)
            ..lineTo(w * 0.36, h * 0.6)
            ..lineTo(w * 0.5, h * 0.72)
            ..lineTo(w * 0.66, h * 0.55)
            ..lineTo(w * 0.88, h * 0.82)
            ..close(),
          soft,
        );
        canvas.drawCircle(Offset(w * 0.8, h * 0.2), w * 0.045, fill);
      case StampDesign.shopping:
        // 暖簾：上から下がる3枚の布と、布をかける竿
        canvas.drawRect(
          Rect.fromLTWH(w * 0.16, h * 0.08, w * 0.68, h * 0.02),
          fill,
        );
        final double pw = w * 0.2;
        for (int i = 0; i < 3; i++) {
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              Rect.fromLTWH(
                w * 0.18 + i * (pw + w * 0.02),
                h * 0.1,
                pw,
                h * 0.1,
              ),
              bottomLeft: Radius.circular(w * 0.02),
              bottomRight: Radius.circular(w * 0.02),
            ),
            soft,
          );
        }
      case StampDesign.plain:
        // 波：下に重なる波の模様（青海波）
        final Paint wave = Paint()
          ..color = ink.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.018;
        for (int i = 0; i < 4; i++) {
          final Offset o = Offset(w * (0.26 + i * 0.16), h * 0.92);
          for (final double r in <double>[0.07, 0.04]) {
            canvas.drawArc(
              Rect.fromCircle(center: o, radius: w * r),
              math.pi,
              math.pi,
              false,
              wave,
            );
          }
        }
    }
  }

  @override
  bool shouldRepaint(_OrnamentPainter old) =>
      old.design != design || old.ink != ink;
}
