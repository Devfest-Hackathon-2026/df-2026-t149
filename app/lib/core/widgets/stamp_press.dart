import 'package:flutter/material.dart';

import '../models/place.dart';
import '../models/place_genre.dart';
import '../strings.dart';
import 'stamp_celebration.dart';

/// 場所のスタンプの種類
StampDesign stampDesignOfPlace(Place place) =>
    StampDesign.of(PlaceGenre.of(place));

/// まだ押していないスタンプ。薄いスタンプの上に「押してスタンプ」と書き、押すとチェックインする。
/// チェックインのタブの「いまここ」で大きく使う。押されたスタンプの演出はチェックインの画面が出す
class StampPressButton extends StatefulWidget {
  const StampPressButton({
    super.key,
    required this.design,
    required this.onPressed,
    required this.semanticLabel,
    this.size = 200,
    this.busy = false,
  });

  final StampDesign design;
  final VoidCallback? onPressed;

  /// 読み上げの文言（「○○で押してスタンプ」）
  final String semanticLabel;
  final double size;

  /// 現在地を確かめている間など、押せないときに回る印を出す
  final bool busy;

  @override
  State<StampPressButton> createState() => _StampPressButtonState();
}

class _StampPressButtonState extends State<StampPressButton>
    with SingleTickerProviderStateMixin {
  // 押せることが伝わるよう、ゆっくり息をするように大きさを変える
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool animate =
        StampCelebration.loop &&
        !MediaQuery.disableAnimationsOf(context) &&
        widget.onPressed != null;
    if (animate && !_breath.isAnimating) {
      _breath.repeat(reverse: true);
    } else if (!animate) {
      _breath.stop();
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double size = widget.size;
    final StampDesign d = widget.design;
    final bool enabled = widget.onPressed != null && !widget.busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: ScaleTransition(
        scale: Tween<double>(
          begin: 1,
          end: 1.04,
        ).animate(CurvedAnimation(parent: _breath, curve: Curves.easeInOut)),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: d.shape(BorderSide.none, size),
            onTap: enabled ? widget.onPressed : null,
            child: SizedBox.square(
              dimension: size,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Opacity(
                    opacity: 0.22,
                    child: StampSeal(
                      size: size,
                      ink: d.ink,
                      caption: '',
                      label: '',
                      design: d,
                      glow: false,
                    ),
                  ),
                  if (widget.busy)
                    const CircularProgressIndicator()
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.touch_app, size: size * 0.2, color: d.ink),
                        SizedBox(height: size * 0.03),
                        Text(
                          l10n.pressToStamp,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 横に長い「押してスタンプ」。小さな薄いスタンプ、文言、「押す」ボタンを並べる。
/// 場所の詳細の下と、地図の結果の上で使い、チェックインのタブと同じ押し方にする
class StampPressTile extends StatelessWidget {
  const StampPressTile({
    super.key,
    required this.design,
    required this.title,
    required this.onPressed,
    this.subtitle,
    this.busy = false,
    this.filled = true,
  });

  final StampDesign design;
  final String title;
  final String? subtitle;
  final VoidCallback? onPressed;
  final bool busy;

  /// 面の色を付けるか。地図の結果の中では、ほかのカードと区別できるよう付ける
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? subtitle = this.subtitle;
    return Material(
      color: filled
          ? Color.alphaBlend(
              design.ink.withValues(alpha: 0.08),
              scheme.surfaceContainerLow,
            )
          : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onPressed,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: <Widget>[
              Opacity(
                opacity: 0.35,
                child: StampSeal(
                  size: 52,
                  ink: design.ink,
                  caption: '',
                  label: '',
                  design: design,
                  glow: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.titleSmall),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: design.ink),
                onPressed: busy ? null : onPressed,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.approval, size: 18),
                label: Text(l10n.pressStampShort),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
