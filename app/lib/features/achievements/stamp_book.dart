import '../../core/widgets/google_maps_notice.dart';
import 'package:flutter/material.dart';

import '../../core/models/memory_log.dart';
import '../../core/models/place_genre.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/widgets/stamp_celebration.dart';
import '../timeline/entry_detail_sheet.dart';
import '../../core/strings.dart';

/// 記録のスタンプの種類。ジャンルを残す前の記録は、どのジャンルにも入らないスタンプにする
StampDesign stampDesignOf(MemoryLog log) {
  for (final PlaceGenre g in PlaceGenre.values) {
    if (g.id == log.genre) {
      return StampDesign.of(g);
    }
  }
  return StampDesign.plain;
}

/// スタンプ帳の1つ。手で押したように少し傾け、1人目は金色にする
class StampBookStamp extends StatelessWidget {
  const StampBookStamp({super.key, required this.log, this.size = 96});

  final MemoryLog log;
  final double size;

  @override
  Widget build(BuildContext context) {
    final StampDesign design = stampDesignOf(log);
    final bool pioneer = log.order == 1;
    final DateTime d = log.createdAt;
    // 記録ごとに決まった向きにし、読み直すたびに傾きが変わらないようにする
    final double tilt = ((log.id.hashCode % 15) - 7) / 100;
    final int? order = log.order;
    return Transform.rotate(
      angle: tilt,
      child: StampSeal(
        size: size,
        ink: pioneer ? AppTheme.sealGold : design.ink,
        caption: l10n.stampBookDate(d.month, d.day),
        label: order == null ? design.label : l10n.orderLabel(order),
        design: design,
        glow: false,
      ),
    );
  }
}

/// 押すと記録の詳細を開く
class _Tappable extends StatelessWidget {
  const _Tappable({required this.log, required this.child});

  final MemoryLog log;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final String name = _nameOf(context, log);
    return Semantics(
      button: true,
      label: l10n.stampBookStampLabel(
        name.isEmpty ? l10n.place : name,
        log.createdAt.month,
        log.createdAt.day,
      ),
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => showEntryDetail(
          context,
          EntryDetail(
            placeId: log.placeId,
            placeName: name,
            stars: log.stars,
            comment: log.comment,
            date: log.createdAt,
            order: log.order,
            mine: true,
            photoId: log.photoId,
            genre: log.genre,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// 場所の名前。実績のページは Places API の上限を使わないよう名前なしで読むので、ほかの画面で読んだ名前を使う
String _nameOf(BuildContext context, MemoryLog log) => log.placeName.isNotEmpty
    ? log.placeName
    : Services.of(context).api.placeNames[log.placeId] ?? '';

/// 集めるスタンプの種類（どのジャンルにも入らない場所の無地のスタンプは数えない）
const List<StampDesign> collectibleStamps = <StampDesign>[
  StampDesign.worship,
  StampDesign.food,
  StampDesign.nature,
  StampDesign.culture,
  StampDesign.view,
  StampDesign.shopping,
];

/// 実績のページの「スタンプ帳」。上に集めた数と種類、下に月ごとのスタンプを3列ほどの格子で並べる
class StampBookView extends StatelessWidget {
  const StampBookView({super.key, required this.logs, this.padding});

  /// 新しい順の記録
  final List<MemoryLog> logs;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EdgeInsets pad =
        padding ??
        EdgeInsets.fromLTRB(
          16,
          4,
          16,
          MediaQuery.paddingOf(context).bottom + 24,
        );
    final Map<String, List<MemoryLog>> byMonth = <String, List<MemoryLog>>{};
    for (final MemoryLog l in logs) {
      byMonth
          .putIfAbsent(
            l10n.stampBookMonth(l.createdAt.year, l.createdAt.month),
            () => <MemoryLog>[],
          )
          .add(l);
    }
    final Map<StampDesign, int> counts = <StampDesign, int>{};
    for (final MemoryLog l in logs) {
      counts.update(stampDesignOf(l), (int n) => n + 1, ifAbsent: () => 1);
    }
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 0),
          sliver: SliverToBoxAdapter(
            child: _StampSummary(total: logs.length, counts: counts),
          ),
        ),
        if (logs.isEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad.left, 24, pad.right, 0),
            sliver: SliverToBoxAdapter(
              child: Text(
                l10n.stampBookEmpty,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        for (final MapEntry<String, List<MemoryLog>> month
            in byMonth.entries) ...<Widget>[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad.left, 24, pad.right, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(month.key, style: theme.textTheme.titleMedium),
                  const SizedBox(width: 8),
                  Text(
                    l10n.stampBookMonthCount(month.value.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pad.left),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 128,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.74,
              ),
              itemCount: month.value.length,
              itemBuilder: (BuildContext context, int i) {
                final MemoryLog log = month.value[i];
                final String name = _nameOf(context, log);
                return _Tappable(
                  log: log,
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: LayoutBuilder(
                            builder: (_, BoxConstraints box) => StampBookStamp(
                              log: log,
                              size: box.biggest.shortestSide,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        name.isEmpty ? stampDesignOf(log).label : name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
        if (logs.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad.left, 16, pad.right, pad.bottom),
            sliver: const SliverToBoxAdapter(child: GoogleMapsAttribution()),
          )
        else
          SliverToBoxAdapter(child: SizedBox(height: pad.bottom)),
      ],
    );
  }
}

/// スタンプ帳の上のまとめ。押した数と、集めた種類（6種類のうちいくつ）を、種類ごとの小さなスタンプで見せる
class _StampSummary extends StatelessWidget {
  const _StampSummary({required this.total, required this.counts});

  final int total;
  final Map<StampDesign, int> counts;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int kinds = collectibleStamps
        .where((StampDesign d) => (counts[d] ?? 0) > 0)
        .length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text('$total', style: AppTheme.number(34)),
                const SizedBox(width: 6),
                Text(
                  l10n.stampBookTotalUnit,
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  l10n.stampBookKinds(kinds, collectibleStamps.length),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                for (final StampDesign d in collectibleStamps)
                  Expanded(
                    child: _KindBadge(design: d, count: counts[d] ?? 0),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 種類ごとの小さなスタンプ。まだ押していない種類は薄く出し、集めたくなるようにする
class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.design, required this.count});

  final StampDesign design;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool got = count > 0;
    return Semantics(
      label: l10n.stampBookKindCount(design.label, count),
      excludeSemantics: true,
      child: Column(
        children: <Widget>[
          Opacity(
            opacity: got ? 1 : 0.22,
            child: Container(
              width: 40,
              height: 40,
              decoration: ShapeDecoration(
                color: got ? design.ink.withValues(alpha: 0.12) : null,
                shape: design.shape(
                  BorderSide(color: design.ink, width: 2),
                  40,
                ),
              ),
              child: Icon(design.motif, size: 20, color: design.ink),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            design.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
          Text(
            got ? '$count' : '—',
            style: theme.textTheme.labelSmall?.copyWith(
              color: got ? design.ink : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
