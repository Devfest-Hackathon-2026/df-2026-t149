import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show PermissionDeniedException;
import 'package:flutter/rendering.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/api/uramichi_api.dart';
import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/sounds.dart';
import '../../core/models/assistant_answer.dart';
import '../../core/location/location_service.dart';
import '../../core/maps/maps_support.dart';
import '../../core/models/place.dart';
import '../../core/models/place_genre.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/widgets/map_zoom.dart';
import '../../core/widgets/floating_tab_bar.dart';
import '../../core/widgets/place_pin.dart';
import '../../core/widgets/places_map.dart';
import '../../core/widgets/state_view.dart';
import '../alternatives/alternatives_screen.dart';
import '../assistant/assistant_controller.dart';
import '../assistant/assistant_sheet.dart';
import '../assistant/assistant_situation.dart';
import '../regions/region_picker.dart';
import '../settings/settings_screen.dart';
import 'condition_pill.dart';
import 'map_search_controller.dart';
import 'results_panel.dart';
import '../../core/strings.dart';

/// 地図：現在地または地図で指定した地点の周囲の穴場を探す
class MapScreen extends StatelessWidget {
  const MapScreen({
    super.key,
    required this.controller,
    required this.assistant,
    required this.onOpenPlace,
    required this.onOpenSuggestion,
    required this.tabRailHeight,
    this.onCheckInHere,
  });

  /// 現在地のそばの場所で「押してスタンプ」を押したとき
  final ValueChanged<Place>? onCheckInHere;

  final MapSearchController controller;

  /// Geminiちゃんとのやり取り。シートを閉じても続きから話しかけられるよう、画面の外で持つ
  final AssistantController assistant;
  final ValueChanged<Place> onOpenPlace;

  /// Geminiちゃんのおすすめを開く
  final OpenSuggestion onOpenSuggestion;

  /// 左の縦のタブの高さ。広い画面では、タブの面をこの高さで描き、結果パネルを開くと上下と右へ広げる
  final double tabRailHeight;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (BuildContext context, Widget? _) =>
        !WindowSize.of(context).isCompact
        ? _WideLayout(
            controller: controller,
            assistant: assistant,
            onOpenPlace: onOpenPlace,
            onOpenSuggestion: onOpenSuggestion,
            tabRailHeight: tabRailHeight,
            onCheckInHere: onCheckInHere,
          )
        : _NarrowLayout(
            controller: controller,
            assistant: assistant,
            onOpenPlace: onOpenPlace,
            onOpenSuggestion: onOpenSuggestion,
            onCheckInHere: onCheckInHere,
          ),
  );
}

class _NarrowLayout extends StatefulWidget {
  const _NarrowLayout({
    required this.controller,
    required this.assistant,
    required this.onOpenPlace,
    required this.onOpenSuggestion,
    this.onCheckInHere,
  });

  final ValueChanged<Place>? onCheckInHere;

  final MapSearchController controller;
  final AssistantController assistant;
  final ValueChanged<Place> onOpenPlace;
  final OpenSuggestion onOpenSuggestion;

  @override
  State<_NarrowLayout> createState() => _NarrowLayoutState();
}

class _NarrowLayoutState extends State<_NarrowLayout> {
  /// 上の操作部分（検索欄とジャンル）の下端の位置。測るまでは null
  double? _controlsBottom;

  /// まだ探していないときの、下の案内の高さ。測るまでは null
  double? _idleHeight;

  /// 結果のシートと上の操作部分の間に空ける幅
  static const double _sheetGap = 8;

  /// 結果のシートの高さ（画面の高さに対する割合）。シートを引くたびに画面全体（地図を含む）を
  /// 作り直さないよう、右下のボタンの位置だけがこの値で動く
  final ValueNotifier<double> _sheetExtent = ValueNotifier<double>(0.4);

  @override
  void dispose() {
    _sheetExtent.dispose();
    super.dispose();
  }

  /// 右下のボタンの間隔と、シートとの間
  static const double _gap = 12;

  /// ズームのレバーの溝の長さ
  static const double _leverLength = 110;

  void _onControlsSize(Size size) {
    if (size.height != _controlsBottom) {
      setState(() => _controlsBottom = size.height);
    }
  }

  void _onIdleSize(Size size) {
    if (size.height != _idleHeight) {
      setState(() => _idleHeight = size.height);
    }
  }

  @override
  Widget build(BuildContext context) {
    final MapSearchController controller = widget.controller;
    final bool hasSheet = controller.state is! SearchIdle;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        // シートを引き上げても上の操作部分に重ならないよう、操作部分の下で止める
        final double maxSheet = _controlsBottom == null
            ? 0.6
            : ((box.maxHeight - _controlsBottom! - _sheetGap) / box.maxHeight)
                  .clamp(0.3, 0.92);
        final double minSheet = math.min(0.2, maxSheet);
        final double initialSheet = math.min(0.4, maxSheet);
        return Stack(
          children: <Widget>[
            Positioned.fill(child: _Map(controller: controller)),
            if (hasSheet)
              NotificationListener<DraggableScrollableNotification>(
                onNotification: (DraggableScrollableNotification n) {
                  _sheetExtent.value = n.extent;
                  return false;
                },
                child: DraggableScrollableSheet(
                  // 上限が変わったときに作り直し、範囲の外の大きさのままにしない
                  key: ValueKey<double>(maxSheet),
                  initialChildSize: initialSheet,
                  minChildSize: minSheet,
                  maxChildSize: maxSheet,
                  // 決まった高さに吸いつかせず、指を離した位置で止める（地図と一覧を見たい割合は人それぞれのため）
                  snap: false,
                  builder: (BuildContext context, ScrollController scroll) =>
                      Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        elevation: 1,
                        shadowColor: Theme.of(context).colorScheme.shadow,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ResultsPanel(
                          controller: controller,
                          onOpenPlace: widget.onOpenPlace,
                          onCheckInHere: widget.onCheckInHere,
                          scrollController: scroll,
                          showHandle: true,
                          leadingFilters: _leadingFilters(context, controller),
                        ),
                      ),
                ),
              )
            else
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _SizeReporter(
                  onSize: _onIdleSize,
                  child: _IdleCard(controller: controller),
                ),
              ),
            // 結果の一覧が加わると子の位置がずれるため、検索欄の入力を保つようキーで区別する
            Positioned(
              key: const ValueKey<String>('map-controls'),
              left: 0,
              right: 0,
              top: 0,
              child: _SizeReporter(
                onSize: _onControlsSize,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: _SearchField(
                          controller: controller,
                          elevated: true,
                        ),
                      ),
                      _GenreRow(controller: controller),
                    ],
                  ),
                ),
              ),
            ),
            // 地図を動かしたら上に「このエリアを探す」を出す
            if (hasSheet && _controlsBottom != null)
              Positioned(
                left: 0,
                right: 0,
                top: _controlsBottom! + 4,
                child: Center(
                  child: _SearchActionButton(controller: controller),
                ),
              ),
            // 右下：拡大・縮小、現在地、Geminiちゃん。シート（まだ探していなければ下の案内）のすぐ上に置いて
            // シートと一緒に動かし、引き上げて場所が足りなければ上から順に隠す
            ValueListenableBuilder<double>(
              valueListenable: _sheetExtent,
              builder: (BuildContext context, double extent, Widget? _) {
                final double fabBottom = hasSheet
                    ? box.maxHeight * extent + _gap
                    : (_idleHeight ?? 0) + _gap;
                final double room =
                    box.maxHeight - fabBottom - (_controlsBottom ?? 0);
                const double fabs = 56 + _gap + 40 + _gap;
                // レバーを出す場所がなければ、＋と－だけにする。それも入らなければ隠す
                final bool showLever =
                    room >=
                    fabs + ZoomLever.heightWith(_leverLength) + _gap + 56;
                final bool showZoom =
                    room >= fabs + ZoomLever.compactHeight + _gap + 56;
                final bool showFabs = room >= fabs + 56;
                return Positioned(
                  right: 16,
                  bottom: fabBottom,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      if (showZoom) ...<Widget>[
                        ZoomLever(
                          controller: controller.zoom,
                          leverLength: _leverLength,
                          compact: !showLever,
                        ),
                        const SizedBox(height: _gap),
                      ],
                      if (showFabs) ...<Widget>[
                        _MyLocationButton(controller: controller),
                        const SizedBox(height: _gap),
                        _AssistantButton(
                          controller: controller,
                          assistant: widget.assistant,
                          onOpenSuggestion: widget.onOpenSuggestion,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// 結果の一覧の絞り込みの先頭に置く、探す地域と代わりを探すボタン
List<Widget> _leadingFilters(
  BuildContext context,
  MapSearchController controller,
) => <Widget>[
  _AreaChip(controller: controller),
  if (controller.searchedQuery case final String query)
    ConditionPill(
      label: l10n.findAlternatives,
      icon: Icons.alt_route,
      selected: false,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => AlternativesScreen(initialQuery: query),
        ),
      ),
    ),
];

/// まだ探していないときに下に出す案内。探し方を3つから選ぶ
class _IdleCard extends StatelessWidget {
  const _IdleCard({required this.controller});

  final MapSearchController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      elevation: 1,
      shadowColor: scheme.shadow,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          20,
          16,
          MediaQuery.paddingOf(context).bottom + 16,
        ),
        child: _IdlePrompt(controller: controller),
      ),
    );
  }
}

/// 探し方の案内。地図の中心、現在地、遠くの地域のどれから探すか
class _IdlePrompt extends StatelessWidget {
  const _IdlePrompt({required this.controller});

  final MapSearchController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.idleTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          l10n.idleMessage,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        // 地名で移動した直後は、その場所の代わりを探すのがウラミチのいちばんの使い方
        if (controller.searchedQuery case final String query) ...<Widget>[
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) =>
                    AlternativesScreen(initialQuery: query),
              ),
            ),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.alt_route),
            label: Text(l10n.findAlternativesFor(query)),
          ),
          const SizedBox(height: 8),
        ],
        FilledButton.icon(
          onPressed: () {
            Haptics.tap();
            Sounds.tap();
            controller.search();
          },
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          icon: const Icon(Icons.travel_explore),
          label: Text(l10n.searchThisArea),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => searchNearbyFromUser(context, controller),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.my_location),
                label: Text(l10n.searchNearby),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => searchFarRegion(context, controller),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.public),
                label: Text(l10n.exploreFar),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 探す地域の選択。今どこを基準に探しているかを見せ、押すと現在地か遠くの地域に切り替えられる
class _AreaChip extends StatelessWidget {
  const _AreaChip({required this.controller});

  final MapSearchController controller;

  @override
  Widget build(BuildContext context) {
    final String label = controller.isWide
        ? (controller.searchedPlaceName ?? l10n.farRegion)
        : controller.measuresFromUser
        ? l10n.nearCurrentLocation
        : (controller.searchedPlaceName ?? l10n.nearMapCenter);
    return MenuAnchor(
      menuChildren: <Widget>[
        MenuItemButton(
          leadingIcon: const Icon(Icons.my_location),
          onPressed: () => searchNearbyFromUser(context, controller),
          child: Text(l10n.searchNearby),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.public),
          onPressed: () => searchFarRegion(context, controller),
          child: Text(l10n.exploreFar),
        ),
      ],
      builder: (BuildContext context, MenuController menu, Widget? _) =>
          ConditionPill(
            label: label,
            icon: controller.isWide
                ? Icons.public
                : controller.measuresFromUser
                ? Icons.my_location
                : Icons.place_outlined,
            selected: false,
            trailing: const Icon(Icons.expand_more),
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
          ),
    );
  }
}

/// 現在地のまわりを探す。現在地がわからなければ地図の中心のまわりを探す
Future<void> searchNearbyFromUser(
  BuildContext context,
  MapSearchController controller,
) async {
  Haptics.tap();
  Sounds.tap();
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    final LocationAccess access = await controller.searchNearby();
    if (access != LocationAccess.granted) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.searchNearbyNoLocation)),
      );
    }
  } catch (error) {
    debugPrint('現在地を測定できません: $error');
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error is PermissionDeniedException
              ? l10n.locationDeniedBrowser
              : l10n.searchNearbyLocationFailed,
        ),
      ),
    );
    controller.search();
  }
}

/// 遠くの地域を選んで、広い範囲で探す
Future<void> searchFarRegion(
  BuildContext context,
  MapSearchController controller,
) async {
  Haptics.tap();
  Sounds.tap();
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final RegionChoice? choice = await showRegionPicker(context);
  if (choice == null) {
    return;
  }
  if (choice.region case final region?) {
    controller.exploreRegion(region);
    return;
  }
  try {
    if (await controller.exploreFar(choice.query!)) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.movedToMockPlace)));
    }
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error is ApiException ? error.message : describeError(error),
        ),
      ),
    );
  }
}

/// 子の大きさが変わったら [onSize] で知らせる
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) => renderObject.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _last) {
      _last = size;
      final Size reported = size;
      WidgetsBinding.instance.addPostFrameCallback((_) => onSize(reported));
    }
  }
}

/// タブレットと PC の配置。Google マップの Web 版と同じく、探す前は地図を全幅で見せ、
/// 探した後だけ左から結果のパネルを出す。パネルは右の縁のつまみで畳める
class _WideLayout extends StatefulWidget {
  const _WideLayout({
    required this.controller,
    required this.assistant,
    required this.onOpenPlace,
    required this.onOpenSuggestion,
    required this.tabRailHeight,
    this.onCheckInHere,
  });

  final MapSearchController controller;
  final AssistantController assistant;
  final ValueChanged<Place> onOpenPlace;
  final OpenSuggestion onOpenSuggestion;
  final double tabRailHeight;
  final ValueChanged<Place>? onCheckInHere;

  @override
  State<_WideLayout> createState() => _WideLayoutState();
}

class _WideLayoutState extends State<_WideLayout> {
  static const Duration _slide = FloatingTabRail.transitionDuration;
  static const Curve _curve = FloatingTabRail.transitionCurve;

  /// 地図の端と、浮かせた部品の間
  static const double _edge = 12;

  /// 結果パネルの左右の余白。ResultsPanel の一覧の左右の余白と同じ
  static const double _panelPadding = 16;

  /// 検索欄の下端。パネルの一覧はここから始める
  static const double _searchBottom = _edge + 52 + _edge;

  bool _panelOpen = true;
  bool _hadResults = false;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSearchChanged);
    _hadResults = widget.controller.state is! SearchIdle;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSearchChanged);
    super.dispose();
  }

  /// 新しく探したときと、地図のピンを選んだときは、畳んだパネルを開き直して結果を見せる
  void _onSearchChanged() {
    final MapSearchController controller = widget.controller;
    final bool hasResults = controller.state is! SearchIdle;
    final String? selectedId = controller.selected?.id;
    final bool reopen =
        (hasResults && !_hadResults) ||
        (selectedId != null && selectedId != _selectedId);
    _hadResults = hasResults;
    _selectedId = selectedId;
    if (reopen && !_panelOpen) {
      setState(() => _panelOpen = true);
    }
  }

  void _setPanel(bool open) {
    Haptics.tap();
    setState(() => _panelOpen = open);
  }

  @override
  Widget build(BuildContext context) {
    final MapSearchController controller = widget.controller;
    final bool hasResults = controller.state is! SearchIdle;
    final bool showPanel = hasResults && _panelOpen;
    final Duration slide = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _slide;
    // 3ボタンのナビゲーションバーを出す端末では、画面の下端がバーの後ろに入る
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    final double topInset = MediaQuery.paddingOf(context).top;
    // 左の浮かせたタブの分。地図はタブの後ろまで表示し、地図の上の部品だけをずらす
    final double leftInset = MediaQuery.paddingOf(context).left;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double panelWidth = ((box.maxWidth - leftInset) * 0.52).clamp(
          320,
          460,
        );
        final double mapLeft = leftInset + (showPanel ? panelWidth : 0);
        final double panelLeft = leftInset - FloatingTabRail.margin;
        return Stack(
          children: <Widget>[
            Positioned.fill(child: _Map(controller: controller)),
            // 縦のタブの面と結果パネルを1枚の面として描く。開くと上下と右へ広がり、畳むと縦のタブの大きさに戻る。
            // タブは面を描かずにボタンだけをこの上に重ねる
            Positioned(
              left: panelLeft - FloatingTabRail.width,
              right: 0,
              top: topInset + _edge,
              bottom: bottomInset + _edge,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints area) {
                  final double collapsedInset =
                      ((area.maxHeight - widget.tabRailHeight) / 2).clamp(
                        0,
                        double.infinity,
                      );
                  final BoxDecoration surface =
                      FloatingTabRail.surfaceDecoration(Theme.of(context));
                  return Stack(
                    children: <Widget>[
                      AnimatedPositioned(
                        duration: slide,
                        curve: _curve,
                        left: 0,
                        top: showPanel ? 0 : collapsedInset,
                        bottom: showPanel ? 0 : collapsedInset,
                        width:
                            FloatingTabRail.width +
                            (showPanel ? panelWidth : 0),
                        child: PointerInterceptor(
                          child: DecoratedBox(
                            key: const ValueKey<String>('wide-tab-surface'),
                            decoration: surface,
                            // 一覧が枠線の上に重ならないよう、枠線は一覧より手前に描く
                            child: DecoratedBox(
                              position: DecorationPosition.foreground,
                              decoration: BoxDecoration(
                                border: surface.border,
                                borderRadius: surface.borderRadius,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusSheet,
                                ),
                                // 一覧は開き終えた大きさで固定し、面の広がりに合わせて見える範囲だけを増やす
                                child: OverflowBox(
                                  alignment: Alignment.centerLeft,
                                  minWidth: FloatingTabRail.width + panelWidth,
                                  maxWidth: FloatingTabRail.width + panelWidth,
                                  minHeight: area.maxHeight,
                                  maxHeight: area.maxHeight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      left: FloatingTabRail.width,
                                      top: _searchBottom,
                                    ),
                                    child: IgnorePointer(
                                      ignoring: !showPanel,
                                      child: ExcludeSemantics(
                                        excluding: !showPanel,
                                        child: ResultsPanel(
                                          controller: controller,
                                          onOpenPlace: widget.onOpenPlace,
                                          onCheckInHere: widget.onCheckInHere,
                                          leadingFilters: _leadingFilters(
                                            context,
                                            controller,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (hasResults)
              AnimatedPositioned(
                duration: slide,
                curve: _curve,
                left: showPanel ? panelLeft + panelWidth : panelLeft,
                top:
                    (box.maxHeight +
                        topInset -
                        bottomInset -
                        _PanelHandle.height) /
                    2,
                child: PointerInterceptor(
                  child: _PanelHandle(
                    open: showPanel,
                    onTap: () => _setPanel(!showPanel),
                  ),
                ),
              ),
            // 一覧の行と左右の端をそろえ、パネルの右の縁との間も空ける
            Positioned(
              left: panelLeft + _panelPadding,
              top: topInset + _edge + 8,
              width: panelWidth - _panelPadding * 2,
              child: _SearchField(
                controller: controller,
                elevated: true,
                showSettings: false,
              ),
            ),
            // ジャンルは、Google マップの種類のチップと同じく検索欄の右に並べる
            AnimatedPositioned(
              duration: slide,
              curve: _curve,
              left: showPanel ? mapLeft + _edge : leftInset + panelWidth,
              right: _edge,
              top: topInset + _edge + 8,
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: PlaceGenre.values.length,
                separatorBuilder: (BuildContext _, int _) =>
                    const SizedBox(width: 8),
                itemBuilder: (BuildContext _, int i) => _genrePill(
                  controller,
                  PlaceGenre.values[i],
                  elevated: true,
                ),
              ),
            ),
            if (hasResults)
              AnimatedPositioned(
                duration: slide,
                curve: _curve,
                left: mapLeft,
                right: 0,
                top: topInset + _searchBottom + 12,
                child: Center(
                  child: _SearchActionButton(controller: controller),
                ),
              )
            else
              Positioned(
                left: leftInset + _edge,
                // 右下のボタンの列と重ならないよう、その幅を空ける
                right: _edge + 56 + _edge,
                bottom: bottomInset + 24,
                child: Center(child: _IdleActions(controller: controller)),
              ),
            Positioned(
              right: 16,
              bottom: bottomInset + 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ZoomLever(controller: controller.zoom),
                  const SizedBox(height: 12),
                  _MyLocationButton(controller: controller),
                  const SizedBox(height: 12),
                  _AssistantButton(
                    controller: controller,
                    assistant: widget.assistant,
                    onOpenSuggestion: widget.onOpenSuggestion,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 結果のパネルの右の縁に付ける、パネルを畳むつまみ
class _PanelHandle extends StatelessWidget {
  const _PanelHandle({required this.open, required this.onTap});

  static const double width = 48;
  static const double height = 64;

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: open ? l10n.collapseList : l10n.expandList,
      child: Material(
        color: scheme.surfaceContainerLowest,
        elevation: 2,
        shadowColor: scheme.shadow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(height / 2),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: width,
            height: height,
            child: Icon(
              open ? Icons.chevron_left : Icons.chevron_right,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 広い画面で、まだ探していないときに地図の下に浮かせる探し方の操作
class _IdleActions extends StatelessWidget {
  const _IdleActions({required this.controller});

  final MapSearchController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    const Size buttonSize = Size(0, 48);
    return Material(
      color: scheme.surfaceContainerLow,
      elevation: 2,
      shadowColor: scheme.shadow,
      // 中のボタンが完全な丸なので、余白を挟んだ入れ物も完全な丸にして縁を平行にする
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (controller.searchedQuery case final String query)
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext _) =>
                        AlternativesScreen(initialQuery: query),
                  ),
                ),
                style: OutlinedButton.styleFrom(minimumSize: buttonSize),
                icon: const Icon(Icons.alt_route),
                label: Text(l10n.findAlternativesFor(query)),
              ),
            FilledButton.icon(
              onPressed: () {
                Haptics.tap();
                Sounds.tap();
                controller.search();
              },
              style: FilledButton.styleFrom(minimumSize: buttonSize),
              icon: const Icon(Icons.travel_explore),
              label: Text(l10n.searchThisArea),
            ),
            FilledButton.tonalIcon(
              onPressed: () => searchNearbyFromUser(context, controller),
              style: FilledButton.styleFrom(minimumSize: buttonSize),
              icon: const Icon(Icons.my_location),
              label: Text(l10n.searchNearby),
            ),
            FilledButton.tonalIcon(
              onPressed: () => searchFarRegion(context, controller),
              style: FilledButton.styleFrom(minimumSize: buttonSize),
              icon: const Icon(Icons.public),
              label: Text(l10n.exploreFar),
            ),
          ],
        ),
      ),
    );
  }
}

/// 地図。検索の状態が変わるたびに Google マップを作り直すと、マーカーと円を毎回プラグインに送るので重い。
/// 地図に関わる値が変わったときだけ作り直す
class _Map extends StatefulWidget {
  const _Map({required this.controller});

  final MapSearchController controller;

  @override
  State<_Map> createState() => _MapState();
}

class _MapState extends State<_Map> {
  Widget? _built;
  List<Object?> _inputs = const <Object?>[];

  @override
  Widget build(BuildContext context) {
    final MapSearchController controller = widget.controller;
    final List<Object?> inputs = <Object?>[
      controller.visiblePlaces,
      controller.center,
      controller.selected?.id,
      controller.radius,
      controller.userLocation,
      controller.isStale,
      controller.zoom,
      Theme.of(context).colorScheme,
    ];
    if (_built == null || !_sameInputs(inputs)) {
      _inputs = inputs;
      _built = PlacesMap(
        places: controller.visiblePlaces,
        center: controller.center,
        selectedPlaceId: controller.selected?.id,
        searchRadiusMeters: controller.radius,
        userLocation: controller.userLocation,
        dimmed: controller.isStale,
        zoom: controller.zoom,
        // 拡大・縮小は右下の ZoomSlider で行う。Google マップの標準のボタンと二重にしない
        showZoomControls: false,
        onCenterChanged: (center) => controller.moveTo(
          center,
          mapRendersMovement: MapsSupport.available,
        ),
        onTapPlace: controller.select,
      );
    }
    return _built!;
  }

  bool _sameInputs(List<Object?> next) {
    for (int i = 0; i < next.length; i++) {
      // 一覧は同じ中身でも作り直されることがあるので、中身で比べる
      final Object? a = _inputs[i];
      final Object? b = next[i];
      if (a is List<Place> && b is List<Place>) {
        if (a.length != b.length) {
          return false;
        }
        for (int j = 0; j < a.length; j++) {
          if (!identical(a[j], b[j])) {
            return false;
          }
        }
      } else if (a != b) {
        return false;
      }
    }
    return true;
  }
}

Widget _genrePill(
  MapSearchController controller,
  PlaceGenre genre, {
  bool elevated = false,
}) => ConditionPill(
  label: genre.label,
  icon: genreIcons[genre],
  selected: controller.genres.contains(genre),
  pending: controller.isGenrePending(genre),
  elevated: elevated,
  onTap: () => controller.toggleGenre(genre),
);

class _GenreRow extends StatelessWidget {
  const _GenreRow({required this.controller});

  final MapSearchController controller;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      itemCount: PlaceGenre.values.length,
      separatorBuilder: (BuildContext _, int _) => const SizedBox(width: 8),
      itemBuilder: (BuildContext _, int i) =>
          _genrePill(controller, PlaceGenre.values[i], elevated: true),
    ),
  );
}

/// 探すボタン。結果が今の条件と一致している間は表示しない
class _SearchActionButton extends StatelessWidget {
  const _SearchActionButton({required this.controller});

  static const Duration _duration = Duration(milliseconds: 180);

  final MapSearchController controller;

  @override
  Widget build(BuildContext context) {
    final SearchAction action = controller.action;
    final Widget child = switch (action) {
      // 探した直後も、同じ場所で探し直せるようにする（新しく口コミが増えた、通信が途切れた、など）
      SearchAction.none when controller.state is SearchLoaded => _button(
        context,
        Icons.refresh,
        l10n.searchAgain,
      ),
      SearchAction.none => const SizedBox.shrink(key: ValueKey<String>('none')),
      SearchAction.searchArea => _button(
        context,
        Icons.travel_explore,
        l10n.searchThisArea,
      ),
      SearchAction.applyConditions => _button(
        context,
        Icons.refresh,
        l10n.searchWithConditions,
      ),
    };
    return AnimatedSwitcher(duration: _duration, child: child);
  }

  Widget _button(BuildContext context, IconData icon, String label) =>
      FilledButton.icon(
        key: ValueKey<String>(label),
        onPressed: () {
          Haptics.tap();
          Sounds.tap();
          controller.search();
        },
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: const StadiumBorder(),
          elevation: 4,
        ),
        icon: Icon(icon),
        label: Text(label),
      );
}

/// Geminiちゃんを開くボタン
class _AssistantButton extends StatelessWidget {
  const _AssistantButton({
    required this.controller,
    required this.assistant,
    required this.onOpenSuggestion,
  });

  final MapSearchController controller;
  final AssistantController assistant;
  final OpenSuggestion onOpenSuggestion;

  /// Geminiちゃんに渡す利用者の状況
  AssistantSituation _situation(BuildContext context) => AssistantSituation(
    now: DateTime.now(),
    onSite: controller.measuresFromUser,
    searchedPlace: controller.searchedQuery,
    area: controller.isWide ? controller.searchedPlaceName : null,
    genres: controller.genres,
    favoriteCount: Services.of(context).favorites?.count ?? 0,
    famousNearby: _famousNearby(),
  );

  /// 探した結果の中で、いちばん口コミの多い定番・超有名の場所
  String? _famousNearby() {
    final SearchState state = controller.state;
    if (state is! SearchLoaded) {
      return null;
    }
    Place? best;
    for (final Place p in state.places) {
      final PlaceTitle? t = PlaceTitle.of(p.title);
      if ((t == PlaceTitle.famous || t == PlaceTitle.known) &&
          (best == null || p.userRatingCount > best.userRatingCount)) {
        best = p;
      }
    }
    return best?.name;
  }

  /// おすすめを、探し直さずに地図と一覧に出す
  void _showSuggestions(AssistantAnswer answer) {
    final AssistantCenter? center = answer.center;
    // 見つかった場所（「近くの駅」など）と、そばの穴場をいっしょに出す
    final List<Place> places = <Place>[
      ...answer.targets,
      for (final AssistantSuggestion s in answer.suggestions) s.place,
    ];
    if (places.isEmpty) {
      return;
    }
    controller.showPlaces(
      places: places,
      center: center == null
          ? LatLng(places.first.lat, places.first.lng)
          : LatLng(center.lat, center.lng),
      name: center == null || center.name == '地図の中心' ? null : center.name,
      isMock: answer.isMock,
    );
  }

  /// 答えの地点を、広い範囲で探す
  void _exploreWide(AssistantAnswer answer) {
    final AssistantCenter? center = answer.center;
    if (center == null) {
      return;
    }
    controller.exploreWide(
      center: LatLng(center.lat, center.lng),
      name: center.name,
    );
  }

  /// 答えの地点と条件を地図に反映する。移動だけの依頼では探さず、ジャンルも変えない
  void _showOnMap(AssistantAnswer answer) {
    final AssistantCenter? center = answer.center;
    if (center == null) {
      return;
    }
    final bool moveOnly = answer.intent == AssistantIntent.locate;
    controller.showAssistantResult(
      center: LatLng(center.lat, center.lng),
      genres: moveOnly ? controller.genres : answer.genres,
      // 地図の中心のまわりを探したときは、地名として表示しない
      name:
          answer.intent == AssistantIntent.recommend &&
              answer.query == null &&
              center.name == '地図の中心'
          ? null
          : center.name,
      query: answer.query,
      search: !moveOnly,
    );
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: l10n.assistantName,
    child: Material(
      elevation: 3,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showAssistantSheet(
          context,
          controller: assistant,
          mapCenter: () =>
              (controller.center.latitude, controller.center.longitude),
          onShowOnMap: _showOnMap,
          onOpenSuggestion: onOpenSuggestion,
          situation: () => _situation(context),
          onShowSuggestions: _showSuggestions,
          onExploreWide: _exploreWide,
        ),
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: AssistantAvatar(size: 48),
        ),
      ),
    ),
  );
}

class _MyLocationButton extends StatelessWidget {
  const _MyLocationButton({required this.controller});

  final MapSearchController controller;

  Future<void> _go(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final LocationService location = controller.location;
    try {
      final LocationAccess access = await controller.goToUserLocation();
      if (access != LocationAccess.granted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              access == LocationAccess.serviceOff
                  ? l10n.locationServiceOff
                  : l10n.locationDenied,
            ),
            action: SnackBarAction(
              label: l10n.openSettings,
              onPressed: () => location.openSettings(access),
            ),
          ),
        );
      }
    } catch (error) {
      debugPrint('現在地を測定できません: $error');
      messenger.showSnackBar(
        SnackBar(
          // Web 版はブラウザが許可を尋ね、拒否されると測定の失敗として返る
          content: Text(
            error is PermissionDeniedException
                ? l10n.locationDeniedBrowser
                : l10n.locationFailed,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // Material 3 の小さな FAB（地図の上なので、地の色は surfaceContainerHigh）
    return FloatingActionButton.small(
      heroTag: null,
      tooltip: l10n.goToMyLocation,
      backgroundColor: scheme.surfaceContainerHigh,
      foregroundColor: scheme.primary,
      onPressed: controller.locating ? null : () => _go(context),
      child: controller.locating
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.my_location),
    );
  }
}

/// 地図を移動する先の検索欄
class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.controller,
    this.elevated = false,
    this.showSettings = true,
  });

  final MapSearchController controller;
  final bool elevated;

  /// 入力が空のとき、右端に設定のボタンを出すか。左の列のタブがある画面では、設定のボタンを列の下に置く
  final bool showSettings;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _searching = false;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit(String value) async {
    final String query = value.trim();
    if (query.isEmpty) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    _focus.unfocus();
    setState(() => _searching = true);
    try {
      if (await widget.controller.jumpTo(query)) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.movedToMockPlace)));
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException ? error.message : describeError(error),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      elevation: widget.elevated ? 3 : 0,
      shape: StadiumBorder(
        side: widget.elevated
            ? BorderSide.none
            : BorderSide(color: scheme.outlineVariant),
      ),
      child: ListenableBuilder(
        listenable: _text,
        builder: (BuildContext context, Widget? _) => TextField(
          controller: _text,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onSubmitted: _submit,
          decoration: InputDecoration(
            hintText: l10n.searchPlaceHint,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            prefixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: l10n.search,
                    icon: const Icon(Icons.search),
                    onPressed: () => _submit(_text.text),
                  ),
            suffixIcon:
                _text.text.isNotEmpty ||
                    (!widget.showSettings &&
                        widget.controller.state is! SearchIdle)
                ? IconButton(
                    tooltip: l10n.clearSearch,
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _text.clear();
                      widget.controller.clearResults();
                      _focus.requestFocus();
                    },
                  )
                : widget.showSettings
                ? const SettingsButton()
                : null,
          ),
        ),
      ),
    );
  }
}
