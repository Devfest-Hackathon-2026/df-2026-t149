import '../../core/widgets/google_maps_notice.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/notifications.dart';

import '../../core/geo.dart';
import '../../core/location/location_service.dart';
import '../../core/location/stay_detector.dart';
import '../../core/location/visit_recorder.dart';
import '../../core/models/memory_log.dart';
import '../../core/models/place.dart';
import '../../core/layout.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/widgets/mock_banner.dart';
import '../../core/widgets/screen_header.dart';
import '../../core/widgets/state_view.dart';
import '../../core/widgets/place_labels.dart';
import '../../core/widgets/stamp_press.dart';
import '../../core/widgets/star_rating.dart';
import '../achievements/stamp_book.dart';
import '../place/place_detail_screen.dart';
import '../timeline/entry_detail_sheet.dart';
import 'checkin_screen.dart';
import 'checkin_tab_controller.dart';
import '../../core/strings.dart';

/// チェックインのタブ。上に「いまここ」（いちばん近い場所の、まだ押していないスタンプ）、
/// 下に「今日の旅」（今日押したスタンプと押し忘れかもしれない滞在）を置く。場所を探すのは地図のタブで行う
class CheckinTabScreen extends StatefulWidget {
  const CheckinTabScreen({
    super.key,
    required this.controller,
    required this.onShowMap,
    this.showTitle = true,
  });

  /// false なら見出しを出さず、現在地を読み直すボタンだけを置く
  final bool showTitle;

  final CheckinTabController controller;
  final VoidCallback onShowMap;

  @override
  State<CheckinTabScreen> createState() => _CheckinTabScreenState();
}

class _CheckinTabScreenState extends State<CheckinTabScreen> {
  Stream<List<MemoryLog>>? _logs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 場所の名前はほかの画面で読んだものを使い、Places API の上限を使わない
    _logs ??= Services.of(context).checkins.watchLogs(withNames: false);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<MemoryLog>>(
    stream: _logs,
    builder: (BuildContext context, AsyncSnapshot<List<MemoryLog>> snap) {
      final DateTime now = DateTime.now();
      return _CheckinTabBody(
        controller: widget.controller,
        onShowMap: widget.onShowMap,
        showTitle: widget.showTitle,
        today: <MemoryLog>[
          for (final MemoryLog l in snap.data ?? const <MemoryLog>[])
            if (_sameDay(l.createdAt, now)) l,
        ],
      );
    },
  );
}

class _CheckinTabBody extends StatelessWidget {
  const _CheckinTabBody({
    required this.controller,
    required this.onShowMap,
    required this.showTitle,
    required this.today,
  });

  final bool showTitle;
  final CheckinTabController controller;
  final VoidCallback onShowMap;

  /// 今日の記録（新しい順とは限らない）
  final List<MemoryLog> today;

  void _checkIn(
    BuildContext context,
    Place place, {
    required double lat,
    required double lng,
    Visit? visit,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) =>
            CheckinScreen(place: place, lat: lat, lng: lng, visit: visit),
      ),
    );
  }

  Widget _refreshButton() => IconButton(
    onPressed: controller.refresh,
    tooltip: l10n.reloadLocation,
    icon: const Icon(Icons.my_location),
  );

  void _checkInNearby(BuildContext context, Place place) {
    if (controller.state case NearbyLoaded(:final GeoSample position)) {
      _checkIn(context, place, lat: position.lat, lng: position.lng);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services services = Services.of(context);
    final double bottom = MediaQuery.paddingOf(context).bottom + 16;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        controller,
        services.visits,
        services.checkins.pendingCount,
      ]),
      builder: (BuildContext context, Widget? _) {
        final int pending = services.checkins.pendingCount.value;
        final Widget header = SafeArea(
          bottom: false,
          child: showTitle
              ? ScreenHeader(title: l10n.tabCheckin, trailing: _refreshButton())
              : Align(
                  alignment: Alignment.centerRight,
                  child: _refreshButton(),
                ),
        );
        final List<Widget> here = <Widget>[
          if (pending > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.cloud_upload_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(l10n.unsentCount(pending)),
                ],
              ),
            ),
          _Nearby(
            controller: controller,
            today: today,
            onCheckIn: (Place place) => _checkInNearby(context, place),
            onShowMap: onShowMap,
          ),
        ];
        final List<Widget> earlier = <Widget>[
          _TodayJourney(
            today: today,
            controller: controller,
            onCheckIn: (Place place, Visit visit) => _checkIn(
              context,
              place,
              lat: visit.lat,
              lng: visit.lng,
              visit: visit,
            ),
          ),
          if (services.visits.canTrack) const _RecordingSwitch(),
          // いまここと今日の旅の場所の名前の出典
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: GoogleMapsAttribution(),
          ),
        ];
        // 広い画面では、今いる場所と、行ったかもしれない場所を左右に並べる
        final bool twoColumns =
            WindowSize.of(context) == WindowSize.expanded &&
            (services.visits.visits.isNotEmpty || services.visits.canTrack);
        if (twoColumns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              header,
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.only(bottom: bottom),
                        children: here,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.only(top: 8, bottom: bottom),
                        children: earlier,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: EdgeInsets.only(bottom: bottom),
              children: <Widget>[header, ...here, ...earlier],
            ),
          ),
        );
      },
    );
  }
}

class _Nearby extends StatelessWidget {
  const _Nearby({
    required this.controller,
    required this.onCheckIn,
    required this.onShowMap,
    required this.today,
  });

  final List<MemoryLog> today;
  final CheckinTabController controller;
  final ValueChanged<Place> onCheckIn;
  final VoidCallback onShowMap;

  @override
  Widget build(BuildContext context) => switch (controller.state) {
    NearbyIdle() => const SizedBox.shrink(),
    NearbyLocating() => Padding(
      padding: EdgeInsets.all(20),
      child: LoadingLabel(l10n.checkingLocation),
    ),
    NearbySearching() => Padding(
      padding: EdgeInsets.all(20),
      child: LoadingLabel(l10n.searchingSpots),
    ),
    NearbyNoAccess(:final LocationAccess access) => _noAccess(context, access),
    NearbyNoFix() => StateView(
      icon: Icons.location_searching,
      title: l10n.locationCheckFailed,
      primary: StateViewAction(
        l10n.retry,
        controller.refresh,
        icon: Icons.refresh,
      ),
      secondary: StateViewAction(
        l10n.findOnMap,
        onShowMap,
        icon: Icons.map_outlined,
      ),
    ),
    NearbyEmpty() => StateView(
      icon: Icons.wrong_location_outlined,
      title: l10n.noSpotsNearby,
      primary: StateViewAction(
        l10n.searchAgainShort,
        controller.refresh,
        icon: Icons.refresh,
      ),
      secondary: StateViewAction(
        l10n.findOnMap,
        onShowMap,
        icon: Icons.map_outlined,
      ),
    ),
    NearbyOffline(:final GeoSample position) => StateView(
      icon: Icons.cloud_off_outlined,
      title: l10n.offline,
      message: l10n.offlineRecordHelp,
      primary: StateViewAction(
        l10n.recordHere,
        () => _saveCurrent(context, position),
        icon: Icons.add_location_alt_outlined,
      ),
      secondary: StateViewAction(
        l10n.searchAgainShort,
        controller.refresh,
        icon: Icons.refresh,
      ),
    ),
    NearbyLimited() => StateView(
      icon: Icons.hourglass_bottom,
      title: l10n.spotLimitReached,
      message: l10n.spotLimitHelp,
      primary: StateViewAction(
        l10n.findOnMap,
        onShowMap,
        icon: Icons.map_outlined,
      ),
    ),
    NearbyFailed(:final String message) => StateView(
      icon: Icons.error_outline,
      title: message,
      primary: StateViewAction(
        l10n.retry,
        controller.refresh,
        icon: Icons.refresh,
      ),
    ),
    final NearbyLoaded loaded => _NearbyLoadedView(
      state: loaded,
      stampedToday: <String, MemoryLog>{
        for (final MemoryLog l in today) l.placeId: l,
      }[loaded.selectedId],
      onSelect: controller.select,
      onCheckIn: onCheckIn,
      onShowMap: onShowMap,
    ),
  };

  void _saveCurrent(BuildContext context, GeoSample position) {
    Services.of(context).visits.saveCurrent(position);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.recordedHere)));
  }

  Widget _noAccess(BuildContext context, LocationAccess access) {
    final LocationService location = Services.of(context).location;
    return StateView(
      icon: Icons.location_disabled,
      title: access == LocationAccess.serviceOff
          ? l10n.locationServiceOff
          : l10n.locationDenied,
      primary: access == LocationAccess.denied
          ? StateViewAction(
              l10n.allowLocation,
              controller.refresh,
              icon: Icons.location_on_outlined,
            )
          : StateViewAction(
              l10n.openSettings,
              () => location.openSettings(access),
              icon: Icons.settings_outlined,
            ),
      secondary: StateViewAction(
        l10n.findOnMap,
        onShowMap,
        icon: Icons.map_outlined,
      ),
    );
  }
}

/// 「いまここ」：いちばん近い場所を1件だけ大きく出し、まだ押していないスタンプを押すとチェックインする。
/// ほかの候補は「ちがう場所？」から選び直す
class _NearbyLoadedView extends StatelessWidget {
  const _NearbyLoadedView({
    required this.state,
    required this.stampedToday,
    required this.onSelect,
    required this.onCheckIn,
    required this.onShowMap,
  });

  final NearbyLoaded state;

  /// 選んだ場所で今日押したスタンプ。まだ押していなければ null
  final MemoryLog? stampedToday;
  final ValueChanged<String> onSelect;
  final ValueChanged<Place> onCheckIn;
  final VoidCallback onShowMap;

  int _distance(Place p) =>
      distanceMeters(state.position.lat, state.position.lng, p.lat, p.lng);

  void _openDetail(BuildContext context, Place place) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => PlaceDetailScreen(
            place: place,
            distanceMeters: _distance(place),
            isMock: state.isMock,
          ),
        ),
      );

  Future<void> _chooseOther(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                l10n.whereAreYou,
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
            ),
            _SpotRadioList(
              places: state.places,
              selectedId: state.selectedId,
              distanceOf: _distance,
              onSelect: (String id) {
                onSelect(id);
                Navigator.of(sheet).pop();
              },
              // シートの context で開く。開いた画面は、広さの切り替えなどで作り直されることがある
              onOpenDetail: (Place p) => _openDetail(sheet, p),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Place selected = state.selected;
    final String? type = placeTypeLabel(selected.primaryType);
    final String distance = state.isOffline
        ? l10n.distanceOffline(_distance(selected))
        : '${_distance(selected)} m';
    final TextStyle? meta = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (state.isMock) const MockBanner(),
        const SizedBox(height: 12),
        Text(l10n.hereQuestion, textAlign: TextAlign.center, style: meta),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            selected.name,
            textAlign: TextAlign.center,
            style: AppTheme.placeName(26),
          ),
        ),
        Text(
          type == null ? distance : l10n.typeAndDistance(type, distance),
          textAlign: TextAlign.center,
          style: meta,
        ),
        const SizedBox(height: 16),
        Center(
          child: switch (stampedToday) {
            // 今日もう押した場所は、押したスタンプを見せ、同じ場所で重ねて押させない
            final MemoryLog log => Column(
              key: const ValueKey<String>('here-stamped'),
              children: <Widget>[
                StampBookStamp(
                  log: log,
                  size: WindowSize.of(context).isCompact ? 180 : 220,
                ),
                const SizedBox(height: 8),
                Text(l10n.alreadyStampedToday, style: meta),
              ],
            ),
            null => StampPressButton(
              key: const ValueKey<String>('here-stamp'),
              design: stampDesignOfPlace(selected),
              semanticLabel: l10n.pressToStampAt(selected.name),
              size: WindowSize.of(context).isCompact ? 200 : 240,
              onPressed: () => onCheckIn(selected),
            ),
          },
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (state.places.length > 1)
                OutlinedButton.icon(
                  onPressed: () => _chooseOther(context),
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(l10n.otherPlaces(state.places.length - 1)),
                ),
              TextButton.icon(
                onPressed: () => _openDetail(context, selected),
                icon: const Icon(Icons.info_outline),
                label: Text(l10n.details),
              ),
              TextButton.icon(
                onPressed: onShowMap,
                icon: const Icon(Icons.map_outlined),
                label: Text(l10n.findAroundOnMap),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// スポットの候補。別のスポットにいるときは、ここから選び直す
class _SpotRadioList extends StatelessWidget {
  const _SpotRadioList({
    required this.places,
    required this.selectedId,
    required this.distanceOf,
    required this.onSelect,
    required this.onOpenDetail,
  });

  final List<Place> places;

  /// 場所の詳細を開く
  final ValueChanged<Place> onOpenDetail;
  final String? selectedId;
  final int Function(Place) distanceOf;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => RadioGroup<String>(
    groupValue: selectedId,
    onChanged: (String? id) {
      if (id != null) {
        onSelect(id);
      }
    },
    child: Column(
      children: <Widget>[
        for (final Place p in places)
          RadioListTile<String>(
            value: p.id,
            title: Text(p.name),
            subtitle: Text('${distanceOf(p)} m'),
            secondary: IconButton(
              tooltip: l10n.placeDetailsTooltip(p.name),
              icon: const Icon(Icons.info_outline),
              onPressed: () => onOpenDetail(p),
            ),
          ),
      ],
    ),
  );
}

/// 「今日の旅」の1件。押したスタンプか、押し忘れかもしれない滞在
sealed class _JourneyItem {
  const _JourneyItem(this.at);

  final DateTime at;
}

final class _StampItem extends _JourneyItem {
  _StampItem(this.log) : super(log.createdAt);

  final MemoryLog log;
}

final class _StayItem extends _JourneyItem {
  _StayItem(this.visit) : super(visit.startedAt);

  final Visit visit;
}

/// 「今日の旅」：今日押したスタンプと、押し忘れかもしれない滞在を、新しい順に1本の線でつなぐ
class _TodayJourney extends StatelessWidget {
  const _TodayJourney({
    required this.today,
    required this.controller,
    required this.onCheckIn,
  });

  final List<MemoryLog> today;
  final CheckinTabController controller;
  final void Function(Place place, Visit visit) onCheckIn;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final Services services = Services.of(context);
    final ThemeData theme = Theme.of(context);
    final DateTime now = DateTime.now();
    final List<_JourneyItem> items = <_JourneyItem>[
      for (final MemoryLog l in today) _StampItem(l),
      for (final Visit v in services.visits.visits) _StayItem(v),
    ]..sort((_JourneyItem a, _JourneyItem b) => b.at.compareTo(a.at));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(l10n.journeyTitle, style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.journeySummary(today.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Text(
                l10n.journeyEmpty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (int i = 0; i < items.length; i++)
            _JourneyRow(
              time: _timeLabel(items[i].at, now),
              last: i == items.length - 1,
              hollow: items[i] is _StayItem,
              color: switch (items[i]) {
                _StampItem(:final MemoryLog log) => stampDesignOf(log).ink,
                _StayItem() => theme.colorScheme.outline,
              },
              child: switch (items[i]) {
                _StampItem(:final MemoryLog log) => _StampRow(log: log),
                _StayItem(:final Visit visit) => _VisitCard(
                  visit: visit,
                  spots: controller.spotsOf(visit),
                  onResolve: () => controller.resolve(visit),
                  onCheckIn: (Place place) => onCheckIn(place, visit),
                  onSelect: (String id) => controller.selectForVisit(visit, id),
                ),
              },
            ),
        ],
      ),
    );
  }

  static String _timeLabel(DateTime d, DateTime now) {
    final String time = '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    return _sameDay(d, now) ? time : '${d.month}/${d.day}\n$time';
  }
}

/// 時刻・点・縦の線を左に置いた1行
class _JourneyRow extends StatelessWidget {
  const _JourneyRow({
    required this.time,
    required this.child,
    required this.color,
    this.last = false,
    this.hollow = false,
  });

  final String time;
  final Widget child;
  final Color color;
  final bool last;
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                time,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 20,
            child: Column(
              children: <Widget>[
                const SizedBox(height: 14),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hollow ? null : color,
                    border: Border.all(color: color, width: 2),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// 今日押したスタンプ。押すと記録の詳細を開く
class _StampRow extends StatelessWidget {
  const _StampRow({required this.log});

  final MemoryLog log;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = log.placeName.isNotEmpty
        ? log.placeName
        : Services.of(context).api.placeNames[log.placeId] ??
              stampDesignOf(log).label;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            StampBookStamp(log: log, size: 60),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(name, style: AppTheme.placeName(16)),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      StarRating(value: log.stars.toDouble(), size: 14),
                      if (log.photoId != null) ...<Widget>[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.photo_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                          semanticLabel: l10n.photoLabel,
                        ),
                      ],
                    ],
                  ),
                  if (log.comment.isNotEmpty)
                    Text(
                      log.comment,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({
    required this.visit,
    required this.spots,
    required this.onResolve,
    required this.onCheckIn,
    required this.onSelect,
  });

  final Visit visit;
  final VisitSpots spots;
  final VoidCallback onResolve;
  final ValueChanged<Place> onCheckIn;
  final ValueChanged<String> onSelect;

  int _distance(Place p) => distanceMeters(visit.lat, visit.lng, p.lat, p.lng);

  Future<void> _changeSpot(BuildContext context, VisitSpotsLoaded loaded) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (BuildContext sheet) => SafeArea(
          child: SingleChildScrollView(
            child: _SpotRadioList(
              places: loaded.places,
              selectedId: loaded.selectedId,
              distanceOf: _distance,
              onSelect: (String id) {
                onSelect(id);
                Navigator.of(sheet).pop();
              },
              // シートの context で開く。開いたカードは、チェックインした後に一覧から消えて使えなくなることがある
              onOpenDetail: (Place p) => Navigator.of(sheet).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) =>
                      PlaceDetailScreen(place: p, distanceMeters: _distance(p)),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> _decline(BuildContext context) {
    final VisitRecorder recorder = Services.of(context).visits;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(l10n.skipThisTime),
              onTap: () {
                recorder.skip(visit);
                Navigator.of(sheet).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_off_outlined),
              title: Text(l10n.neverSuggestPlace),
              onTap: () {
                recorder.neverSuggest(visit);
                Navigator.of(sheet).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final VisitSpots spots = this.spots;
    final Place? place = spots is VisitSpotsLoaded ? spots.selected : null;
    final int minutes = visit.endedAt.difference(visit.startedAt).inMinutes;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 押し忘れかもしれない滞在として見せる
            Text(
              minutes >= StayDetector.minDwell.inMinutes
                  ? l10n.journeyStay(minutes)
                  : l10n.journeyStayShort,
              style: theme.textTheme.titleSmall,
            ),
            Text(
              _period(visit),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            switch (spots) {
              VisitSpotsIdle() => Text(
                l10n.positionRecorded,
                style: theme.textTheme.bodyLarge,
              ),
              VisitSpotsLoading() => LoadingLabel(l10n.searchingSpotsShort),
              VisitSpotsOffline() => Text(
                l10n.spotsLoadFailed,
                style: theme.textTheme.bodyLarge,
              ),
              VisitSpotsLoaded(:final Place? selected) => Text(
                selected?.name ?? l10n.noSpotsNearby,
                style: selected == null
                    ? theme.textTheme.bodyLarge
                    : AppTheme.placeName(18),
              ),
            },
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: <Widget>[
                TextButton(
                  onPressed: () => _decline(context),
                  child: Text(l10n.skipCheckin),
                ),
                if (spots is VisitSpotsOffline || spots is VisitSpotsIdle)
                  TextButton(onPressed: onResolve, child: Text(l10n.findSpots)),
                if (spots is VisitSpotsLoaded && spots.places.length > 1)
                  TextButton(
                    onPressed: () => _changeSpot(context, spots),
                    child: Text(l10n.changePlace),
                  ),
                if (place != null)
                  FilledButton.tonalIcon(
                    onPressed: () => onCheckIn(place),
                    icon: const Icon(Icons.approval, size: 18),
                    label: Text(l10n.pressLater),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _period(Visit v) {
    String time(DateTime d) =>
        '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    final String start =
        '${v.startedAt.month}/${v.startedAt.day} ${time(v.startedAt)}';
    return v.endedAt.difference(v.startedAt) < StayDetector.minDwell
        ? start
        : l10n.timeRange(start, time(v.endedAt));
  }
}

/// 滞在した場所の記録のスイッチ
class _RecordingSwitch extends StatelessWidget {
  const _RecordingSwitch();

  Future<void> _toggle(BuildContext context, bool on) async {
    final VisitRecorder visits = Services.of(context).visits;
    if (!on) {
      await visits.disable();
      return;
    }
    final LocationService location = Services.of(context).location;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool notify = Services.of(context).settings.notificationsEnabled;
    final bool? agreed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: Text(l10n.recordStaysTitle),
        content: Text(l10n.recordStaysMessage(StayDetector.minDwell.inMinutes)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l10n.doNotRecord),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l10n.record),
          ),
        ],
      ),
    );
    if (agreed != true) {
      return;
    }
    final LocationAccess access = await visits.enable();
    // 滞在を見つけたときに知らせるため、通知の許可もここで聞く（設定で通知を切っていれば聞かない）
    if (access == LocationAccess.granted && notify) {
      unawaited(AppNotifications.requestPermission());
    }
    if (access == LocationAccess.backgroundNeeded) {
      // Android 11 以降は設定の画面でしか選べない。戻ると VisitRecorder.refresh が記録を始める
      await location.openSettings(access);
    } else if (access != LocationAccess.granted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.locationDenied),
          action: SnackBarAction(
            label: l10n.openSettings,
            onPressed: () => location.openSettings(access),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    secondary: const Icon(Icons.route_outlined),
    title: Text(l10n.recordStays),
    value: Services.of(context).visits.enabled,
    onChanged: (bool on) => _toggle(context, on),
  );
}
