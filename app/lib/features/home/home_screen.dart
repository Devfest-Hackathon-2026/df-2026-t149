import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/data/checkin_repository.dart';
import '../../core/geo.dart';
import '../../core/models/assistant_answer.dart';
import '../../core/models/place.dart';
import '../../core/data/favorites.dart';
import '../../core/layout.dart';
import '../../core/models/memory_log.dart';
import '../../core/notifications.dart';
import '../../core/services.dart';
import '../../core/widgets/floating_tab_bar.dart';
import '../achievements/achievements_screen.dart';
import '../assistant/assistant_controller.dart';
import '../checkin/checkin_screen.dart';
import '../checkin/checkin_tab_controller.dart';
import '../checkin/checkin_tab_screen.dart';
import '../place/place_detail_screen.dart';
import '../settings/settings_screen.dart';
import '../map/map_screen.dart';
import '../map/map_search_controller.dart';
import '../timeline/timeline_screen.dart';
import '../../core/strings.dart';

enum HomeTab {
  map,
  checkin,
  timeline,
  achievements;

  FloatingTabItem get item => switch (this) {
    map => FloatingTabItem(
      icon: Icons.map_outlined,
      selectedIcon: Icons.map,
      label: l10n.tabMap,
    ),
    checkin => FloatingTabItem(
      icon: Icons.where_to_vote_outlined,
      selectedIcon: Icons.where_to_vote,
      label: l10n.tabCheckin,
    ),
    timeline => FloatingTabItem(
      icon: Icons.forum_outlined,
      selectedIcon: Icons.forum,
      label: l10n.tabTimeline,
    ),
    achievements => FloatingTabItem(
      icon: Icons.emoji_events_outlined,
      selectedIcon: Icons.emoji_events,
      label: l10n.tabAchievements,
    ),
  };
}

/// アプリの土台。狭い画面は下のタブ、広い画面は左に浮かせた縦のタブで切り替える
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const Duration _syncInterval = Duration(minutes: 1);

  HomeTab _tab = HomeTab.map;
  final Set<HomeTab> _opened = <HomeTab>{HomeTab.map};
  MapSearchController? _search;
  FavoritesController? _favorites;
  CheckinTabController? _checkin;
  AssistantController? _assistant;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncTimer = Timer.periodic(_syncInterval, (Timer _) => _sync());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_search != null) {
      return;
    }
    final Services services = Services.of(context);
    final LatLng start = LatLng(
      services.config.initialLat,
      services.config.initialLng,
    );
    final MapSearchController search = MapSearchController(
      api: services.api,
      location: services.location,
      settings: services.settings,
      start: start,
    );
    _search = search;
    _favorites = services.favorites?..addListener(search.favoritesChanged);
    _assistant = AssistantController(api: services.api);
    // 測定できなくても、前回の地点の地図で下調べに使える
    unawaited(
      search.start().catchError((Object error) {
        debugPrint('現在地を測定できません: $error');
        return null;
      }),
    );
    _checkin = CheckinTabController(
      api: services.api,
      location: services.location,
      visits: services.visits,
      start: start,
      knownPlaces: () => switch (search.state) {
        SearchLoaded(:final List<Place> places, isMock: false) => places,
        _ => const <Place>[],
      },
    );
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Services.of(context).visits.refresh();
      _sync();
      // 起動の時の通信を増やさないよう、反応はアプリに戻ったときだけ数える
      _checkReactions(ScaffoldMessenger.of(context));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    if (_search case final MapSearchController search) {
      _favorites?.removeListener(search.favoritesChanged);
    }
    _search?.dispose();
    _checkin?.dispose();
    _assistant?.dispose();
    super.dispose();
  }

  void _select(HomeTab tab) {
    setState(() {
      _tab = tab;
      _opened.add(tab);
    });
    if (tab == HomeTab.checkin) {
      _checkin!.open();
      _sync();
    }
  }

  Future<void> _sync() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final SyncReport report = await Services.of(context).checkins.sync();
    final List<SentCheckin> sent = report.checkins;
    if (sent.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            sent.length == 1
                ? l10n.syncSentOne(sent.single.placeName, sent.single.order)
                : l10n.syncSentMany(sent.length),
          ),
        ),
      );
    }
    if (report.rejected > 0) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.syncRejected(report.rejected))),
      );
    }
  }

  bool _checkingReactions = false;
  DateTime? _reactionsCheckedAt;

  /// 何度もアプリを行き来しても、記録を読み直しすぎないよう、数える間を空ける
  static const Duration _reactionsInterval = Duration(minutes: 10);

  /// 自分の口コミに新しい反応（行ってみたい・参考になった）が付いていれば知らせる。
  /// アプリに戻ったときに数え、前に数えたときより増えた分を知らせる
  Future<void> _checkReactions(ScaffoldMessengerState messenger) async {
    final DateTime now = DateTime.now();
    final DateTime? last = _reactionsCheckedAt;
    if (_checkingReactions ||
        !mounted ||
        (last != null && now.difference(last) < _reactionsInterval)) {
      return;
    }
    _checkingReactions = true;
    _reactionsCheckedAt = now;
    final CheckinRepository checkins = Services.of(context).checkins;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (!AppNotifications.enabled(prefs)) {
        return;
      }
      // 名前はいらないので、Places API の上限を使わない
      final List<MemoryLog> logs = await checkins
          .watchLogs(withNames: false)
          .first;
      final int total = logs.fold<int>(
        0,
        (int n, MemoryLog l) => n + l.wantCount + l.helpfulCount,
      );
      final int added = await AppNotifications.takeNewReactions(prefs, total);
      if (added > 0 && mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.notifyReactionsBody(added)),
            action: SnackBarAction(
              label: l10n.notifyReactionsOpen,
              onPressed: () => _select(HomeTab.timeline),
            ),
          ),
        );
      }
    } catch (error) {
      // 反応の知らせは補助なので、数えられなくても何もしない
      debugPrint('反応を数えられません: $error');
    } finally {
      _checkingReactions = false;
    }
  }

  /// 地図で現在地のそばの場所の「押してスタンプ」を押したとき。チェックインのタブと同じ画面でスタンプを押す
  void _checkInHere(Place place) {
    final LatLng? here = _search!.userLocation;
    if (here == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => CheckinScreen(
          place: place,
          lat: here.latitude,
          lng: here.longitude,
        ),
      ),
    );
  }

  void _openPlace(Place place) {
    final MapSearchController search = _search!;
    final bool isMock = switch (search.state) {
      SearchLoaded(:final bool isMock) => isMock,
      _ => false,
    };
    _pushDetail(
      place,
      distanceMeters: search.distanceTo(place),
      isMock: isMock,
    );
  }

  // Geminiちゃんは地図の検索と別の地点を探すことがあるため、地図の検索の状態ではなく答えの中心とデータ元を使う
  void _openSuggestion(AssistantSuggestion suggestion, AssistantAnswer answer) {
    final Place place = suggestion.place;
    final AssistantCenter? center = answer.center;
    _pushDetail(
      place,
      distanceMeters: center == null
          ? null
          : distanceMeters(center.lat, center.lng, place.lat, place.lng),
      isMock: answer.isMock,
    );
  }

  void _pushDetail(
    Place place, {
    required int? distanceMeters,
    required bool isMock,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => PlaceDetailScreen(
          place: place,
          distanceMeters: distanceMeters,
          isMock: isMock,
        ),
      ),
    );
  }

  List<FloatingTabItem> _items(Services services) => <FloatingTabItem>[
    for (final HomeTab t in HomeTab.values)
      t == HomeTab.checkin && services.visits.visits.isNotEmpty
          ? FloatingTabItem(
              icon: t.item.icon,
              selectedIcon: t.item.selectedIcon,
              label: t.item.label,
              showDot: true,
            )
          : t.item,
  ];

  @override
  Widget build(BuildContext context) {
    final Services services = Services.of(context);
    final MapSearchController search = _search!;
    final Widget pages = IndexedStack(
      index: _tab.index,
      children: <Widget>[
        MapScreen(
          controller: search,
          assistant: _assistant!,
          onOpenPlace: _openPlace,
          onOpenSuggestion: _openSuggestion,
          onCheckInHere: _checkInHere,
          tabRailHeight: FloatingTabRail.compactHeightFor(
            HomeTab.values.length,
            hasTrailing: true,
          ),
        ),
        if (_tab == HomeTab.checkin)
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: CheckinTabScreen(
                controller: _checkin!,
                onShowMap: () => _select(HomeTab.map),
              ),
            ),
          )
        else
          const SizedBox.shrink(),
        if (_opened.contains(HomeTab.timeline))
          TimelineScreen(
            nearbyCenter: () => search.timelineCenter,
            nearbyLabel: () => search.timelineCenterLabel,
            active: _tab == HomeTab.timeline,
            onShowMap: () => _select(HomeTab.map),
          )
        else
          const SizedBox.shrink(),
        if (_opened.contains(HomeTab.achievements))
          const AchievementsScreen()
        else
          const SizedBox.shrink(),
      ],
    );

    return ListenableBuilder(
      listenable: services.visits,
      builder: (BuildContext context, Widget? _) {
        final List<FloatingTabItem> items = _items(services);
        if (!WindowSize.of(context).isCompact) {
          final MediaQueryData media = MediaQuery.of(context);
          // 地図は全面に表示し、タブはその上に浮かせる。地図の上の部品は、左の padding の分だけタブを避ける
          final Widget content = _tab == HomeTab.map
              ? MediaQuery(
                  data: media.copyWith(
                    padding: media.padding.copyWith(
                      left: media.padding.left + FloatingTabRail.space,
                    ),
                  ),
                  child: pages,
                )
              : Padding(
                  padding: const EdgeInsets.only(left: FloatingTabRail.space),
                  child: pages,
                );
          return Scaffold(
            body: Stack(
              children: <Widget>[
                Positioned.fill(child: content),
                Positioned(
                  left: media.padding.left + FloatingTabRail.margin,
                  top: media.padding.top,
                  bottom: media.padding.bottom,
                  // Web 版では地図が HTML の要素なので、タブの上のホイール操作も地図に届いてしまう
                  child: Center(
                    child: PointerInterceptor(
                      child: FloatingTabRail(
                        items: items,
                        selectedIndex: _tab.index,
                        onSelected: (int i) => _select(HomeTab.values[i]),
                        trailing: const SettingsButton(),
                        // 地図では、結果パネルと1枚の面にするため、面を地図の画面が描く
                        showSurface: _tab != HomeTab.map,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          extendBody: true,
          body: pages,
          bottomNavigationBar: FloatingTabBar(
            items: items,
            showLabels: false,
            selectedIndex: _tab.index,
            onSelected: (int i) => _select(HomeTab.values[i]),
          ),
        );
      },
    );
  }
}
