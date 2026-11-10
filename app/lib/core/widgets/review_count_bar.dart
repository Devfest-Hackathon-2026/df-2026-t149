import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/place.dart';
import '../theme.dart';
import 'place_labels.dart';
import '../strings.dart';

/// レビュー数を対数の目盛りで表す横棒。
///
/// 棒の地の全幅が基準（有名スポット）のレビュー数を表し、比べる場所の棒を称号の色で重ねる。
class ReviewCountBar extends StatelessWidget {
  const ReviewCountBar({
    super.key,
    required this.count,
    required this.baseline,
    required this.title,
    this.thickness = 6,
  });

  static const Key barKey = ValueKey<String>('review-count-bar');
  static const Key trackKey = ValueKey<String>('review-count-track');

  /// 比べる場所のレビュー数
  final int count;

  /// 基準にする有名スポットのレビュー数
  final int baseline;

  /// 比べる場所の称号。棒の色に使う
  final PlaceTitle? title;

  final double thickness;

  /// 棒の長さの割合（0〜1）。件数の桁が大きく違っても比べられるよう、対数で求める
  static double ratio(int count, int baseline) {
    if (baseline <= 0) {
      return count > 0 ? 1 : 0;
    }
    final double value = math.log(1 + count) / math.log(1 + baseline);
    return value.clamp(0, 1).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color fill = TitleColors.of(context).forTitle(title).color;
    final Radius radius = Radius.circular(thickness / 2);
    final double fraction = ratio(count, baseline);

    return Semantics(
      label: l10n.reviewCountBarLabel(
        formatCount(count),
        formatCount(baseline),
      ),
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          // 0件でも場所があることが分かるよう、太さと同じ幅の丸を最小にする
          final double width = math.max(thickness, box.maxWidth * fraction);
          return DecoratedBox(
            key: trackKey,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.all(radius),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              heightFactor: 1,
              child: SizedBox(
                width: width,
                height: thickness,
                child: DecoratedBox(
                  key: barKey,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.all(radius),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
