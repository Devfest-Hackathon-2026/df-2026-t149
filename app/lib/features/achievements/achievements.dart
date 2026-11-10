import 'package:flutter/material.dart';

import '../../core/models/memory_log.dart';
import '../../core/strings.dart';

/// 実績の定義。思い出ログから進み具合を計算する。
///
/// 端末で計算するのは、圏外で残してまだ送っていない記録と、Firebase を使わない設定で端末に保存した記録も
/// 数えるためである（docs/decisions.md の D-018）。記録は [CheckinRepository.watchLogs] から受け取る。
/// 実績を足すときは [achievementDefinitions] に1件足す。[id] は変えない
class AchievementDefinition {
  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.goal = 1,
    this.tiers,
    required this.counts,
    this.detail = '',
    this.distinctPlace = false,
    this.distinctKey,
    this.samePlace = false,
    this.groupKey,
    this.secret = false,
    this.hint = '',
    this.rarity = AchievementRarity.common,
  });

  final String id;
  final String title;

  /// 解除の条件（一覧に出す短い文）
  final String description;

  /// 詳細の画面に出す説明。空なら [description] だけを出す
  final String detail;
  final IconData icon;

  /// 解除に必要な記録の数（段階のない実績）。[tiers] があれば使わない
  final int goal;

  /// 段階のある実績の、ブロンズ・シルバー・ゴールドに必要な数（小さい順）。
  /// [description] の「{n}」は次の段階の数に置き換えて表示する
  final List<int>? tiers;

  /// 段階ごとに必要な数。段階のない実績は [goal] の1つだけ
  List<int> get goals => tiers ?? <int>[goal];

  /// 最後の段階に必要な数
  int get finalGoal => goals.last;

  bool get tiered => tiers != null;

  /// 「{n}」を [n] に置き換えた条件の文
  String describe(int n) => description.replaceAll('{n}', '$n');

  /// 記録1件が、この実績の進み具合に数えられるか
  final bool Function(MemoryLog log) counts;

  /// true なら、同じ場所の記録は最初の1件だけ数える
  final bool distinctPlace;

  /// 記録をまとめる鍵。同じ鍵の記録は最初の1件だけ数える（日付ごとに1件、など）。
  /// [distinctPlace] より優先する
  final String Function(MemoryLog log)? distinctKey;

  /// true なら、1つの場所の記録だけで [goal] に達したときに解除する。進み具合は最も多い場所の数
  final bool samePlace;

  /// 記録をまとめる単位（日付など）。どれか1つのまとまりで [goal] に達したときに解除する。
  /// [distinctPlace] と組み合わせると、まとまりの中の同じ場所は1回だけ数える
  final String Function(MemoryLog log)? groupKey;

  /// シークレット実績か。解除するまで名前と条件を隠し、[hint] だけを見せる
  final bool secret;

  /// シークレット実績のヒント
  final String hint;

  final AchievementRarity rarity;

  String? _keyOf(MemoryLog l) =>
      distinctKey?.call(l) ?? (distinctPlace ? l.placeId : null);
}

/// 段階のある実績の段階。色はテーマと別の、金属の色にする（AppTheme.tierColors）
enum AchievementTier {
  bronze(),
  silver(),
  gold();

  const AchievementTier();
  String get label => switch (this) {
    bronze => l10n.tierBronze,
    silver => l10n.tierSilver,
    gold => l10n.tierGold,
  };
}

/// 実績のめずらしさ。詳細の画面と解除の演出の色を変える
enum AchievementRarity {
  common(),
  rare(),
  epic(),
  legend();

  const AchievementRarity();
  String get label => switch (this) {
    common => l10n.rarityCommon,
    rare => l10n.rarityRare,
    epic => l10n.rarityEpic,
    legend => l10n.rarityLegend,
  };
}

bool _always(MemoryLog _) => true;

String _dayKey(MemoryLog l) =>
    '${l.createdAt.year}-${l.createdAt.month}-${l.createdAt.day}';

bool _isWeekend(MemoryLog l) =>
    l.createdAt.weekday == DateTime.saturday ||
    l.createdAt.weekday == DateTime.sunday;

/// 実績の一覧（表示する順）。シークレット実績は最後にまとめる
final List<AchievementDefinition> achievementDefinitions =
    <AchievementDefinition>[
      AchievementDefinition(
        id: 'first_log',
        title: l10n.achFirstStepTitle,
        description: l10n.achFirstStepDescription,
        detail: l10n.achFirstStepDetail,
        icon: Icons.flag_outlined,
        goal: 1,
        counts: _always,
      ),
      AchievementDefinition(
        id: 'pioneer',
        title: l10n.achPioneerTitle,
        description: l10n.achPioneerDescription,
        detail: l10n.achPioneerDetail,
        icon: Icons.explore_outlined,
        tiers: const <int>[1, 5, 15],
        distinctPlace: true,
        rarity: AchievementRarity.rare,
        counts: (MemoryLog l) => l.order == 1,
      ),
      AchievementDefinition(
        id: 'veteran',
        title: l10n.achVeteranTitle,
        description: l10n.achVeteranDescription,
        detail: l10n.achVeteranDetail,
        icon: Icons.military_tech_outlined,
        tiers: const <int>[3, 10, 25],
        distinctPlace: true,
        rarity: AchievementRarity.rare,
        counts: (MemoryLog l) => (l.order ?? 0) >= 1 && (l.order ?? 0) <= 10,
      ),
      AchievementDefinition(
        id: 'honor_miss',
        title: l10n.achHonorableMissTitle,
        description: l10n.achHonorableMissDescription,
        detail: l10n.achHonorableMissDetail,
        icon: Icons.sentiment_dissatisfied_outlined,
        goal: 1,
        counts: (MemoryLog l) => l.stars <= 2,
      ),
      AchievementDefinition(
        id: 'connoisseur',
        title: l10n.achConnoisseurTitle,
        description: l10n.achConnoisseurDescription,
        detail: l10n.achConnoisseurDetail,
        icon: Icons.thumb_up_outlined,
        tiers: const <int>[5, 15, 30],
        counts: (MemoryLog l) => l.stars >= 4,
      ),
      AchievementDefinition(
        id: 'full_marks',
        title: l10n.achPerfectViewTitle,
        description: l10n.achPerfectViewDescription,
        detail: l10n.achPerfectViewDetail,
        icon: Icons.auto_awesome_outlined,
        tiers: const <int>[3, 10, 20],
        rarity: AchievementRarity.rare,
        counts: (MemoryLog l) => l.stars == 5,
      ),
      AchievementDefinition(
        id: 'wanderer',
        title: l10n.achWalkTitle,
        description: l10n.achWalkDescription,
        detail: l10n.achWalkDetail,
        icon: Icons.route_outlined,
        tiers: <int>[5, 20, 50],
        distinctPlace: true,
        counts: _always,
      ),
      AchievementDefinition(
        id: 'regular',
        title: l10n.achRegularTitle,
        description: l10n.achRegularDescription,
        detail: l10n.achRegularDetail,
        icon: Icons.star_outline,
        tiers: <int>[10, 30, 50],
        counts: _always,
      ),
      AchievementDefinition(
        id: 'three_days',
        title: l10n.achConsistentTitle,
        description: l10n.achConsistentDescription,
        detail: l10n.achConsistentDetail,
        icon: Icons.calendar_month_outlined,
        tiers: const <int>[3, 7, 30],
        distinctKey: _dayKey,
        counts: _always,
      ),
      AchievementDefinition(
        id: 'commentator',
        title: l10n.achCommenterTitle,
        description: l10n.achCommenterDescription,
        detail: l10n.achCommenterDetail,
        icon: Icons.chat_bubble_outline,
        tiers: const <int>[10, 30, 60],
        counts: (MemoryLog l) => l.comment.trim().isNotEmpty,
      ),
      AchievementDefinition(
        id: 'storyteller',
        title: l10n.achStorytellerTitle,
        description: l10n.achStorytellerDescription,
        detail: l10n.achStorytellerDetail,
        icon: Icons.campaign_outlined,
        tiers: const <int>[3, 10, 30],
        counts: (MemoryLog l) => l.isPublic,
      ),
      // ここからシークレット実績。条件は解除するまで見せない
      AchievementDefinition(
        id: 'runner_up',
        title: l10n.achSoCloseTitle,
        description: l10n.achSoCloseDescription,
        detail: l10n.achSoCloseDetail,
        icon: Icons.looks_two_outlined,
        goal: 1,
        secret: true,
        hint: l10n.achSoCloseHint,
        rarity: AchievementRarity.rare,
        counts: (MemoryLog l) => l.order == 2,
      ),
      AchievementDefinition(
        id: 'kiriban',
        title: l10n.achRoundNumberTitle,
        description: l10n.achRoundNumberDescription,
        detail: l10n.achRoundNumberDetail,
        icon: Icons.pin_outlined,
        goal: 1,
        secret: true,
        hint: l10n.achRoundNumberHint,
        rarity: AchievementRarity.epic,
        counts: (MemoryLog l) => (l.order ?? 0) >= 10 && l.order! % 10 == 0,
      ),
      AchievementDefinition(
        id: 'night_owl',
        title: l10n.achNightOwlTitle,
        description: l10n.achNightOwlDescription,
        detail: l10n.achNightOwlDetail,
        icon: Icons.nightlight_outlined,
        goal: 1,
        secret: true,
        hint: l10n.achNightOwlHint,
        rarity: AchievementRarity.rare,
        counts: (MemoryLog l) => l.createdAt.hour < 4,
      ),
      AchievementDefinition(
        id: 'early_bird',
        title: l10n.achEarlyBirdTitle,
        description: l10n.achEarlyBirdDescription,
        detail: l10n.achEarlyBirdDetail,
        icon: Icons.wb_twilight_outlined,
        goal: 1,
        secret: true,
        hint: l10n.achEarlyBirdHint,
        rarity: AchievementRarity.rare,
        counts: (MemoryLog l) => l.createdAt.hour >= 5 && l.createdAt.hour < 7,
      ),
      AchievementDefinition(
        id: 'hashigo',
        title: l10n.achHopperTitle,
        description: l10n.achHopperDescription,
        detail: l10n.achHopperDetail,
        icon: Icons.directions_walk,
        goal: 3,
        groupKey: _dayKey,
        distinctPlace: true,
        secret: true,
        hint: l10n.achHopperHint,
        rarity: AchievementRarity.rare,
        counts: _always,
      ),
      AchievementDefinition(
        id: 'weekend',
        title: l10n.achWeekendTitle,
        description: l10n.achWeekendDescription,
        detail: l10n.achWeekendDetail,
        icon: Icons.weekend_outlined,
        goal: 5,
        secret: true,
        hint: l10n.achWeekendHint,
        counts: _isWeekend,
      ),
      AchievementDefinition(
        id: 'poet',
        title: l10n.achTalkativeTitle,
        description: l10n.achTalkativeDescription,
        detail: l10n.achTalkativeDetail,
        icon: Icons.history_edu_outlined,
        goal: 1,
        secret: true,
        hint: l10n.achTalkativeHint,
        counts: (MemoryLog l) => l.comment.trim().runes.length >= 100,
      ),
      AchievementDefinition(
        id: 'regular_spot',
        title: l10n.achRevisitTitle,
        description: l10n.achRevisitDescription,
        detail: l10n.achRevisitDetail,
        icon: Icons.repeat,
        goal: 3,
        samePlace: true,
        secret: true,
        hint: l10n.achRevisitHint,
        rarity: AchievementRarity.epic,
        counts: _always,
      ),
    ];

/// 実績1件の進み具合
class AchievementProgress {
  const AchievementProgress({
    required this.definition,
    required this.progress,
    this.tier = 0,
    this.unlockedAt,
    this.unlockedBy,
    this.tierReachedAt,
    this.previousTier,
  });

  final AchievementDefinition definition;

  /// 今の値。最後の段階の数を超えない
  final int progress;

  /// 達した段階の数（0 はまだ。段階のない実績は 0 か 1）
  final int tier;

  /// はじめて条件を満たした（最初の段階に達した）記録の日時。まだなら null
  final DateTime? unlockedAt;

  /// はじめて条件を満たした記録。まだなら null
  final MemoryLog? unlockedBy;

  /// 今の段階に達した日時
  final DateTime? tierReachedAt;

  /// [newlyUnlocked] が返すときだけ入る、前の段階の数。昇格の演出に使う
  final int? previousTier;

  bool get unlocked => tier >= 1;

  /// 名前と条件を隠すか（解除していないシークレット実績）
  bool get hidden => definition.secret && !unlocked;

  /// 達した段階（段階のある実績で、1つ以上達しているとき）
  AchievementTier? get tierLevel => definition.tiered && tier >= 1
      ? AchievementTier.values[(tier - 1).clamp(
          0,
          AchievementTier.values.length - 1,
        )]
      : null;

  /// 次の段階に必要な数。すべて達していれば null
  int? get nextGoal =>
      tier < definition.goals.length ? definition.goals[tier] : null;

  /// すべての段階に達したか
  bool get completed => tier >= definition.goals.length;

  /// 今の条件の文（次の段階、すべて達したら最後の段階）
  String get currentDescription =>
      definition.describe(nextGoal ?? definition.finalGoal);

  /// 昇格したか（2つ目以降の段階に上がった）
  bool get promoted => previousTier != null && previousTier! >= 1;

  AchievementProgress withPreviousTier(int previous) => AchievementProgress(
    definition: definition,
    progress: progress,
    tier: tier,
    unlockedAt: unlockedAt,
    unlockedBy: unlockedBy,
    tierReachedAt: tierReachedAt,
    previousTier: previous,
  );
}

/// 思い出ログ（順番は問わない）から、すべての実績の進み具合を定義の順に返す
List<AchievementProgress> computeAchievements(
  List<MemoryLog> logs, {
  List<AchievementDefinition>? definitions,
}) {
  final List<MemoryLog> sorted = List<MemoryLog>.of(logs)
    ..sort((MemoryLog a, MemoryLog b) => a.createdAt.compareTo(b.createdAt));
  return <AchievementProgress>[
    for (final AchievementDefinition d in definitions ?? achievementDefinitions)
      _progress(d, _steps(d, sorted)),
  ];
}

/// [before] より [after] で段階が上がった実績（はじめての解除と昇格。定義の順）
List<AchievementProgress> newlyUnlocked(
  List<MemoryLog> before,
  List<MemoryLog> after, {
  List<AchievementDefinition>? definitions,
}) {
  final Map<String, int> had = <String, int>{
    for (final AchievementProgress a in computeAchievements(
      before,
      definitions: definitions,
    ))
      a.definition.id: a.tier,
  };
  return <AchievementProgress>[
    for (final AchievementProgress a in computeAchievements(
      after,
      definitions: definitions,
    ))
      if (a.tier > (had[a.definition.id] ?? 0))
        a.withPreviousTier(had[a.definition.id] ?? 0),
  ];
}

/// 数が1つ増えた記録を、増えた順に返す。i 番目の記録で数が i+1 になる
List<MemoryLog> _steps(AchievementDefinition d, List<MemoryLog> logs) {
  if (d.samePlace) {
    return _groupedSteps(d, logs, (MemoryLog l) => l.placeId);
  }
  if (d.groupKey case final String Function(MemoryLog) key) {
    return _groupedSteps(d, logs, key);
  }
  final Set<String> seen = <String>{};
  return <MemoryLog>[
    for (final MemoryLog l in logs)
      if (d.counts(l) && (d._keyOf(l) == null || seen.add(d._keyOf(l)!))) l,
  ];
}

/// [groupKey] ごとに数え、最も多いまとまりの数が増えた記録を返す
List<MemoryLog> _groupedSteps(
  AchievementDefinition d,
  List<MemoryLog> logs,
  String Function(MemoryLog) groupKey,
) {
  final Map<String, int> counts = <String, int>{};
  final Map<String, Set<String>> places = <String, Set<String>>{};
  int best = 0;
  final List<MemoryLog> out = <MemoryLog>[];
  for (final MemoryLog l in logs) {
    if (!d.counts(l)) {
      continue;
    }
    final String g = groupKey(l);
    if (d.distinctPlace && !(places[g] ??= <String>{}).add(l.placeId)) {
      continue;
    }
    final int n = (counts[g] ?? 0) + 1;
    counts[g] = n;
    if (n > best) {
      best = n;
      out.add(l);
    }
  }
  return out;
}

AchievementProgress _progress(AchievementDefinition d, List<MemoryLog> steps) {
  final List<int> goals = d.goals;
  final int tier = goals.where((int g) => steps.length >= g).length;
  return AchievementProgress(
    definition: d,
    progress: steps.length.clamp(0, d.finalGoal),
    tier: tier,
    unlockedAt: tier >= 1 ? steps[goals.first - 1].createdAt : null,
    unlockedBy: tier >= 1 ? steps[goals.first - 1] : null,
    tierReachedAt: tier >= 1 ? steps[goals[tier - 1] - 1].createdAt : null,
  );
}

/// サーバーに知らせる、解除した実績と段階（段階のない実績は 1）。まだ解除していない実績は含めない
Map<String, int> unlockedTiers(List<AchievementProgress> list) => <String, int>{
  for (final AchievementProgress a in list)
    if (a.unlocked) a.definition.id: a.tier,
};
