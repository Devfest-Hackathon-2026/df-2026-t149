import 'package:flutter/material.dart';

import '../../core/api/uramichi_api.dart';
import '../../core/models/achievement_stats.dart';
import '../../core/models/memory_log.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/widgets/responsive_grid.dart';
import '../../core/widgets/screen_header.dart';
import '../../core/widgets/state_view.dart';
import 'achievement_widgets.dart';
import 'achievements.dart';
import 'stamp_book.dart';
import '../../core/strings.dart';

/// 実績：思い出ログから決まる実績と、その進み具合
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  /// 広い画面でも読みやすいよう、カードを並べる範囲の幅を抑える
  static const double _maxWidth = 1120;

  Stream<List<MemoryLog>>? _logs;

  /// 利用者全体の集計。読めないとき（ダミーデータだけで動くときや通信できないとき）は割合を出さない
  AchievementStats? _stats;

  /// 最後にサーバーに知らせた実績。同じ内容を何度も送らない
  String? _reported;

  /// 一覧に出す実績の絞り込み
  AchievementFilter _filter = AchievementFilter.all;

  /// 実績とスタンプ帳のどちらを見せるか。1つのページに並べると長くなりすぎるため切り替える
  bool _showStamps = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 実績の計算に場所の名前はいらないので、Places API の上限を使わない
    _logs ??= Services.of(context).checkins.watchLogs(withNames: false);
  }

  /// 自分の実績を知らせてから、全体の集計を読む。自分の分を数えた割合を見せるため
  Future<void> _report(Map<String, int> tiers) async {
    final List<String> parts = <String>[
      for (final MapEntry<String, int> e in tiers.entries)
        '${e.key}:${e.value}',
    ]..sort();
    final String key = parts.join(',');
    if (key == _reported) {
      return;
    }
    _reported = key;
    final UramichiApi api = Services.of(context).api;
    try {
      await api.putAchievements(tiers);
      final AchievementStats? stats = await api.fetchAchievementStats();
      if (mounted && stats != null) {
        setState(() => _stats = stats);
      }
    } catch (error) {
      // 割合は補助の情報なので、読めなくても実績は見せる。次に開いたときに送り直す
      debugPrint('実績の集計を読めません: $error');
      _reported = null;
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ほかのタブと同じく、上に見出しを置く
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: ScreenHeader(title: l10n.tabAchievements),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: <ButtonSegment<bool>>[
                  ButtonSegment<bool>(
                    value: false,
                    icon: const Icon(Icons.emoji_events_outlined),
                    label: Text(l10n.achievementsViewAchievements),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    icon: const Icon(Icons.approval_outlined),
                    label: Text(l10n.achievementsViewStamps),
                  ),
                ],
                selected: <bool>{_showStamps},
                onSelectionChanged: (Set<bool> v) =>
                    setState(() => _showStamps = v.first),
              ),
            ),
          ),
        ),
        Expanded(child: _body()),
      ],
    ),
  );

  Widget _body() => StreamBuilder<List<MemoryLog>>(
    stream: _logs,
    builder: (BuildContext context, AsyncSnapshot<List<MemoryLog>> snap) {
      if (snap.hasError && !snap.hasData) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(describeError(snap.error!)),
          ),
        );
      }
      if (!snap.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_showStamps) {
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: StampBookView(
              logs: <MemoryLog>[...snap.data!]
                ..sort(
                  (MemoryLog a, MemoryLog b) =>
                      b.createdAt.compareTo(a.createdAt),
                ),
            ),
          ),
        );
      }
      final List<AchievementProgress> list = computeAchievements(snap.data!);
      // 描いている途中に状態を変えないよう、描いた後に送る
      final Map<String, int> tiers = unlockedTiers(list);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _report(tiers);
        }
      });
      final int unlocked = list
          .where((AchievementProgress a) => a.unlocked)
          .length;
      final List<AchievementProgress> shown = <AchievementProgress>[
        for (final AchievementProgress a in list)
          if (_filter.matches(a)) a,
      ];
      final List<AchievementProgress> normal = <AchievementProgress>[
        for (final AchievementProgress a in shown)
          if (!a.definition.secret) a,
      ];
      final List<AchievementProgress> secret = <AchievementProgress>[
        for (final AchievementProgress a in shown)
          if (a.definition.secret) a,
      ];
      final int secretTotal = list
          .where((AchievementProgress a) => a.definition.secret)
          .length;
      final int secretUnlocked = list
          .where((AchievementProgress a) => a.definition.secret && a.unlocked)
          .length;
      final List<AchievementProgress> almost = almostThere(list);
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final int columns = ResponsiveGrid.columnsFor(box.maxWidth - 32);
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  MediaQuery.paddingOf(context).bottom + 24,
                ),
                children: <Widget>[
                  _Summary(list: list, unlocked: unlocked),
                  if (almost.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 20),
                    Text(
                      l10n.almostUnlocked,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ...ResponsiveGrid.rows(
                      <Widget>[
                        for (final AchievementProgress a in almost)
                          _AlmostTile(achievement: a, stats: _stats),
                      ],
                      columns: columns,
                      spacing: 8,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: SegmentedButton<AchievementFilter>(
                        showSelectedIcon: false,
                        segments: <ButtonSegment<AchievementFilter>>[
                          for (final AchievementFilter f
                              in AchievementFilter.values)
                            ButtonSegment<AchievementFilter>(
                              value: f,
                              label: Text(f.label),
                            ),
                        ],
                        selected: <AchievementFilter>{_filter},
                        onSelectionChanged: (Set<AchievementFilter> s) =>
                            setState(() => _filter = s.first),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        _filter == AchievementFilter.unlocked
                            ? l10n.noUnlockedAchievements
                            : l10n.allAchievementsUnlocked,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ...ResponsiveGrid.rows(
                    <Widget>[
                      for (final AchievementProgress a in normal)
                        _AchievementTile(achievement: a, stats: _stats),
                    ],
                    columns: columns,
                    spacing: 10,
                  ),
                  if (secret.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 24),
                    Text(
                      l10n.secretAchievementCount(secretUnlocked, secretTotal),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.secretAchievementHelp,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    ...ResponsiveGrid.rows(
                      <Widget>[
                        for (final AchievementProgress a in secret)
                          _AchievementTile(achievement: a, stats: _stats),
                      ],
                      columns: columns,
                      spacing: 10,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

/// 実績の一覧の絞り込み
enum AchievementFilter {
  all(),
  unlocked(),
  locked();

  const AchievementFilter();
  String get label => switch (this) {
    all => l10n.filterAll,
    unlocked => l10n.filterUnlocked,
    locked => l10n.filterLocked,
  };

  bool matches(AchievementProgress a) => switch (this) {
    all => true,
    unlocked => a.unlocked,
    locked => !a.unlocked,
  };
}

/// 次の段階まで近い実績を、近い順に最大 [count] 件返す。
/// 条件の分からないシークレット実績と、まだ1つも進んでいない実績は除く
List<AchievementProgress> almostThere(
  List<AchievementProgress> list, {
  int count = 3,
}) {
  double ratio(AchievementProgress a) => a.progress / a.nextGoal!;
  final List<AchievementProgress> candidates =
      <AchievementProgress>[
        for (final AchievementProgress a in list)
          if (!a.hidden &&
              a.nextGoal != null &&
              a.progress > 0 &&
              a.progress < a.nextGoal!)
            a,
      ]..sort((AchievementProgress a, AchievementProgress b) {
        final int byRatio = ratio(b).compareTo(ratio(a));
        return byRatio != 0
            ? byRatio
            : (a.nextGoal! - a.progress).compareTo(b.nextGoal! - b.progress);
      });
  return candidates.take(count).toList();
}

/// もう少しで解除できる実績。押すと詳細を開く
class _AlmostTile extends StatelessWidget {
  const _AlmostTile({required this.achievement, this.stats});

  final AchievementProgress achievement;
  final AchievementStats? stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AchievementDefinition d = achievement.definition;
    final int left = achievement.nextGoal! - achievement.progress;
    return Semantics(
      button: true,
      label: l10n.almostTileLabel(d.title, left),
      excludeSemantics: true,
      child: Material(
        color: scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              showAchievementDetail(context, achievement, stats: stats),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            child: Row(
              children: <Widget>[
                Icon(d.icon, color: scheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(d.title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 6),
                      NextGoalBar(achievement: achievement),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 解除した数、段階ごとのメダルの数、最後に解除した実績
class _Summary extends StatelessWidget {
  const _Summary({required this.list, required this.unlocked});

  final List<AchievementProgress> list;
  final int unlocked;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int total = list.length;
    final Map<AchievementTier, int> medals = <AchievementTier, int>{
      for (final AchievementTier t in AchievementTier.values)
        t: list.where((AchievementProgress a) => a.tierLevel == t).length,
    };
    AchievementProgress? latest;
    for (final AchievementProgress a in list) {
      final DateTime? at = a.tierReachedAt;
      if (a.unlocked &&
          at != null &&
          (latest == null || at.isAfter(latest.tierReachedAt!))) {
        latest = a;
      }
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 見出しはページの上の ScreenHeader に出す
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text('$unlocked', style: AppTheme.number(32)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 4),
                  child: Text(
                    l10n.unlockedOfTotal(total),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Spacer(),
                for (final AchievementTier t in AchievementTier.values)
                  _MedalCount(tier: t, count: medals[t]!),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : unlocked / total,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 10),
            if (latest case final AchievementProgress a)
              Row(
                children: <Widget>[
                  Icon(Icons.history, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.recentUnlock(
                        a.definition.title,
                        a.tierReachedAt!.month,
                        a.tierReachedAt!.day,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              )
            else
              Text(
                l10n.achievementsEmptyHelp,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 段階の色の丸と、その段階に達した実績の数
class _MedalCount extends StatelessWidget {
  const _MedalCount({required this.tier, required this.count});

  final AchievementTier tier;
  final int count;

  @override
  Widget build(BuildContext context) {
    final (Color light, Color dark) = AppTheme.tierColors[tier.index];
    return Semantics(
      label: '${tier.label} $count',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(left: 10, bottom: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[light, dark],
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text('$count', style: AppTheme.number(14)),
          ],
        ),
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.achievement, this.stats});

  final AchievementProgress achievement;
  final AchievementStats? stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AchievementDefinition d = achievement.definition;
    final bool on = achievement.unlocked;
    final bool hidden = achievement.hidden;
    final String title = hidden ? l10n.hiddenTitle : d.title;
    final Color accent = achievementColor(achievement);
    final AchievementTier? tier = achievement.tierLevel;
    final DateTime? at = achievement.tierReachedAt;
    return Semantics(
      button: true,
      label: switch ((on, tier)) {
        (false, _) => l10n.achievementTileLocked(title),
        (true, null) => l10n.achievementTileUnlocked(title),
        (true, final AchievementTier tier) => l10n.achievementTileUnlockedTier(
          title,
          tier.label,
        ),
      },
      child: Card(
        margin: EdgeInsets.zero,
        // 解除した実績は、テーマの色ではなく実績の色（段階の金属の色・めずらしさの色）で目立たせる
        color: on
            ? Color.alphaBlend(accent.withValues(alpha: 0.10), scheme.surface)
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          side: BorderSide(
            color: on ? accent.withValues(alpha: 0.6) : scheme.outlineVariant,
            width: on ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              showAchievementDetail(context, achievement, stats: stats),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                AchievementBadge(achievement: achievement),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              title,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (tier != null) ...<Widget>[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                tier.label,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hidden
                            ? l10n.achievementHint(d.hint)
                            : achievement.currentDescription,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!hidden && achievement.nextGoal != null)
                        NextGoalBar(achievement: achievement)
                      else if (at != null)
                        Text(
                          achievement.completed && d.tiered
                              ? l10n.achievementAllTiersOn(
                                  at.year,
                                  at.month,
                                  at.day,
                                )
                              : l10n.achievementUnlockedOnDate(
                                  at.year,
                                  at.month,
                                  at.day,
                                ),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (unlockRateLabel(stats, achievement)
                          case final String rate) ...<Widget>[
                        const SizedBox(height: 6),
                        UnlockRate(label: rate),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
