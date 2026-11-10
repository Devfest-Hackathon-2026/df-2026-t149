import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import '../../core/strings.dart';

/// 検索の条件のボタン。
///
/// 選択中はキーカラーで塗る。[pending] は変更したがまだ探していないことを表し、点線の枠で示す
class ConditionPill extends StatelessWidget {
  const ConditionPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailing,
    this.pending = false,
    this.elevated = false,
  });

  final String label;
  final bool selected;
  final bool pending;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? trailing;

  /// 地図の上に重ねるときに影を付ける
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool filled = selected && !pending;
    final Color foreground = filled
        ? scheme.onPrimary
        : (pending ? scheme.primary : scheme.onSurface);
    final Widget? trailing = this.trailing;
    final IconData? icon = this.icon;

    final Widget content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: filled || pending ? FontWeight.w700 : null,
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: 2),
              IconTheme.merge(
                data: IconThemeData(size: 18, color: foreground),
                child: trailing,
              ),
            ],
          ],
        ),
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: pending ? l10n.conditionPending(label) : label,
      excludeSemantics: true,
      child: Material(
        color: filled ? scheme.primary : scheme.surfaceContainerLowest,
        elevation: elevated && !pending ? 2 : 0,
        shape: StadiumBorder(
          side: pending
              ? BorderSide.none
              : BorderSide(
                  color: filled ? scheme.primary : scheme.outlineVariant,
                ),
        ),
        child: CustomPaint(
          foregroundPainter: pending
              ? _DashedStadiumPainter(color: scheme.primary)
              : null,
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _DashedStadiumPainter extends CustomPainter {
  const _DashedStadiumPainter({required this.color});

  final Color color;

  static const double _dash = 5;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final Path outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          Radius.circular(size.height / 2),
        ),
      );
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final PathMetric metric in outline.computeMetrics()) {
      for (double d = 0; d < metric.length; d += _dash + _gap) {
        canvas.drawPath(metric.extractPath(d, d + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedStadiumPainter oldDelegate) =>
      oldDelegate.color != color;
}
