import '../../core/models/memory_log.dart';
import '../../core/strings.dart';

/// バッジの判定（担当：C）。しきい値はチームで決めて調整する。

/// チェックインの順番でもらえるバッジ
String? badgeForOrder(int order) {
  if (order == 1) return l10n.badgePioneer;
  if (order <= 10) return l10n.badgeVeteran(order);
  return null;
}

/// 思い出ログ全体から決まるバッジ
List<String> badgesForLogs(List<MemoryLog> logs) => [
  if (logs.any((l) => l.order == 1)) l10n.badgePioneerShort,
  if (logs.any((l) => l.stars <= 2)) l10n.badgeHonorableMiss,
  if (logs.length >= 5) l10n.badgeRegular,
];
