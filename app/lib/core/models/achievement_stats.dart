import '../strings.dart';

/// アプリの利用者全体で、それぞれの実績を解除した人数（GET /api/achievements/stats）
class AchievementStats {
  const AchievementStats({required this.users, required this.counts});

  factory AchievementStats.fromJson(Map<String, dynamic> j) => AchievementStats(
    users: (j['users'] as num?)?.toInt() ?? 0,
    counts: <String, List<int>>{
      for (final MapEntry<String, dynamic> e
          in ((j['achievements'] as Map?) ?? const <String, dynamic>{})
              .cast<String, dynamic>()
              .entries)
        e.key: <int>[
          for (final Object? n in e.value as List<Object?>) (n! as num).toInt(),
        ],
    },
  );

  /// 実績を知らせた利用者の数
  final int users;

  /// 実績の ID → 段階1〜3それぞれの、その段階以上を解除した人数
  final Map<String, List<int>> counts;

  /// [tier] 段階（段階のない実績は 1）以上を解除した人の割合（0〜1）。利用者がいなければ null
  double? rate(String id, int tier) {
    if (users == 0 || tier < 1) {
      return null;
    }
    final List<int> c = counts[id] ?? const <int>[];
    return (tier <= c.length ? c[tier - 1] : 0) / users;
  }

  /// 割合を「12%」のように書く。0 より大きく 1% に満たないときは「1%未満」
  static String percent(double rate) {
    if (rate > 0 && rate < 0.01) {
      return l10n.percentUnderOne;
    }
    return '${(rate * 100).round()}%';
  }
}
