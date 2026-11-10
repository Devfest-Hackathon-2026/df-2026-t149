import 'package:flutter/material.dart';

import '../models/place.dart';
import '../services.dart';
import 'favorite_button.dart';
import '../theme.dart';
import 'place_labels.dart';
import 'title_badge.dart';
import '../strings.dart';

/// 種類、レビュー数、距離を、それぞれアイコンを先頭に付けて並べる
class PlaceFacts extends StatelessWidget {
  const PlaceFacts({
    super.key,
    required this.place,
    this.distanceMeters,
    this.showReviews = true,
  });

  final Place place;

  /// false のとき、レビュー数を表示しない（ほかの場所でレビュー数を大きく見せるとき）
  final bool showReviews;

  /// 表示する距離。null なら [Place.distanceMeters] を使い、それもなければ距離を表示しない
  final int? distanceMeters;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final String? type = placeTypeLabel(place.primaryType);
    final int? distance = distanceMeters ?? place.distanceMeters;

    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: <Widget>[
        if (type != null)
          _Fact(
            icon: placeTypeIcon(place.primaryType),
            text: type,
            style: style,
          ),
        if (showReviews && place.reviewCountKnown)
          _Fact(
            icon: Icons.rate_review_outlined,
            text: formatCount(place.userRatingCount),
            semanticsLabel: l10n.reviewCountLabel(
              formatCount(place.userRatingCount),
            ),
            style: style,
          ),
        if (distance != null)
          _Fact(
            icon: Icons.directions_walk,
            text: formatDistance(distance),
            style: style,
          ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.text,
    this.semanticsLabel,
    this.style,
  });

  final IconData icon;
  final String text;

  /// 画面では数字だけを見せる項目を、読み上げで何の数かが分かるように伝える文
  final String? semanticsLabel;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final String? semanticsLabel = this.semanticsLabel;
    final Widget fact = Semantics(
      label: semanticsLabel ?? text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: style?.color),
          const SizedBox(width: 4),
          Text(text, style: style),
        ],
      ),
    );
    if (semanticsLabel == null) {
      return fact;
    }
    // 行のタップは場所の詳細を開くので、数字だけの項目の説明は長押しで少しのあいだ出す
    return Tooltip(
      message: semanticsLabel,
      triggerMode: TooltipTriggerMode.longPress,
      showDuration: const Duration(seconds: 2),
      excludeFromSemantics: true,
      child: fact,
    );
  }
}

/// 場所の1行分。順位、場所の名前と称号、種類・レビュー数・距離を表示する
class PlaceRow extends StatelessWidget {
  const PlaceRow({
    super.key,
    required this.place,
    required this.onTap,
    this.rank,
    this.distanceMeters,
    this.footer,
  });

  final Place place;

  /// 押したときの処理。通常は場所の詳細を開く
  final VoidCallback onTap;

  /// 1から始まる順位。null なら順位を表示しない
  final int? rank;

  /// 表示する距離。null なら [Place.distanceMeters] を使う
  final int? distanceMeters;

  /// 下に追加で表示する部品（レビュー数の比較の棒など）
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int? rank = this.rank;
    final Widget? footer = this.footer;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (rank != null)
              SizedBox(
                width: 36,
                child: Text(
                  '$rank',
                  // 順位は並びの位置を示すだけなので、名前より目立たせず、1位だけをキーカラーにする
                  style: AppTheme.number(
                    20,
                    color: rank == 1 ? scheme.primary : scheme.outline,
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          place.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.placeName(18),
                        ),
                      ),
                      if (place.reviewCountKnown) ...<Widget>[
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: TitleBadge.of(place),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  PlaceFacts(place: place, distanceMeters: distanceMeters),
                  if (footer != null) ...<Widget>[
                    const SizedBox(height: 10),
                    footer,
                  ],
                ],
              ),
            ),
            // 行を押すと詳細を開くので、右端はお気に入りのボタンにする。お気に入りを使えないときは矢印を出す
            if (Services.maybeOf(context)?.favorites != null)
              FavoriteButton(place: place, compact: true)
            else
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.chevron_right, color: scheme.outline),
              ),
          ],
        ),
      ),
    );
  }
}

/// 場所の行を、区切り線で分けて1つの面に並べる
class PlaceList extends StatelessWidget {
  const PlaceList({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: <Widget>[
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
          rows[i],
        ],
      ],
    ),
  );
}

/// 場所を1件だけ表示するカード。地図の下の選んだ場所などに使う
class PlaceCard extends StatelessWidget {
  const PlaceCard({
    super.key,
    required this.place,
    required this.onTap,
    this.rank,
    this.distanceMeters,
    this.footer,
  });

  final Place place;
  final VoidCallback onTap;
  final int? rank;
  final int? distanceMeters;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Card(
    child: PlaceRow(
      place: place,
      onTap: onTap,
      rank: rank,
      distanceMeters: distanceMeters,
      footer: footer,
    ),
  );
}

/// 読み込み中に、結果の行と同じ形で出す仮の表示
class PlaceRowPlaceholder extends StatelessWidget {
  const PlaceRowPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final Color fill = Theme.of(context).colorScheme.surfaceContainer;
    Widget block(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );

    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            block(180, 18),
            const SizedBox(height: 10),
            block(220, 14),
          ],
        ),
      ),
    );
  }
}

/// 読み込み中に、結果のカードと同じ形で出す仮の表示
class PlaceCardPlaceholder extends StatelessWidget {
  const PlaceCardPlaceholder({super.key});

  @override
  Widget build(BuildContext context) =>
      const Card(child: PlaceRowPlaceholder());
}
