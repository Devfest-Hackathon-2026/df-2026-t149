import '../../core/widgets/google_maps_notice.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/data/checkin_repository.dart';
import '../../core/geo.dart';
import '../../core/models/memory_log.dart';
import '../../core/models/profile.dart';
import '../../core/models/timeline_entry.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/widgets/log_photo.dart';
import '../../core/widgets/mock_banner.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../core/widgets/screen_header.dart';
import '../../core/widgets/state_view.dart';
import '../checkin/badges.dart';
import '../favorites/favorites_screen.dart';
import '../../core/widgets/star_rating.dart';
import '../../core/models/place.dart';
import '../../core/widgets/favorite_button.dart';
import 'edit_log_sheet.dart';
import 'entry_detail_sheet.dart';
import 'reaction_bar.dart';
import 'report_sheet.dart';
import '../../core/widgets/rating_summary.dart';
import '../../core/strings.dart';

enum TimelineScope { mine, favorites, nearby }

/// タイムライン：自分の記録、お気に入りの場所、基準の地点の周辺で公開された記録
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    super.key,
    required this.nearbyCenter,
    required this.nearbyLabel,
    required this.active,
    required this.onShowMap,
  });

  /// 周辺の記録を探す地点を返す
  final LatLng Function() nearbyCenter;

  /// 周辺の記録を探す地点の呼び名を返す
  final String Function() nearbyLabel;

  /// このタブを表示しているか。開いたときに地点が変わっていれば読み直す
  final bool active;

  /// 地図のタブを開く
  final VoidCallback onShowMap;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  TimelineScope _scope = TimelineScope.mine;
  Stream<List<MemoryLog>>? _mine;
  Future<List<TimelineEntry>>? _nearby;
  LatLng? _nearbyLoadedAt;
  String _nearbyLabel = '';

  /// みんなの口コミを、全国の新着で見るか（false なら基準の地点の周辺）
  bool _nationwide = false;

  /// 読み直す地点の移動量（m）。周辺の記録は約 5 km 四方の区画で探すので、小さな移動では結果が変わらない
  static const int _reloadDistanceMeters = 800;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mine ??= Services.of(context).checkins.watchLogs();
  }

  void _reloadMine() {
    setState(() => _mine = Services.of(context).checkins.watchLogs());
  }

  void _loadNearby() {
    final LatLng center = widget.nearbyCenter();
    setState(() {
      _nearbyLoadedAt = center;
      _nearbyLabel = widget.nearbyLabel();
      _nearby = Services.of(context).checkins.nearbyTimeline(
        lat: center.latitude,
        lng: center.longitude,
        nationwide: _nationwide,
      );
    });
  }

  void _setNationwide(bool on) {
    if (on == _nationwide) {
      return;
    }
    _nationwide = on;
    _loadNearby();
  }

  @override
  void didUpdateWidget(TimelineScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final LatLng? loadedAt = _nearbyLoadedAt;
    // 全国の新着は地点に関係ないので、地図を動かしても読み直さない
    if (!widget.active ||
        oldWidget.active ||
        _scope != TimelineScope.nearby ||
        _nationwide ||
        loadedAt == null) {
      return;
    }
    final LatLng center = widget.nearbyCenter();
    final int moved = distanceMeters(
      loadedAt.latitude,
      loadedAt.longitude,
      center.latitude,
      center.longitude,
    );
    // 場所の名前を読む回数を消費するので、地点が変わったときだけ読み直す
    if (moved > _reloadDistanceMeters) {
      _loadNearby();
    } else {
      setState(() => _nearbyLabel = widget.nearbyLabel());
    }
  }

  void _setScope(TimelineScope scope) {
    setState(() => _scope = scope);
    if (scope == TimelineScope.nearby) {
      _loadNearby();
    }
  }

  /// 広い画面で、切り替えボタンと補足を置く左の列の幅
  static const double _sideWidth = 340;
  static const double _columnGap = 32;
  static const double _bodyMaxWidth = 600;

  Widget _scopeButton() => SegmentedButton<TimelineScope>(
    showSelectedIcon: false,
    // 列の幅いっぱいに広げ、3つの項目を同じ幅で並べる
    expandedInsets: EdgeInsets.zero,
    // アイコンだけでは分かりにくいので文字にする。3つ並べても1行に収まるよう、アイコンは付けない
    segments: <ButtonSegment<TimelineScope>>[
      ButtonSegment<TimelineScope>(
        value: TimelineScope.mine,
        label: Text(l10n.myLog),
      ),
      ButtonSegment<TimelineScope>(
        value: TimelineScope.favorites,
        label: Text(l10n.favorites),
      ),
      ButtonSegment<TimelineScope>(
        value: TimelineScope.nearby,
        label: Text(l10n.nearby),
      ),
    ],
    selected: <TimelineScope>{_scope},
    onSelectionChanged: (Set<TimelineScope> s) => _setScope(s.first),
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final bool wide =
              box.maxWidth >= _sideWidth + _columnGap + 440 + _columnGap * 2;
          // 一覧の種類ごとに、補足（平均の評価や基準の地点）と一覧を受け取り、画面の幅に合わせて並べる
          Widget frame({Widget? side, required Widget body}) {
            if (wide) {
              final double bodyWidth =
                  (box.maxWidth - _sideWidth - _columnGap * 3).clamp(
                    0,
                    _bodyMaxWidth,
                  );
              final double total =
                  _sideWidth + _columnGap - 16 + bodyWidth + 32;
              return Column(
                children: <Widget>[
                  // 見出しは左の列の左端にそろえる
                  SizedBox(
                    width: total,
                    child: ScreenHeader(title: l10n.tabTimeline),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SizedBox(
                          width: _sideWidth,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(top: 4, bottom: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                _scopeButton(),
                                if (side != null) ...<Widget>[
                                  const SizedBox(height: 20),
                                  side,
                                ],
                              ],
                            ),
                          ),
                        ),
                        // 一覧は左右に 16 の余白を持つので、その分を列の間から引く
                        const SizedBox(width: _columnGap - 16),
                        SizedBox(width: bodyWidth + 32, child: body),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _bodyMaxWidth + 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    ScreenHeader(title: l10n.tabTimeline),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: _scopeButton(),
                    ),
                    if (side != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: side,
                      ),
                    Expanded(child: body),
                  ],
                ),
              ),
            );
          }

          return switch (_scope) {
            TimelineScope.mine => _MineList(
              stream: _mine!,
              onRetry: _reloadMine,
              frame: frame,
              boxedSummary: wide,
            ),
            TimelineScope.favorites => frame(
              body: FavoritesList(
                bottomPadding: MediaQuery.paddingOf(context).bottom + 16,
              ),
            ),
            TimelineScope.nearby => frame(
              side: _EveryoneArea(
                nationwide: _nationwide,
                onChanged: _setNationwide,
                base: _NearbyBase(label: _nearbyLabel, onTap: widget.onShowMap),
              ),
              body: _NearbyList(future: _nearby, onRetry: _loadNearby),
            ),
          };
        },
      ),
    );
  }
}

/// 一覧の補足と一覧を、画面の幅に合わせて並べる関数
typedef TimelineFrame = Widget Function({Widget? side, required Widget body});

/// みんなの口コミを、周辺で見るか全国の新着で見るかの切り替え。周辺のときは基準の地点も見せる
class _EveryoneArea extends StatelessWidget {
  const _EveryoneArea({
    required this.nationwide,
    required this.onChanged,
    required this.base,
  });

  final bool nationwide;
  final ValueChanged<bool> onChanged;
  final Widget base;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 8,
          children: <Widget>[
            ChoiceChip(
              avatar: const Icon(Icons.near_me_outlined, size: 18),
              label: Text(l10n.timelineAreaNearby),
              selected: !nationwide,
              showCheckmark: false,
              onSelected: (_) => onChanged(false),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.public, size: 18),
              label: Text(l10n.timelineAreaNationwide),
              selected: nationwide,
              showCheckmark: false,
              onSelected: (_) => onChanged(true),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (nationwide)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.timelineNationwideNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          base,
      ],
    );
  }
}

/// 周辺の記録の基準の地点。押すと地図を開いて地点を変えられる
class _NearbyBase extends StatelessWidget {
  const _NearbyBase({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.place_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _MineList extends StatefulWidget {
  const _MineList({
    required this.stream,
    required this.onRetry,
    required this.frame,
    required this.boxedSummary,
  });

  final Stream<List<MemoryLog>> stream;
  final TimelineFrame frame;

  /// 平均の評価と称号をカードに入れるか。広い画面の左の列では、一覧と区切るためにカードに入れる
  final bool boxedSummary;

  /// 読み込みに失敗したときに、一覧を読み直す
  final VoidCallback onRetry;

  @override
  State<_MineList> createState() => _MineListState();
}

class _MineListState extends State<_MineList> {
  // 公開状態を変えるたびに一覧を読み直すと、場所の名前を読む回数が増えるため、手元で上書きする
  final Map<String, bool> _publicOverrides = <String, bool>{};
  final Set<String> _changing = <String>{};

  // 直した記録。公開状態と同じく、一覧を読み直さずに手元で置き換える
  final Map<String, MemoryLog> _edited = <String, MemoryLog>{};

  Future<void> _edit(MemoryLog log) async {
    final MemoryLog? edited = await showEditLogSheet(context, log);
    if (edited != null && mounted) {
      setState(() => _edited[log.id] = edited);
    }
  }

  Future<void> _togglePublic(MemoryLog log, bool next) async {
    final CheckinRepository checkins = Services.of(context).checkins;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // 失敗したら、この操作の前に確定していた状態へ戻す。消すと読み込んだ時点の状態に戻ってしまう
    final bool before = _publicOverrides[log.id] ?? log.isPublic;
    setState(() {
      _publicOverrides[log.id] = next;
      _changing.add(log.id);
    });
    try {
      await checkins.setLogPublic(log, isPublic: next);
    } catch (error) {
      if (mounted) {
        setState(() => _publicOverrides[log.id] = before);
      }
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) {
        setState(() => _changing.remove(log.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MemoryLog>>(
      stream: widget.stream,
      builder: (BuildContext context, AsyncSnapshot<List<MemoryLog>> snap) {
        if (snap.hasError) {
          return widget.frame(
            body: StateView(
              icon: Icons.cloud_off_outlined,
              title: describeError(snap.error!),
              primary: StateViewAction(
                l10n.retry,
                widget.onRetry,
                icon: Icons.refresh,
              ),
            ),
          );
        }
        final List<MemoryLog>? logs = snap.data;
        if (logs == null) {
          return widget.frame(
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (logs.isEmpty) {
          return widget.frame(
            body: StateView(
              icon: Icons.where_to_vote_outlined,
              title: l10n.noLogsYet,
            ),
          );
        }
        final List<MemoryLog> sorted =
            <MemoryLog>[for (final MemoryLog l in logs) _edited[l.id] ?? l]
              ..sort(
                (MemoryLog a, MemoryLog b) =>
                    b.createdAt.compareTo(a.createdAt),
              );
        final Widget summary = _MineSummary(logs: sorted);
        return widget.frame(
          side: widget.boxedSummary
              ? Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: summary,
                  ),
                )
              : summary,
          body: _TimelineListView(
            dates: <DateTime>[for (final MemoryLog l in sorted) l.createdAt],
            itemBuilder: (BuildContext context, int i) {
              final MemoryLog log = sorted[i];
              final bool isPublic = _publicOverrides[log.id] ?? log.isPublic;
              return _EntryCard(
                onTap: () => showEntryDetail(
                  context,
                  EntryDetail(
                    placeId: log.placeId,
                    placeName: log.placeName,
                    stars: log.stars,
                    comment: log.comment,
                    date: log.createdAt,
                    order: log.order,
                    mine: true,
                    photoId: log.photoId,
                    genre: log.genre,
                    reactions: _MineReactions.of(log),
                  ),
                  actions: <Widget>[
                    Builder(
                      builder: (BuildContext sheet) => FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(sheet).pop();
                          _edit(log.copyWith(isPublic: isPublic));
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(l10n.editLog),
                      ),
                    ),
                  ],
                ),
                stars: log.stars,
                placeName: log.placeName,
                comment: log.comment,
                order: log.order,
                photoId: log.photoId,
                footer: _MineReactions.of(log),
                trailing: _changing.contains(log.id)
                    ? const SizedBox.square(
                        dimension: 48,
                        child: Center(
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : IconButton(
                        tooltip: isPublic
                            ? l10n.publicToggleToPrivate
                            : l10n.publicToggleToPublic,
                        isSelected: isPublic,
                        selectedIcon: const Icon(Icons.public),
                        icon: const Icon(Icons.lock_outline),
                        onPressed: () => _togglePublic(log, !isPublic),
                      ),
                leadingBadge: log.isPending
                    ? Tooltip(
                        message: l10n.unsent,
                        child: Icon(Icons.cloud_upload_outlined, size: 16),
                      )
                    : null,
              );
            },
          ),
        );
      },
    );
  }
}

class _MineSummary extends StatelessWidget {
  const _MineSummary({required this.logs});

  final List<MemoryLog> logs;

  @override
  Widget build(BuildContext context) {
    final List<String> badges = badgesForLogs(logs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        RatingSummary(
          stars:
              logs.fold<int>(0, (int n, MemoryLog l) => n + l.stars) /
              logs.length,
          count: logs.length,
        ),
        if (badges.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String b in badges)
                Chip(
                  avatar: const Icon(Icons.military_tech, size: 18),
                  label: Text(b),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 自分の記録に付いた反応の数。まだ誰も反応していなければ出さない
abstract final class _MineReactions {
  static Widget? of(MemoryLog log) {
    if (log.wantCount == 0 && log.helpfulCount == 0) {
      return null;
    }
    return ReactionBar(
      entry: TimelineEntry(
        id: log.id,
        author: '',
        mine: true,
        placeId: log.placeId,
        placeName: log.placeName,
        verdict: log.verdict,
        createdAt: log.createdAt,
        wantCount: log.wantCount,
        helpfulCount: log.helpfulCount,
      ),
    );
  }
}

class _NearbyList extends StatefulWidget {
  const _NearbyList({required this.future, required this.onRetry});

  final Future<List<TimelineEntry>>? future;
  final VoidCallback onRetry;

  @override
  State<_NearbyList> createState() => _NearbyListState();
}

class _NearbyListState extends State<_NearbyList> {
  final Set<String> _reported = <String>{};

  /// 反応を変えた記録。一覧を読み直すまで、手元の状態で見せる
  final Map<String, TimelineEntry> _reacted = <String, TimelineEntry>{};

  void _onReacted(TimelineEntry e) => setState(() => _reacted[e.id] = e);

  /// お気に入りに入れるための場所。お気に入りは place ID で覚え、名前と位置は一覧を開くときにサーバーが読む
  static Place _placeOf(TimelineEntry e) =>
      Place(id: e.placeId, name: e.placeName, lat: 0, lng: 0);

  Future<void> _report(TimelineEntry entry) async {
    final CheckinRepository checkins = Services.of(context).checkins;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ReportChoice? choice = await showReportSheet(context);
    if (choice == null || !mounted) {
      return;
    }
    setState(() => _reported.add(entry.id));
    try {
      await checkins.reportEntry(
        entry.id,
        reason: choice.reason,
        note: choice.note,
      );
      messenger.showSnackBar(SnackBar(content: Text(l10n.reported)));
    } catch (error) {
      if (mounted) {
        setState(() => _reported.remove(entry.id));
      }
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TimelineEntry>>(
      future: widget.future,
      builder: (BuildContext context, AsyncSnapshot<List<TimelineEntry>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return StateView(
            icon: Icons.cloud_off_outlined,
            title: describeError(snap.error!),
            primary: StateViewAction(
              l10n.retry,
              widget.onRetry,
              icon: Icons.refresh,
            ),
          );
        }
        final List<TimelineEntry> entries =
            <TimelineEntry>[
              for (final TimelineEntry e in snap.data!)
                if (!_reported.contains(e.id)) _reacted[e.id] ?? e,
            ]..sort(
              (TimelineEntry a, TimelineEntry b) =>
                  b.createdAt.compareTo(a.createdAt),
            );
        if (entries.isEmpty) {
          return StateView(
            icon: Icons.near_me_outlined,
            title: l10n.noNearbyLogs,
          );
        }
        final bool hasMock = entries.any((TimelineEntry e) => e.isMock);
        return _TimelineListView(
          dates: <DateTime>[for (final TimelineEntry e in entries) e.createdAt],
          header: hasMock
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                  child: const MockBanner(),
                )
              : null,
          itemBuilder: (BuildContext context, int index) {
            final TimelineEntry e = entries[index];
            return _EntryCard(
              onTap: () => showEntryDetail(
                context,
                EntryDetail(
                  placeId: e.placeId,
                  placeName: e.placeName,
                  stars: e.stars,
                  comment: e.comment,
                  date: e.createdAt,
                  order: e.order,
                  authorName: e.mine ? null : e.authorName,
                  authorIcon: e.authorIcon,
                  mine: e.mine,
                  photoId: e.photoId,
                  genre: e.genre,
                  reactions: ReactionBar(entry: e, onChanged: _onReacted),
                ),
                actions: <Widget>[
                  if (!e.mine)
                    Builder(
                      builder: (BuildContext sheet) => TextButton.icon(
                        onPressed: () {
                          Navigator.of(sheet).pop();
                          _report(e);
                        },
                        icon: const Icon(Icons.flag_outlined),
                        label: Text(l10n.reportLog),
                      ),
                    ),
                ],
              ),
              stars: e.stars,
              placeName: e.placeName,
              comment: e.comment,
              order: e.order,
              photoId: e.photoId,
              // 自分の口コミは反応できないので、反応があるときだけ数を見せる
              footer: e.mine && e.wantCount == 0 && e.helpfulCount == 0
                  ? null
                  : ReactionBar(
                      key: ValueKey<String>('reactions-${e.id}'),
                      entry: e,
                      onChanged: _onReacted,
                    ),
              author: e.mine ? null : e,
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // ほかの人が行った場所も、お気に入りに入れて後で行ける
                  // 架空の投稿（端末だけで動くとき）の場所は、本物の場所ではないので入れない
                  if (!e.isMock && !Place.isMockId(e.placeId))
                    FavoriteButton(place: _placeOf(e), compact: true),
                  if (!e.mine)
                    IconButton(
                      tooltip: l10n.reportLog,
                      icon: const Icon(Icons.flag_outlined),
                      onPressed: () => _report(e),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// 投稿者のアイコンとニックネーム。プロフィールを保存していない投稿者は人の形だけを示す
class _Author extends StatelessWidget {
  const _Author({required this.entry, required this.style});

  final TimelineEntry entry;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (entry.authorName.isEmpty) {
      return Icon(
        Icons.person_outline,
        size: 16,
        color: theme.colorScheme.onSurfaceVariant,
        semanticLabel: l10n.author,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ProfileAvatar(icon: ProfileIcon.of(entry.authorIcon), size: 22),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            entry.authorName,
            style: style?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// タイムラインの1件
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.stars,
    required this.placeName,
    required this.comment,
    required this.order,
    this.author,
    this.trailing,
    this.leadingBadge,
    this.onTap,
    this.photoId,
    this.footer,
  });

  /// 記録に付けた写真の ID
  final String? photoId;

  /// カードの下に置く反応のボタン
  final Widget? footer;

  /// 押すと詳細を開く
  final VoidCallback? onTap;

  /// ★の数（1〜5）
  final int stars;
  final String placeName;
  final String comment;
  final int? order;

  /// 他の人の記録の投稿者。自分の記録では null
  final TimelineEntry? author;
  final Widget? trailing;
  final Widget? leadingBadge;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextStyle? meta = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final TimelineEntry? author = this.author;
    final int? order = this.order;
    final Widget? trailing = this.trailing;
    final Widget? leadingBadge = this.leadingBadge;
    final Widget? footer = this.footer;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Tooltip(
                          message: starsLabel(stars),
                          child: StarRating(value: stars.toDouble()),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          placeName.isEmpty
                              ? l10n.placeNameUnavailable
                              : placeName,
                          style: placeName.isEmpty
                              ? AppTheme.placeName(
                                  16,
                                ).copyWith(color: scheme.onSurfaceVariant)
                              : AppTheme.placeName(16),
                        ),
                        if (photoId case final String id) ...<Widget>[
                          const SizedBox(height: 8),
                          LogPhoto(photoId: id, height: 160),
                        ],
                        if (comment.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 4),
                          // 長いひとことは詳細で読む
                          Text(
                            comment,
                            style: theme.textTheme.bodyMedium,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            ?leadingBadge,
                            if (author != null)
                              _Author(entry: author, style: meta),
                            if (order != null)
                              Text(l10n.visitorOrderShort(order), style: meta),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
              // 反応のボタンは右の操作の列の下まで広げ、横に並べる
              if (footer != null)
                Padding(padding: const EdgeInsets.only(top: 6), child: footer),
            ],
          ),
        ),
      ),
    );
  }
}

/// 記録を新しい順に1列で並べ、日付ごとの見出しで区切る。各記録の左に時刻を置き、
/// 同じ日の記録を縦の線でつないで、上から下へ時間が戻ることを示す
class _TimelineListView extends StatelessWidget {
  const _TimelineListView({
    required this.dates,
    required this.itemBuilder,
    this.header,
  });

  /// 各記録の日時。新しい順に並べておく
  final List<DateTime> dates;
  final IndexedWidgetBuilder itemBuilder;

  /// 一覧の先頭に置くもの
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    // 見出しと記録を1つの並びにする。見出しは int ではなく日付の文字列で表す
    final List<Object> rows = <Object>[];
    DateTime? day;
    for (int i = 0; i < dates.length; i++) {
      final DateTime local = dates[i].toLocal();
      final DateTime d = DateTime(local.year, local.month, local.day);
      if (d != day) {
        day = d;
        rows.add(timelineDayLabel(d, now));
      }
      rows.add(i);
    }
    final Widget? header = this.header;
    final int offset = header == null ? 0 : 1;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      // 最後に場所の名前の出典を置く
      itemCount: rows.length + offset + 1,
      itemBuilder: (BuildContext context, int i) {
        if (i == rows.length + offset) {
          return const GoogleMapsAttribution();
        }
        if (header != null && i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: header,
          );
        }
        final Object row = rows[i - offset];
        if (row is String) {
          return _DayHeader(label: row, first: i == offset);
        }
        final int index = row as int;
        final bool firstOfDay = rows[i - offset - 1] is String;
        final bool lastOfDay =
            i - offset + 1 >= rows.length || rows[i - offset + 1] is String;
        return _TimelineRow(
          time: dates[index].toLocal(),
          firstOfDay: firstOfDay,
          lastOfDay: lastOfDay,
          child: itemBuilder(context, index),
        );
      },
    );
  }
}

/// 日付の見出し。今日と昨日は日付の前に添える
String timelineDayLabel(DateTime day, DateTime now) {
  final DateTime today = DateTime(now.year, now.month, now.day);
  final String date = day.year == now.year
      ? l10n.timelineDate(day.month, day.day, '${day.weekday}')
      : l10n.timelineDateWithYear(
          day.year,
          day.month,
          day.day,
          '${day.weekday}',
        );
  if (day == today) {
    return '${l10n.timelineToday}　$date';
  }
  if (day == today.subtract(const Duration(days: 1))) {
    return '${l10n.timelineYesterday}　$date';
  }
  return date;
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, required this.first});

  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(_TimelineRow.gutter, first ? 4 : 16, 0, 8),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 時刻、縦の線と点、記録のカードを横に並べた1行
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.time,
    required this.firstOfDay,
    required this.lastOfDay,
    required this.child,
  });

  static const double _timeWidth = 48;
  static const double _lineWidth = 16;

  /// カードの左端までの幅。日付の見出しもここにそろえる
  static const double gutter = _timeWidth + _lineWidth + 12;

  /// 点の中心の高さ。カードの1行目（★）の高さにそろえる
  static const double _dotY = 22;

  final DateTime time;
  final bool firstOfDay;
  final bool lastOfDay;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String minute = time.minute.toString().padLeft(2, '0');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: _timeWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: _dotY - 9, right: 6),
              child: Text(
                '${time.hour}:$minute',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          SizedBox(
            width: _lineWidth,
            child: CustomPaint(
              painter: _LinePainter(
                line: scheme.outlineVariant,
                dot: scheme.primary,
                dotY: _dotY,
                fromTop: !firstOfDay,
                toBottom: !lastOfDay,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: lastOfDay ? 0 : 12),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter({
    required this.line,
    required this.dot,
    required this.dotY,
    required this.fromTop,
    required this.toBottom,
  });

  final Color line;
  final Color dot;
  final double dotY;

  /// 前の記録から点までの線を描くか
  final bool fromTop;

  /// 点から次の記録までの線を描くか
  final bool toBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final double x = size.width / 2;
    final Paint stroke = Paint()
      ..color = line
      ..strokeWidth = 2;
    if (fromTop) {
      canvas.drawLine(Offset(x, 0), Offset(x, dotY), stroke);
    }
    if (toBottom) {
      canvas.drawLine(Offset(x, dotY), Offset(x, size.height), stroke);
    }
    canvas.drawCircle(Offset(x, dotY), 6, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.line != line ||
      old.dot != dot ||
      old.fromTop != fromTop ||
      old.toBottom != toBottom;
}
