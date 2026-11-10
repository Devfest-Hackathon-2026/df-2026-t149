import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/models/memory_log.dart';
import '../../core/share.dart';
import '../../core/theme.dart';
import '../../core/widgets/share_buttons.dart';
import '../../core/widgets/stamp_celebration.dart';
import '../../core/widgets/star_rating.dart';
import '../achievements/achievement_widgets.dart';
import '../achievements/achievements.dart';
import 'badges.dart';
import '../../core/strings.dart';

/// 思い出を残したあとの画面。「チェックインスタンプ」が押され、何人目か・★評価・解除した実績を見せ、シェアできる
class CheckinCelebrationScreen extends StatefulWidget {
  const CheckinCelebrationScreen({
    super.key,
    required this.log,
    this.unlocked = const <AchievementProgress>[],
    this.level = CelebrationLevel.newPlace,
    this.openUrl = openExternal,
    this.shareImage = shareImageWithSystem,
    this.design = StampDesign.plain,
  });

  /// チェックインスタンプの種類（場所のジャンルで決める）
  final StampDesign design;

  /// 残した記録
  final MemoryLog log;

  /// この記録で新しく解除した実績
  final List<AchievementProgress> unlocked;

  /// 祝い方の強さ。実績を解除したときは、スタンプのあとにメダルの演出と振動を続ける
  final CelebrationLevel level;

  final OpenUrl openUrl;

  /// Instagram などへ画像で共有する
  final ShareImage shareImage;

  @override
  State<CheckinCelebrationScreen> createState() =>
      _CheckinCelebrationScreenState();
}

class _CheckinCelebrationScreenState extends State<CheckinCelebrationScreen> {
  /// スタンプが押されてから、実績のメダルを出し始めるまで
  static const Duration _medalStart = Duration(milliseconds: 1400);

  /// メダルを1枚ずつ出す間隔
  static const Duration _medalGap = Duration(milliseconds: 900);

  String get _shareText => checkinShareText(
    placeName: widget.log.placeName,
    order: widget.log.order,
    stars: widget.log.stars,
    comment: widget.log.comment,
  );

  /// スタンプと場所の名前の部分。Instagram へは、この部分を画像にして共有する
  final GlobalKey _card = GlobalKey();

  void _done() =>
      Navigator.of(context).popUntil((Route<void> route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final MemoryLog log = widget.log;
    final int? order = log.order;
    final String? badge = order == null ? null : badgeForOrder(order);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l10n.celebrationTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.close,
            icon: const Icon(Icons.close),
            onPressed: _done,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          // Instagram に送る画像を、下までスクロールした後でも作れるよう、一覧の全体をいつも作っておく
          // （ListView は見えない部分を作らないので、画像にする部分が消えてしまう）
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Instagram に共有する画像にする部分。透明にならないよう、地の色を塗る
                RepaintBoundary(
                  key: _card,
                  child: ColoredBox(
                    color: scheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: <Widget>[
                          StampCelebration(
                            level: widget.level,
                            label: order == null
                                ? l10n.stampRecorded
                                : l10n.orderLabel(order),
                            caption: switch (widget.level) {
                              CelebrationLevel.revisit => l10n.stampRevisit,
                              _ => l10n.stampFirstVisit,
                            },
                            size: 300,
                            design: widget.design,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            log.placeName,
                            textAlign: TextAlign.center,
                            style: AppTheme.placeName(22),
                          ),
                          Text(
                            l10n.hashtag,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (badge != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Center(
                    child: Chip(
                      avatar: const Icon(Icons.military_tech),
                      label: Text(badge),
                    ),
                  ),
                ],
                if (order == null)
                  Text(
                    l10n.checkinPendingOrder,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                const SizedBox(height: 12),
                Center(
                  child: StarRating(value: log.stars.toDouble(), size: 32),
                ),
                Text(
                  starsLabel(log.stars),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                if (log.comment.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    l10n.quotedComment(log.comment),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
                if (widget.unlocked.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 24),
                  Text(
                    widget.unlocked.any(
                          (AchievementProgress a) => a.definition.secret,
                        )
                        ? l10n.secretAchievementUnlocked
                        : l10n.achievementUnlocked,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < widget.unlocked.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: 8),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      color: Color.alphaBlend(
                        achievementColor(
                          widget.unlocked[i],
                        ).withValues(alpha: 0.12),
                        scheme.surface,
                      ),
                      child: InkWell(
                        onTap: () =>
                            showAchievementDetail(context, widget.unlocked[i]),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                          child: Row(
                            children: <Widget>[
                              MedalReveal(
                                achievement: widget.unlocked[i],
                                delay: _medalStart + _medalGap * i,
                                radius: 22,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      widget.unlocked[i].definition.title,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    Text(
                                      unlockHeadline(widget.unlocked[i]),
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: achievementColor(
                                              widget.unlocked[i],
                                            ),
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    Text(
                                      widget.unlocked[i].currentDescription,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 24),
                Text(
                  l10n.shareHeading,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ShareButtons(
                  text: _shareText,
                  captureImage: () => captureBoundary(_card),
                  openUrl: widget.openUrl,
                  shareImage: widget.shareImage,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _done,
                  child: Text(l10n.findNextPlace),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
