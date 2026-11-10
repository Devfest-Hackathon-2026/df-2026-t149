import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/widgets/google_maps_notice.dart';

import '../../core/auth/account_controller.dart';
import '../../core/theme.dart';
import '../../core/widgets/place_pin.dart';
import '../../core/strings.dart';

/// Google アカウントでログインする画面。
///
/// 上半分に、有名スポットから路地裏の穴場へ抜ける道を描いた地図を置き、ピンを順に落として
/// アプリの使い方（有名な所の代わりに、知られていない所へ）を一目で伝える。演出は一度だけ動く
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.account});

  final AccountController account;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.status == AnimationStatus.dismissed) {
      // 動きを減らす設定の端末では、最後の絵だけを見せる
      if (MediaQuery.disableAnimationsOf(context)) {
        _intro.value = 1;
      } else {
        _intro.forward();
      }
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TitleColors titles = TitleColors.of(context);
    final AccountController account = widget.account;
    final AccountState state = account.state;
    final bool signingIn = state is AccountSigningIn;
    final String? error = state is AccountSignedOut ? state.error : null;

    // 文字と案内は、地図の演出の後半で下から浮かび上がらせる
    final Animation<double> reveal = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
    );

    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      body: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ExcludeSemantics(
                  child: AnimatedBuilder(
                    animation: _intro,
                    builder: (BuildContext context, Widget? _) => CustomPaint(
                      painter: _MapPainter(
                        progress: _intro.value,
                        ground: scheme.surfaceContainer,
                        block: scheme.surfaceContainerHighest,
                        road: scheme.surfaceContainerLowest,
                        route: scheme.primary,
                        famous: titles.famous,
                        pins: <(TitleColor, IconData)>[
                          (titles.hidden, Icons.local_cafe_outlined),
                          (titles.untrodden, Icons.temple_buddhist_outlined),
                          (titles.hidden, Icons.park_outlined),
                          (titles.untrodden, Icons.museum_outlined),
                        ],
                      ),
                    ),
                  ),
                ),
                // 地図と下の案内の境目をなじませる
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 48,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            scheme.surfaceContainer.withValues(alpha: 0),
                            scheme.surfaceContainer.withValues(alpha: 0.6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTheme.radiusSheet),
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 24,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        FadeTransition(
                          opacity: reveal,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.25),
                              end: Offset.zero,
                            ).animate(reveal),
                            child: _Intro(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (error != null) ...<Widget>[
                          _ErrorBanner(message: error),
                          const SizedBox(height: 16),
                        ],
                        _GoogleButton(
                          signingIn: signingIn,
                          onPressed: signingIn ? null : account.signIn,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.loginPrivacy,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const GoogleMapsTermsNotice(
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// アプリの名前、ひとこと、できることの3行
class _Intro extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            // ホーム画面のアイコンと同じ絵にして、ログインした後に開くアプリと結び付ける
            Image.asset(
              'assets/images/app_icon.png',
              width: 56,
              height: 56,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.appTitle,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    l10n.appTagline,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          l10n.appLead,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _Feature(icon: Icons.travel_explore, text: l10n.loginFeatureSearch),
        _Feature(icon: Icons.approval_outlined, text: l10n.loginFeatureStamp),
        _Feature(
          icon: Icons.military_tech_outlined,
          text: l10n.loginFeatureBadge,
        ),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Google のブランドの指針に沿った、白地に枠線と G のロゴのボタン
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.signingIn, required this.onPressed});

  final bool signingIn;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: scheme.onSurface,
        backgroundColor: scheme.surfaceContainerLowest,
        side: BorderSide(color: scheme.outline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (signingIn)
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            Image.asset('assets/images/google_g.png', width: 20, height: 20),
          const SizedBox(width: 12),
          Text(signingIn ? l10n.loggingIn : l10n.loginWithGoogle),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 街区と道を簡略化した地図に、有名スポットから路地裏の穴場をつなぐ道を描く。
///
/// [progress] が 0 から 1 へ進むと、道が伸び、穴場のピンが順に落ちてくる
class _MapPainter extends CustomPainter {
  const _MapPainter({
    required this.progress,
    required this.ground,
    required this.block,
    required this.road,
    required this.route,
    required this.famous,
    required this.pins,
  });

  final double progress;
  final Color ground;
  final Color block;
  final Color road;
  final Color route;
  final TitleColor famous;

  /// 穴場のピンの色とアイコン。道の順に置く
  final List<(TitleColor, IconData)> pins;

  /// 穴場の位置（幅と高さに対する割合）。有名スポットから近い順
  static const List<Offset> _spots = <Offset>[
    Offset(0.30, 0.40),
    Offset(0.16, 0.66),
    Offset(0.52, 0.82),
    Offset(0.80, 0.62),
  ];

  static const Offset _famousAt = Offset(0.68, 0.28);

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);

    // 街区：決まった並びで角の丸い四角を敷き詰め、少しずつ大きさを変えて街らしくする
    final Paint blockPaint = Paint()..color = block;
    const double cell = 64;
    int i = 0;
    for (double y = -cell / 2; y < h + cell; y += cell) {
      for (double x = -cell / 2; x < w + cell; x += cell) {
        final double jw = ((i * 37) % 13) - 6;
        final double jh = ((i * 53) % 11) - 5;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + 7, y + 7, cell - 14 + jw, cell - 14 + jh),
            const Radius.circular(8),
          ),
          blockPaint,
        );
        i++;
      }
    }

    // 大通り
    final Paint roadPaint = Paint()
      ..color = road
      ..strokeCap = StrokeCap.round;
    for (final (Offset, Offset, double) line in <(Offset, Offset, double)>[
      (Offset(-20, h * 0.22), Offset(w + 20, h * 0.12), 16),
      (Offset(-20, h * 0.58), Offset(w + 20, h * 0.74), 20),
      (Offset(w * 0.62, -20), Offset(w * 0.74, h + 20), 14),
      (Offset(w * 0.08, -20), Offset(w * 0.22, h + 20), 9),
    ]) {
      canvas.drawLine(line.$1, line.$2, roadPaint..strokeWidth = line.$3);
    }

    final Offset famousAt = Offset(w * _famousAt.dx, h * _famousAt.dy);
    final List<Offset> spots = <Offset>[
      for (final Offset s in _spots) Offset(w * s.dx, h * s.dy),
    ];

    // 有名スポットのまわりの人だかり
    final Paint crowd = Paint()..color = famous.color.withValues(alpha: 0.22);
    canvas.drawCircle(famousAt, 34, crowd);
    canvas.drawCircle(
      famousAt,
      52,
      crowd..color = crowd.color.withValues(alpha: 0.1),
    );

    // 有名スポットから穴場をめぐる、路地の点線
    final double routeT = Curves.easeInOut.transform(
      (progress / 0.75).clamp(0.0, 1.0),
    );
    final Path routePath = Path()..moveTo(famousAt.dx, famousAt.dy);
    Offset from = famousAt;
    for (final Offset to in spots) {
      final Offset mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
      // 曲がりくねった路地に見えるよう、中点を少しずらす
      final Offset bend = Offset(-(to.dy - from.dy), to.dx - from.dx) * 0.18;
      routePath.quadraticBezierTo(
        mid.dx + bend.dx,
        mid.dy + bend.dy,
        to.dx,
        to.dy,
      );
      from = to;
    }
    final Paint dash = Paint()
      ..color = route
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    for (final ui.PathMetric m in routePath.computeMetrics()) {
      final double end = m.length * routeT;
      for (double d = 0; d < end; d += 14) {
        canvas.drawPath(m.extractPath(d, math.min(d + 7, end)), dash);
      }
    }

    // 有名スポットのピン：灰色で、人が多いことを示す
    _drawPin(
      canvas,
      famousAt,
      PinStyle(
        icon: Icons.groups,
        fill: famous.color,
        onFill: famous.onColor,
        ring: Colors.white,
        selected: true,
      ),
      1,
    );

    // 穴場のピン：道が届いたところから順に落ちてくる
    for (int k = 0; k < spots.length && k < pins.length; k++) {
      final double start = 0.18 + k * 0.16;
      final double t = ((progress - start) / 0.25).clamp(0.0, 1.0);
      if (t == 0) {
        continue;
      }
      final double drop = Curves.easeOutBack.transform(t);
      _drawPin(
        canvas,
        spots[k].translate(0, -(1 - drop) * 40),
        PinStyle(
          icon: pins[k].$2,
          fill: pins[k].$1.color,
          onFill: pins[k].$1.onColor,
          ring: Colors.white,
        ),
        t,
      );
    }
  }

  /// 先端が [tip] にあるピン
  static void _drawPin(
    Canvas canvas,
    Offset tip,
    PinStyle style,
    double opacity,
  ) {
    final Size size = style.size;
    canvas.save();
    canvas.translate(tip.dx - size.width / 2, tip.dy - size.height);
    if (opacity < 1) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      );
      paintPin(canvas, size, style);
      canvas.restore();
    } else {
      paintPin(canvas, size, style);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MapPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      ground != oldDelegate.ground ||
      block != oldDelegate.block ||
      road != oldDelegate.road ||
      route != oldDelegate.route ||
      famous != oldDelegate.famous;
}
