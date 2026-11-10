import 'package:flutter/material.dart';

import '../models/place.dart';
import '../theme.dart';

/// 称号（未踏・穴場・定番・超有名）を称号の色で表示する小さなバッジ
class TitleBadge extends StatelessWidget {
  const TitleBadge({super.key, required this.title});

  TitleBadge.of(Place place, {Key? key})
    : this(key: key, title: PlaceTitle.of(place.title));

  /// null のときは称号が分からない場所として、超有名と同じ色で「?」を表示する
  final PlaceTitle? title;

  @override
  Widget build(BuildContext context) {
    final TitleColor color = TitleColors.of(context).forTitle(title);
    final TextStyle? style = Theme.of(context).textTheme.labelSmall;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: color.container,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          title?.label ?? '?',
          style: style?.copyWith(color: color.color),
        ),
      ),
    );
  }
}
