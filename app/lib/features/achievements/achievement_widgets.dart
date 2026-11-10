import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/achievement_stats.dart';

import '../../core/haptics.dart';
import '../../core/sounds.dart';
import '../../core/theme.dart';
import 'achievements.dart';
import '../../core/strings.dart';

/// めずらしさの色
Color rarityColor(AchievementRarity r) => AppTheme.rarityColors[r.index];

/// 実績の色（明るい色と暗い色の組）。段階のある実績は段階の金属の色、ない実績はめずらしさの色。
/// テーマ（キーカラー）と混ざらない決まった色にする
(Color, Color) achievementColors(AchievementProgress a) {
  final AchievementTier? tier = a.tierLevel;
  if (tier != null) {
    return AppTheme.tierColors[tier.index];
  }
  final Color c = rarityColor(a.definition.rarity);
  return (Color.lerp(c, Colors.white, 0.25)!, c);
}

/// 解除・昇格の見出し（「シルバーに昇格！」など）
String unlockHeadline(AchievementProgress a) {
  final AchievementTier? tier = a.tierLevel;
  if (tier == null) {
    return l10n.achievementUnlockedShort;
  }
  return a.promoted
      ? l10n.achievementPromoted(tier.label)
      : l10n.achievementTierEarned(tier.label);
}

/// 実績の代表の色（帯や文字に使う）
Color achievementColor(AchievementProgress a) => achievementColors(a).$2;

/// 実績のメダル。解除していなければ鍵、シークレットなら「？」を見せる。
/// 段階のある実績は、下に段階の点（●●○）を出す
/// 実績のバッジ。花の形に切り抜いた七宝（エナメル）のピンバッジにする。
/// 金属のふちに色のガラス質の面、左上につやの光を描く。まだ解除していない実績は、色の付いていない灰色のピンにする
class AchievementBadge extends StatelessWidget {
  const AchievementBadge({
    super.key,
    required this.achievement,
    this.radius = 24,
  });

  final AchievementProgress achievement;

  /// ピンの大きさの半分
  final double radius;

  /// ピンの形（8枚の花びらの花形）。[side] はふちの線
  static OutlinedBorder shape([BorderSide side = BorderSide.none]) =>
      StarBorder(
        side: side,
        points: 8,
        innerRadiusRatio: 0.82,
        pointRounding: 0.6,
      );

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool darkMode = Theme.of(context).brightness == Brightness.dark;
    final AchievementDefinition d = achievement.definition;
    final bool on = achievement.unlocked;
    final (Color light, Color dark) = achievementColors(achievement);
    final double size = radius * 2;
    final Widget medal = Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        shape: shape(
          BorderSide(
            // 金属のふち。解除した実績は面の色を明るくした金属の色にする
            color: on
                ? Color.lerp(light, Colors.white, 0.55)!
                : scheme.outlineVariant,
            width: radius / 7,
          ),
        ),
        gradient: on
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color.lerp(light, Colors.white, 0.15)!, dark],
              )
            : null,
        color: on ? null : scheme.surfaceContainerHighest,
        shadows: on
            ? <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: darkMode ? 0.45 : 0.2),
                  blurRadius: radius / 6,
                  offset: Offset(0, radius / 14),
                ),
              ]
            : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Icon(
            on
                ? d.icon
                : achievement.hidden
                ? Icons.question_mark
                : Icons.lock_outline,
            size: radius * 0.95,
            color: on ? Colors.white : scheme.onSurfaceVariant,
          ),
          // 七宝のつや
          if (on)
            Positioned(
              top: size * 0.17,
              left: size * 0.22,
              child: Transform.rotate(
                angle: -0.5,
                child: Container(
                  width: size * 0.2,
                  height: size * 0.08,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(size),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (!d.tiered) {
      return medal;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        medal,
        SizedBox(height: radius / 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < d.goals.length; i++)
              Container(
                width: radius / 3.2,
                height: radius / 3.2,
                margin: EdgeInsets.symmetric(horizontal: radius / 20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < achievement.tier
                      ? AppTheme.tierColors[i].$2
                      : scheme.outlineVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

String _date(DateTime at) => '${at.year}/${at.month}/${at.day}';

/// 実績の詳細を下から出す
Future<void> showAchievementDetail(
  BuildContext context,
  AchievementProgress achievement, {
  AchievementStats? stats,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (BuildContext context) =>
      AchievementDetailSheet(achievement: achievement, stats: stats),
);

/// 利用者全体で解除した人の割合の文。[tier] は段階（段階のない実績は 1）。集計がなければ null
String? unlockRateLabel(
  AchievementStats? stats,
  AchievementProgress achievement, {
  int? tier,
}) {
  final AchievementDefinition d = achievement.definition;
  final int t = tier ?? (achievement.tier < 1 ? 1 : achievement.tier);
  final double? r = stats?.rate(d.id, t);
  if (r == null) {
    return null;
  }
  final String p = AchievementStats.percent(r);
  return d.tiered
      ? l10n.achievementTierShare(AchievementTier.values[t - 1].label, p)
      : l10n.achievementShare(p);
}

class AchievementDetailSheet extends StatelessWidget {
  const AchievementDetailSheet({
    super.key,
    required this.achievement,
    this.stats,
  });

  final AchievementProgress achievement;

  /// 利用者全体の集計。読めていなければ null
  final AchievementStats? stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AchievementDefinition d = achievement.definition;
    final bool hidden = achievement.hidden;
    final DateTime? at = achievement.unlockedAt;
    final String? place = achievement.unlockedBy?.placeName;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AchievementBadge(achievement: achievement, radius: 40),
            const SizedBox(height: 16),
            Text(
              hidden ? l10n.hiddenTitle : d.title,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: <Widget>[
                if (achievement.tierLevel case final AchievementTier t)
                  _Tag(label: t.label, color: achievementColor(achievement))
                else
                  _Tag(label: d.rarity.label, color: rarityColor(d.rarity)),
                if (d.secret) _Tag(label: l10n.secret, color: scheme.tertiary),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              hidden
                  ? l10n.achievementHint(d.hint)
                  : achievement.currentDescription,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (!hidden && d.detail.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                d.detail,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (d.tiered && !hidden) ...<Widget>[
              const SizedBox(height: 16),
              _TierSteps(achievement: achievement, stats: stats),
            ] else if (unlockRateLabel(stats, achievement)
                case final String rate) ...<Widget>[
              const SizedBox(height: 12),
              UnlockRate(label: rate),
            ],
            const SizedBox(height: 20),
            if (at != null)
              Text(
                place == null || place.isEmpty
                    ? l10n.achievementUnlockedOn(_date(at))
                    : l10n.achievementUnlockedAt(_date(at), place),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
            if (!hidden && achievement.nextGoal != null) ...<Widget>[
              const SizedBox(height: 12),
              NextGoalBar(achievement: achievement),
            ],
          ],
        ),
      ),
    );
  }
}

/// 段階ごとの条件と、達したか
class _TierSteps extends StatelessWidget {
  const _TierSteps({required this.achievement, this.stats});

  final AchievementProgress achievement;
  final AchievementStats? stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AchievementDefinition d = achievement.definition;
    return Column(
      children: <Widget>[
        for (int i = 0; i < d.goals.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: <Widget>[
                Icon(
                  i < achievement.tier
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 20,
                  color: i < achievement.tier
                      ? AppTheme.tierColors[i].$2
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: Text(
                    AchievementTier.values[i].label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppTheme.tierColors[i].$2,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    d.describe(d.goals[i]),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (stats?.rate(d.id, i + 1) case final double r)
                  Text(
                    l10n.achievementSharePercent(AchievementStats.percent(r)),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 利用者全体で解除した人の割合
class UnlockRate extends StatelessWidget {
  const UnlockRate({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.groups_outlined, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// 次の段階（段階のない実績は解除）までの進み具合
class NextGoalBar extends StatelessWidget {
  const NextGoalBar({super.key, required this.achievement});

  final AchievementProgress achievement;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? next = achievement.nextGoal;
    if (next == null) {
      return const SizedBox.shrink();
    }
    final AchievementDefinition d = achievement.definition;
    final int tier = achievement.tier;
    final Color color = d.tiered
        ? AppTheme.tierColors[tier.clamp(0, AppTheme.tierColors.length - 1)].$2
        : rarityColor(d.rarity);
    final String label = d.tiered
        ? l10n.achievementNextTier(
            AchievementTier.values[tier].label,
            next - achievement.progress,
          )
        : l10n.achievementRemaining(next - achievement.progress);
    return Row(
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (achievement.progress / next).clamp(0.0, 1.0),
              minHeight: 8,
              color: color,
              backgroundColor: color.withValues(alpha: 0.18),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: theme.textTheme.labelLarge),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: 0.6)),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
    ),
  );
}

/// 解除した実績を、紙吹雪と一緒に見せる。何も解除していなければ何もしない
Future<void> showUnlockedAchievements(
  BuildContext context,
  List<AchievementProgress> unlocked,
) async {
  if (unlocked.isEmpty) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) =>
        AchievementUnlockedDialog(unlocked: unlocked),
  );
}

class AchievementUnlockedDialog extends StatefulWidget {
  const AchievementUnlockedDialog({super.key, required this.unlocked});

  final List<AchievementProgress> unlocked;

  @override
  State<AchievementUnlockedDialog> createState() =>
      _AchievementUnlockedDialogState();
}

class _AchievementUnlockedDialogState extends State<AchievementUnlockedDialog> {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<AchievementProgress> list = widget.unlocked;
    return AlertDialog(
      title: Text(
        list.any((AchievementProgress a) => a.definition.secret)
            ? l10n.secretAchievementUnlocked
            : l10n.achievementUnlocked,
        textAlign: TextAlign.center,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < list.length; i++) ...<Widget>[
              MedalReveal(
                achievement: list[i],
                delay: const Duration(milliseconds: 700) * i,
              ),
              const SizedBox(height: 8),
              Text(list[i].definition.title, style: theme.textTheme.titleLarge),
              Text(
                unlockHeadline(list[i]),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: achievementColor(list[i]),
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                list[i].currentDescription,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.achievementCongrats),
        ),
      ],
    );
  }
}

/// 実績を解除したときのメダルの演出。メダルが回って現れ、光が横切り、星が飛び散る。
///
/// [delay] だけ待ってから始める（複数の実績を順に見せるため）。メダルが正面を向いた瞬間に [Haptics.unlock] で振動させる
class MedalReveal extends StatefulWidget {
  const MedalReveal({
    super.key,
    required this.achievement,
    this.delay = Duration.zero,
    this.radius = 32,
    this.haptics = true,
  });

  final AchievementProgress achievement;
  final Duration delay;
  final double radius;
  final bool haptics;

  @override
  State<MedalReveal> createState() => _MedalRevealState();
}

class _MedalRevealState extends State<MedalReveal>
    with SingleTickerProviderStateMixin {
  static const Duration _length = Duration(milliseconds: 1500);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.delay + _length,
  )..addListener(_onTick);

  /// 待つ時間の割合。待つ間はタイマーを使わず、アニメーションの前半で止めておく
  late final double _start =
      widget.delay.inMicroseconds / (widget.delay + _length).inMicroseconds;
  bool _buzzed = false;

  double get _t => ((_c.value - _start) / (1 - _start)).clamp(0.0, 1.0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status == AnimationStatus.dismissed) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  void _onTick() {
    if (!_buzzed && _t >= 0.45) {
      _buzzed = true;
      if (widget.haptics) {
        Haptics.unlock();
        Sounds.unlock();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double box = widget.radius * 3.4;
    final Color ring = rarityColor(widget.achievement.definition.rarity);
    return SizedBox.square(
      dimension: box,
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? _) {
          final double t = _t;
          final double flip = Curves.easeOutBack.transform(
            (t / 0.45).clamp(0.0, 1.0),
          );
          final double after = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  painter: _SparklePainter(progress: after, color: ring),
                ),
              ),
              Opacity(
                opacity: (t / 0.15).clamp(0.0, 1.0),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateY((1 - flip) * math.pi * 1.5)
                    ..scaleByDouble(0.4 + 0.6 * flip, 0.4 + 0.6 * flip, 1, 1),
                  child: Stack(
                    children: <Widget>[
                      AchievementBadge(
                        achievement: widget.achievement,
                        radius: widget.radius,
                      ),
                      // 光がピンを横切る。ピンの形に切り抜き、下の段階の点にはかけない
                      if (after > 0 && after < 1)
                        Positioned(
                          left: 0,
                          top: 0,
                          width: widget.radius * 2,
                          height: widget.radius * 2,
                          child: ClipPath(
                            clipper: ShapeBorderClipper(
                              shape: AchievementBadge.shape(),
                            ),
                            child: FractionalTranslation(
                              translation: Offset(-1.2 + 2.4 * after, 0),
                              child: Transform.rotate(
                                angle: 0.5,
                                child: const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: <Color>[
                                        Color(0x00FFFFFF),
                                        Color(0x99FFFFFF),
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
            ],
          );
        },
      ),
    );
  }
}

/// メダルのまわりに飛び散る星
class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static Path _star(Offset c, double r) {
    final Path p = Path();
    for (int i = 0; i < 8; i++) {
      final double a = i * math.pi / 4 - math.pi / 2;
      final double len = i.isEven ? r : r * 0.35;
      final Offset o = c + Offset(math.cos(a) * len, math.sin(a) * len);
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) {
      return;
    }
    final Offset c = size.center(Offset.zero);
    final double r = size.shortestSide / 2;
    final double fly = Curves.easeOutCubic.transform(progress);
    final Paint paint = Paint()
      ..color = Color.lerp(
        color,
        AppTheme.starColor,
        0.5,
      )!.withValues(alpha: 1 - progress);
    const int n = 10;
    for (int i = 0; i < n; i++) {
      final double a = i * 2 * math.pi / n + 0.3;
      final double d = r * (0.45 + 0.5 * fly) * (i.isEven ? 1 : 0.8);
      canvas.drawPath(
        _star(
          c + Offset(math.cos(a) * d, math.sin(a) * d),
          (i.isEven ? 7 : 5) * (1 - progress * 0.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.progress != progress;
}
