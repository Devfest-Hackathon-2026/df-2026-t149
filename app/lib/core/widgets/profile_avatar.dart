import 'package:flutter/material.dart';

import '../models/place.dart';
import '../models/profile.dart';
import '../theme.dart';

/// プロフィールのアイコンを、アイコンごとに決まった色の丸で表示する
///
/// 色はテーマの色と称号の色から選ぶ。キーカラーやダークのテーマに切り替えても、地と絵のコントラストを保つため
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.icon, this.size = 40});

  final ProfileIcon icon;
  final double size;

  /// アイコンの地と絵の色の組
  static (Color, Color) colorsOf(BuildContext context, ProfileIcon icon) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TitleColors titles = TitleColors.of(context);
    final TitleColor hidden = titles.forTitle(PlaceTitle.hidden);
    final TitleColor known = titles.forTitle(PlaceTitle.known);
    final List<(Color, Color)> palette = <(Color, Color)>[
      (scheme.primaryContainer, scheme.onPrimaryContainer),
      (hidden.container, hidden.color),
      (known.container, known.color),
      (scheme.secondaryContainer, scheme.onSecondaryContainer),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      (scheme.surfaceContainerHighest, scheme.onSurface),
    ];
    return palette[icon.index % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground) = colorsOf(context, icon);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(icon.icon, size: size * 0.56, color: foreground),
    );
  }
}
