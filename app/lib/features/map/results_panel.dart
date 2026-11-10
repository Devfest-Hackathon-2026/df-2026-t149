import '../../core/widgets/google_maps_notice.dart';
import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/models/memory_log.dart';
import '../../core/models/place.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/widgets/mock_banner.dart';
import '../../core/widgets/place_card.dart';
import '../../core/widgets/place_labels.dart';
import '../../core/widgets/state_view.dart';
import 'condition_pill.dart';
import 'map_search_controller.dart';
import '../../core/widgets/rating_summary.dart';
import '../../core/widgets/stamp_press.dart';
import '../../core/strings.dart';

/// 探した結果の一覧。モバイルでは下から引き上げるシート、デスクトップでは左の列に置く
class ResultsPanel extends StatelessWidget {
  const ResultsPanel({
    super.key,
    required this.controller,
    required this.onOpenPlace,
    this.scrollController,
    this.showHandle = false,
    this.leadingFilters = const <Widget>[],
    this.idle,
    this.onCheckInHere,
  });

  /// 現在地のそばの場所で「押してスタンプ」を押したとき。null なら出さない
  final ValueChanged<Place>? onCheckInHere;

  static const Key staleKey = ValueKey<String>('results-stale');

  final MapSearchController controller;
  final ValueChanged<Place> onOpenPlace;
  final ScrollController? scrollController;
  final bool showHandle;

  /// 絞り込みの列の先頭に置くもの（探す地域の選択など）
  final List<Widget> leadingFilters;

  /// まだ探していないときに出す案内
  final Widget? idle;

  @override
  Widget build(BuildContext context) {
    final SearchState state = controller.state;
    final List<Place> places = controller.visiblePlaces;
    final Place? selected = controller.selected;
    final int? nextRadius = controller.nextRadius;

    final List<Widget> body = switch (state) {
      SearchIdle() => <Widget>[?idle],
      SearchLoading() => <Widget>[
        LoadingLabel(l10n.searchingNearby),
        const SizedBox(height: 12),
        const PlaceList(
          rows: <Widget>[
            PlaceRowPlaceholder(),
            PlaceRowPlaceholder(),
            PlaceRowPlaceholder(),
          ],
        ),
      ],
      SearchFailed(:final String message) => <Widget>[
        StateView(
          icon: Icons.cloud_off_outlined,
          title: message,
          primary: StateViewAction(
            l10n.retry,
            controller.search,
            icon: Icons.refresh,
          ),
        ),
      ],
      SearchLoaded(places: final List<Place> all) when all.isEmpty => <Widget>[
        StateView(
          icon: Icons.travel_explore,
          title: l10n.notFound,
          primary: nextRadius == null
              ? null
              : StateViewAction(
                  l10n.widenRange,
                  () => controller.widenAndSearch(nextRadius),
                  icon: Icons.zoom_out_map,
                ),
        ),
      ],
      SearchLoaded() when places.isEmpty => <Widget>[
        StateView(
          icon: Icons.filter_alt_off_outlined,
          title: l10n.noPlacesForPopularity,
          primary: StateViewAction(
            l10n.showFamousPlaces,
            controller.showAllPopularity,
            icon: Icons.filter_alt_off,
          ),
        ),
      ],
      SearchLoaded() => <Widget>[
        if (selected != null) ...<Widget>[
          PlaceCard(
            place: selected,
            distanceMeters: controller.distanceTo(selected),
            onTap: () => onOpenPlace(selected),
            footer: _footer(selected),
          ),
          const SizedBox(height: 8),
        ],
        PlaceList(
          rows: <Widget>[
            for (int i = 0; i < places.length; i++)
              PlaceRow(
                place: places[i],
                rank: i + 1,
                distanceMeters: controller.distanceTo(places[i]),
                onTap: () => onOpenPlace(places[i]),
                footer: _footer(places[i]),
              ),
          ],
        ),
      ],
    };

    final bool stale = controller.isStale;
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(
        16,
        showHandle ? 8 : 0,
        16,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      children: <Widget>[
        if (showHandle)
          Center(
            // Material 3 のシートのつまみ（32×4、onSurfaceVariant の 40%）
            child: Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        if (state case SearchLoaded(isMock: true)) ...<Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            child: const MockBanner(),
          ),
          const SizedBox(height: 8),
        ],
        // 件数の下に絞り込みのチップを1列に並べる
        if (state is! SearchIdle) ...<Widget>[
          if (state case SearchLoaded(
            places: final List<Place> all,
          ) when all.isNotEmpty)
            _ResultHeader(controller: controller, count: places.length),
          const SizedBox(height: 8),
          _FilterRow(controller: controller, leading: leadingFilters),
          const SizedBox(height: 12),
        ],
        // 地図を動かしたり条件を変えたりしたときは、結果を薄くせず、前の結果だと文で伝える（薄い文字は読みにくいため）
        if (stale) ...<Widget>[
          _StaleBanner(key: staleKey, controller: controller),
          const SizedBox(height: 8),
        ],
        if (state is SearchLoaded && onCheckInHere != null)
          if (controller.placeHere case final Place here) ...<Widget>[
            StampPressTile(
              key: const ValueKey<String>('map-here-stamp'),
              design: stampDesignOfPlace(here),
              title: l10n.mapHereTitle(here.name),
              subtitle: l10n.mapHereSubtitle,
              onPressed: () => onCheckInHere!(here),
            ),
            const SizedBox(height: 12),
          ],
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
        if (state case SearchLoaded(
          isMock: false,
          places: final List<Place> all,
        ) when all.isNotEmpty)
          const GoogleMapsAttribution(),
      ],
    );
  }

  static Widget? _footer(Place place) => switch (place) {
    Place(stars: final double stars) => RatingSummary(
      stars: stars,
      count: place.starCount,
    ),
    // ★評価の前の当たり・ハズレだけの集計は、当たりを★4、ハズレを★2として★で見せる。
    // ハズレの数を出すと、場所の悪い評判を広めているように見えるため
    _ when place.hits + place.misses > 0 => RatingSummary(
      stars:
          (place.hits * Verdict.defaultStars(Verdict.hit) +
              place.misses * Verdict.defaultStars(Verdict.miss)) /
          (place.hits + place.misses),
      count: place.hits + place.misses,
    ),
    _ => null,
  };
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.controller, required this.count});

  final MapSearchController controller;
  final int count;

  // どこから探したかと半径は、下の絞り込みのチップで見せる
  @override
  Widget build(BuildContext context) => Text(
    l10n.resultCount(count),
    style: Theme.of(context).textTheme.titleMedium,
  );
}

/// 並べ替えの選択。今の並べ方を文字で見せ、押すと説明付きの一覧を出す
class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.controller});

  final MapSearchController controller;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: <Widget>[
      for (final ResultSort sort in ResultSort.values)
        MenuItemButton(
          leadingIcon: Icon(
            sort == controller.sort
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
          ),
          onPressed: () {
            Haptics.select();
            controller.setSort(sort);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(sort.label),
              Text(
                sort.description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
    ],
    builder: (BuildContext context, MenuController menu, Widget? _) =>
        ConditionPill(
          label: controller.sort.label,
          icon: Icons.sort,
          selected: false,
          trailing: const Icon(Icons.expand_more),
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
        ),
  );
}

/// 表示中の結果が、今の地図の場所や条件の結果ではないことを伝える
class _StaleBanner extends StatelessWidget {
  const _StaleBanner({super.key, required this.controller});

  final MapSearchController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.info_outline,
              size: 20,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                controller.action == SearchAction.applyConditions
                    ? l10n.staleConditions
                    : l10n.staleMoved,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Haptics.tap();
                controller.search();
              },
              child: Text(l10n.searchAgain),
            ),
          ],
        ),
      ),
    );
  }
}

/// 絞り込みのチップの列。地域・半径・人気度・並び順・お気に入りを1列にまとめ、横に動かして見る。
/// 半径は探し直すまで反映せず、人気度とお気に入りの絞り込みはすぐに反映する
class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.controller, required this.leading});

  final MapSearchController controller;
  final List<Widget> leading;

  void _openPopularity(BuildContext context) {
    Haptics.tap();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? _) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            // 中身の高さに合わせる（シートの既定の高さは画面の半分あり、下が空く）
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l10n.popularityHelp,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                PopularitySlider(controller: controller),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (int, int) p = controller.popularity;
    final bool allPopularity = p == (0, PlaceTitle.values.length - 1);
    final Widget radius = MenuAnchor(
      menuChildren: <Widget>[
        for (final int r in MapSearchController.radiusSteps)
          MenuItemButton(
            leadingIcon: Icon(
              r == controller.radius
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            onPressed: () => controller.setRadius(r),
            child: Text(
              r > MapSearchController.wideRadius
                  ? l10n.radiusWide(formatDistance(r))
                  : formatDistance(r),
            ),
          ),
      ],
      builder: (BuildContext context, MenuController menu, Widget? _) =>
          ConditionPill(
            label: l10n.radiusLabel(formatDistance(controller.radius)),
            icon: Icons.radar,
            selected: false,
            pending: controller.isRadiusPending,
            trailing: const Icon(Icons.expand_more),
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
          ),
    );
    final favorites = Services.maybeOf(context)?.favorites;
    final List<Widget> chips = <Widget>[
      ...leading,
      radius,
      ConditionPill(
        label: allPopularity
            ? l10n.popularity
            : l10n.popularityLabel(PopularitySlider.rangeLabel(p)),
        icon: Icons.local_fire_department_outlined,
        selected: false,
        pending: controller.isPopularityPending,
        trailing: const Icon(Icons.expand_more),
        onTap: () => _openPopularity(context),
      ),
      _SortMenu(controller: controller),
      if (favorites != null)
        ConditionPill(
          label: l10n.favorites,
          icon: controller.favoritesOnly
              ? Icons.favorite
              : Icons.favorite_border,
          selected: controller.favoritesOnly,
          onTap: () {
            Haptics.select();
            controller.setFavoritesOnly(
              !controller.favoritesOnly,
              isFavorite: favorites.isFavorite,
            );
          },
        ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // シートの左右の余白を越えて端まで動かせるようにする
      clipBehavior: Clip.none,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < chips.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 8),
            chips[i],
          ],
        ],
      ),
    );
  }
}

/// 人気度の幅を選ぶ。左が知られていない場所（未踏）、右が有名な場所（超有名）
class PopularitySlider extends StatelessWidget {
  const PopularitySlider({super.key, required this.controller});

  final MapSearchController controller;

  static String rangeLabel((int, int) p) {
    final String lo = PlaceTitle.values[p.$1].label;
    final String hi = PlaceTitle.values[p.$2].label;
    return p.$1 == p.$2 ? lo : l10n.popularityRange(lo, hi);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TitleColors colors = TitleColors.of(context);
    final (int, int) p = controller.popularity;
    final int last = PlaceTitle.values.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.local_fire_department_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(l10n.popularity, style: theme.textTheme.labelLarge),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                rangeLabel(p),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            if (controller.isPopularityPending)
              Text(
                l10n.appliedOnSearch,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
          ],
        ),
        RangeSlider(
          values: RangeValues(p.$1.toDouble(), p.$2.toDouble()),
          max: last.toDouble(),
          divisions: last,
          labels: RangeLabels(
            PlaceTitle.values[p.$1].label,
            PlaceTitle.values[p.$2].label,
          ),
          semanticFormatterCallback: (double v) =>
              PlaceTitle.values[v.round()].label,
          onChanged: (RangeValues v) {
            final (int, int) next = (v.start.round(), v.end.round());
            if (next != p) {
              Haptics.select();
              controller.setPopularity(next.$1, next.$2);
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (final PlaceTitle t in PlaceTitle.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: colors.forTitle(t).color,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      t.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: t.index >= p.$1 && t.index <= p.$2
                            ? FontWeight.bold
                            : null,
                        color: t.index >= p.$1 && t.index <= p.$2
                            ? null
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
