import 'package:flutter/material.dart';

import 'star_rating.dart';
import '../strings.dart';

/// ★評価の平均と数
class RatingSummary extends StatelessWidget {
  const RatingSummary({super.key, required this.stars, required this.count});

  final double stars;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      label: l10n.ratingSummaryLabel(stars.toStringAsFixed(1), count),
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          StarRating(value: stars),
          const SizedBox(width: 6),
          Text(stars.toStringAsFixed(1), style: theme.textTheme.labelLarge),
          const SizedBox(width: 6),
          Text(
            l10n.ratingCount(count),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
