import 'package:flutter/material.dart';

import '../haptics.dart';
import '../sounds.dart';
import '../models/memory_log.dart';
import '../theme.dart';
import '../strings.dart';

/// ★の数を表示する。[value] は 0〜5 で、小数は半分の★で表す
class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.value, this.size = 16});

  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color empty = Theme.of(context).colorScheme.outlineVariant;
    return Semantics(
      label: l10n.starRatingLabel(
        value.toStringAsFixed(value % 1 == 0 ? 0 : 1),
      ),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 1; i <= 5; i++)
              Icon(
                value >= i
                    ? Icons.star_rounded
                    : value >= i - 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
                size: size,
                color: value >= i - 0.5 ? AppTheme.starColor : empty,
              ),
          ],
        ),
      ),
    );
  }
}

/// ★を選ぶ。タップした★までを点け、選んだ★の言葉（最高！ など）を下に出す
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 44,
  });

  /// 選んだ★の数。まだ選んでいなければ null
  final int? value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? value = this.value;
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (int i = 1; i <= 5; i++)
              Semantics(
                button: true,
                selected: value == i,
                label: l10n.starInputLabel(i, starsLabel(i)),
                child: ExcludeSemantics(
                  child: IconButton(
                    iconSize: size,
                    padding: const EdgeInsets.all(2),
                    onPressed: () {
                      Haptics.star(i);
                      Sounds.star();
                      onChanged(i);
                    },
                    icon: AnimatedScale(
                      scale: value != null && i <= value ? 1.1 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        value != null && i <= value
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: value != null && i <= value
                            ? AppTheme.starColor
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value == null ? l10n.starInputPrompt : starsLabel(value),
          style: theme.textTheme.titleMedium?.copyWith(
            color: value == null ? theme.colorScheme.onSurfaceVariant : null,
          ),
        ),
      ],
    );
  }
}
