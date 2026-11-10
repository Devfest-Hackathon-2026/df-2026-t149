import '../../core/widgets/google_maps_notice.dart';
import 'package:flutter/material.dart';

import '../../core/models/memory_log.dart';
import '../../core/widgets/stamp_celebration.dart';
import '../../core/widgets/share_buttons.dart';
import '../../core/models/place_genre.dart';
import '../../core/models/profile.dart';
import '../../core/share.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/log_photo.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../core/widgets/star_rating.dart';
import '../../core/strings.dart';

/// 口コミ（記録）の詳細に出す内容。自分の記録と周辺の記録で同じ形にする
class EntryDetail {
  const EntryDetail({
    required this.placeId,
    required this.placeName,
    required this.stars,
    required this.comment,
    required this.date,
    this.order,
    this.authorName,
    this.authorIcon = '',
    this.mine = false,
    this.photoId,
    this.reactions,
    this.genre,
  });

  /// スタンプの種類（[PlaceGenre.id]）。シェアの画像のスタンプに使う
  final String? genre;

  final String placeId;
  final String placeName;
  final int stars;
  final String comment;
  final DateTime date;
  final int? order;

  /// 投稿者のニックネーム。null は自分の記録、空の文字列はプロフィールのない投稿者
  final String? authorName;
  final String authorIcon;
  final bool mine;

  /// 記録に付けた写真の ID。写真のない記録は null
  final String? photoId;

  /// 反応のボタン（[ReactionBar]）。反応のない記録は null
  final Widget? reactions;

  /// Google マップでこの場所を開く URL。名前を読めなくても place ID で開ける
  Uri get mapsUri =>
      Uri.https('www.google.com', '/maps/search/', <String, String>{
        'api': '1',
        'query': placeName.isEmpty ? l10n.place : placeName,
        'query_place_id': placeId,
      });
}

/// 口コミの詳細を下から開く
Future<void> showEntryDetail(
  BuildContext context,
  EntryDetail entry, {
  OpenUrl openUrl = openExternal,
  List<Widget> actions = const <Widget>[],
}) {
  // 広い画面で下からシートを出すと、横に長い帯になって読みにくいため、中央のダイアログで開く
  if (!WindowSize.of(context).isCompact) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: EntryDetailSheet(
              entry: entry,
              openUrl: openUrl,
              actions: actions,
            ),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext context) =>
        EntryDetailSheet(entry: entry, openUrl: openUrl, actions: actions),
  );
}

class EntryDetailSheet extends StatelessWidget {
  const EntryDetailSheet({
    super.key,
    required this.entry,
    this.openUrl = openExternal,
    this.actions = const <Widget>[],
  });

  final EntryDetail entry;
  final OpenUrl openUrl;

  /// 公開の切り替えや報告など、一覧と同じ操作
  final List<Widget> actions;

  Future<void> _openMaps(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!await openUrl(entry.mapsUri)) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.openMapsFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextStyle? meta = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final DateTime d = entry.date;
    final String time = l10n.dateTimeFull(
      d.year,
      d.month,
      d.day,
      d.hour,
      d.minute.toString().padLeft(2, '0'),
    );
    final String? authorName = entry.authorName;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              entry.placeName.isEmpty
                  ? l10n.placeNameUnavailable
                  : entry.placeName,
              style: AppTheme.placeName(22),
            ),
            if (entry.placeName.isEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(l10n.placeNameLimitReached, style: meta),
            ],
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                StarRating(value: entry.stars.toDouble(), size: 24),
                const SizedBox(width: 8),
                Text(
                  starsLabel(entry.stars),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            if (entry.photoId case final String photoId) ...<Widget>[
              const SizedBox(height: 16),
              LogPhoto(photoId: photoId, height: 240),
            ],
            const SizedBox(height: 16),
            if (entry.comment.isNotEmpty)
              Text(entry.comment, style: theme.textTheme.bodyLarge)
            else
              Text(l10n.noComment, style: meta),
            if (entry.reactions case final Widget reactions) ...<Widget>[
              const SizedBox(height: 12),
              reactions,
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                if (authorName == null)
                  Text(l10n.myLog, style: meta)
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      ProfileAvatar(
                        icon: ProfileIcon.of(entry.authorIcon),
                        size: 24,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        authorName.isEmpty
                            ? l10n.anonymousTraveler
                            : authorName,
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                Text(time, style: meta),
                if (entry.order case final int n)
                  Text(l10n.visitorOrder(n), style: meta),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: () => _openMaps(context),
                  icon: const Icon(Icons.map_outlined),
                  label: Text(l10n.openInGoogleMaps),
                ),
                OutlinedButton.icon(
                  onPressed: () => showEntryShareSheet(context, entry),
                  icon: const Icon(Icons.share_outlined),
                  label: Text(l10n.shareAction),
                ),
                ...actions,
              ],
            ),
            const GoogleMapsAttribution(),
          ],
        ),
      ),
    );
  }
}

/// 記録や口コミをシェアする画面を下から開く。上にシェアする画像の見本、下にシェアの先を並べる
Future<void> showEntryShareSheet(BuildContext context, EntryDetail entry) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => _EntryShareSheet(entry: entry),
    );

class _EntryShareSheet extends StatelessWidget {
  _EntryShareSheet({required this.entry});

  final EntryDetail entry;
  final GlobalKey _card = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final String name = entry.placeName.isEmpty ? l10n.place : entry.placeName;
    final String text = entryShareText(
      placeName: name,
      mine: entry.mine,
      stars: entry.stars,
      comment: entry.comment,
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              entry.mine ? l10n.shareSheetTitle : l10n.shareSheetTitleOthers,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            RepaintBoundary(
              key: _card,
              child: EntryShareCard(entry: entry, placeName: name),
            ),
            const SizedBox(height: 16),
            ShareButtons(
              text: text,
              captureImage: () => captureBoundary(_card),
            ),
          ],
        ),
      ),
    );
  }
}

/// シェアする画像。スタンプ、場所の名前、★（★4以上のとき）、ひとことを1枚にする
class EntryShareCard extends StatelessWidget {
  const EntryShareCard({
    super.key,
    required this.entry,
    required this.placeName,
  });

  final EntryDetail entry;
  final String placeName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    StampDesign design = StampDesign.plain;
    for (final PlaceGenre g in PlaceGenre.values) {
      if (g.id == entry.genre) {
        design = StampDesign.of(g);
      }
    }
    final int? order = entry.order;
    final DateTime d = entry.date;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          StampSeal(
            size: 96,
            ink: order == 1 ? AppTheme.sealGold : design.ink,
            caption: l10n.stampBookDate(d.month, d.day),
            label: order == null ? design.label : l10n.orderLabel(order),
            design: design,
            glow: false,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(placeName, style: AppTheme.placeName(18)),
                if (entry.stars >= 4) ...<Widget>[
                  const SizedBox(height: 4),
                  StarRating(value: entry.stars.toDouble(), size: 18),
                ],
                if (entry.comment.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    entry.comment,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  l10n.shareCardFooter,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
