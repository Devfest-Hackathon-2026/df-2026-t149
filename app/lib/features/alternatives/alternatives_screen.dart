import '../../core/widgets/google_maps_notice.dart';
import 'package:flutter/material.dart';

import '../../core/api/uramichi_api.dart';
import '../../core/models/place.dart';
import '../../core/models/place_genre.dart';
import '../../core/layout.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/widgets/mock_banner.dart';
import '../../core/widgets/place_card.dart';
import '../../core/widgets/place_labels.dart';
import '../../core/widgets/review_count_bar.dart';
import '../../core/widgets/screen_header.dart';
import '../../core/widgets/state_view.dart';
import '../../core/widgets/title_badge.dart';
import '../place/place_detail_screen.dart';
import '../settings/settings_screen.dart';
import '../../core/strings.dart';

/// 「代わりに行くならここ」の画面の状態
sealed class _AlternativesState {
  const _AlternativesState();
}

/// まだ検索していない
final class _Idle extends _AlternativesState {
  const _Idle();
}

final class _Searching extends _AlternativesState {
  const _Searching(this.query);

  final String query;
}

final class _Found extends _AlternativesState {
  const _Found({
    required this.origin,
    required this.alternatives,
    required this.isMock,
  });

  final Place origin;

  /// 未知度の高い順、同じなら近い順に並べた候補
  final List<Place> alternatives;
  final bool isMock;
}

/// 入力した名前の有名スポットが見つからなかった
final class _OriginNotFound extends _AlternativesState {
  const _OriginNotFound(this.query);

  final String query;
}

final class _Failed extends _AlternativesState {
  const _Failed(this.message);

  final String message;
}

/// 代わりに行くならここ：有名スポットの名前から、近くにある知られていない場所を提案する
class AlternativesScreen extends StatefulWidget {
  const AlternativesScreen({super.key, this.initialQuery});

  /// 指定すると開いた時点でこの名前の代わりを探す。別の画面から開くので、見出しの代わりに戻るボタンを置く
  final String? initialQuery;

  static const Key topCandidateKey = ValueKey<String>('top-candidate');

  /// 範囲を広げるときの半径の段階（m）。API の上限は 10000
  static const List<int> radiusSteps = <int>[3000, 6000, 10000];

  /// 候補がこの数より少ないときは、結果の下に範囲を広げる操作を表示する
  static const int enoughCandidates = 3;

  @override
  State<AlternativesScreen> createState() => _AlternativesScreenState();
}

class _AlternativesScreenState extends State<AlternativesScreen> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  _AlternativesState _state = const _Idle();
  int _radius = AlternativesScreen.radiusSteps.first;
  String _searchedQuery = '';

  /// 最後に送ったリクエストの番号。古い応答で新しい結果を上書きしないために使う
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery case final String query) {
      _query.text = query;
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted) {
          _submit(query);
        }
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final String query = text.trim();
    if (query.isEmpty) {
      return;
    }
    _radius = AlternativesScreen.radiusSteps.first;
    _focus.unfocus();
    _search(query);
  }

  Future<void> _search(String query) async {
    final UramichiApi api = Services.of(context).api;
    final int requestId = ++_requestId;
    _searchedQuery = query;
    setState(() => _state = _Searching(query));
    try {
      final AlternativesResult result = await api.alternatives(
        query,
        radius: _radius,
      );
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _state = _Found(
          origin: result.origin,
          alternatives: sortAlternatives(result.alternatives),
          isMock: result.isMock,
        );
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _state = switch (error) {
          ApiException(code: 'origin_not_found') => _OriginNotFound(query),
          _ => _Failed(describeError(error)),
        };
      });
    }
  }

  int? get _nextRadius {
    for (final int step in AlternativesScreen.radiusSteps) {
      if (step > _radius) {
        return step;
      }
    }
    return null;
  }

  void _widen(int radius) {
    _radius = radius;
    _search(_searchedQuery);
  }

  void _editQuery() {
    _query.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _query.text.length,
    );
    _focus.requestFocus();
  }

  void _openPlace(Place place, Place origin, bool isMock) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext _) =>
              PlaceDetailScreen(place: place, origin: origin, isMock: isMock),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final _AlternativesState state = _state;
    final int? nextRadius = _nextRadius;
    final double bottom = MediaQuery.paddingOf(context).bottom + 16;

    final List<Widget> content = switch (state) {
      _Idle() => const <Widget>[],
      _Searching(:final String query) => <Widget>[
        LoadingLabel(l10n.searchingAlternatives(query)),
        const SizedBox(height: 12),
        for (int i = 0; i < 3; i++) ...<Widget>[
          const PlaceCardPlaceholder(),
          const SizedBox(height: 8),
        ],
      ],
      _OriginNotFound(:final String query) => <Widget>[
        StateView(
          icon: Icons.search_off,
          title: l10n.originNotFound(query),
          primary: StateViewAction(
            l10n.searchAnotherName,
            _editQuery,
            icon: Icons.edit,
          ),
        ),
      ],
      _Failed(:final String message) => <Widget>[
        StateView(
          icon: Icons.cloud_off_outlined,
          title: l10n.alternativesLoadFailed,
          message: message,
          primary: StateViewAction(
            l10n.retry,
            () => _search(_searchedQuery),
            icon: Icons.refresh,
          ),
        ),
      ],
      _Found(:final Place origin, alternatives: final List<Place> found)
          when found.isEmpty =>
        <Widget>[
          _OriginCard(origin: origin),
          StateView(
            icon: Icons.travel_explore,
            title: l10n.noAlternativesNearby,
            message: l10n.radiusLabel(formatDistance(_radius)),
            primary: nextRadius == null
                ? null
                : StateViewAction(
                    l10n.widenRange,
                    () => _widen(nextRadius),
                    icon: Icons.zoom_out_map,
                  ),
            secondary: StateViewAction(l10n.searchAnotherName, _editQuery),
          ),
        ],
      _Found(
        :final Place origin,
        alternatives: final List<Place> found,
        :final bool isMock,
      ) =>
        <Widget>[
          _SplitColumns(
            lead: <Widget>[
              _OriginCard(origin: origin),
              _FewerReviews(origin: origin, alternatives: found),
              _TopCandidate(
                key: AlternativesScreen.topCandidateKey,
                place: found.first,
                origin: origin,
                onTap: () => _openPlace(found.first, origin, isMock),
              ),
            ],
            rest: <Widget>[
              if (!isMock) const GoogleMapsAttribution(),
              if (found.length > 1) ...<Widget>[
                _CandidatesHeading(count: found.length - 1),
                const SizedBox(height: 8),
                PlaceList(
                  rows: <Widget>[
                    for (int i = 1; i < found.length; i++)
                      PlaceRow(
                        place: found[i],
                        rank: i + 1,
                        onTap: () => _openPlace(found[i], origin, isMock),
                        footer: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _Reason(place: found[i], origin: origin),
                            const SizedBox(height: 4),
                            ReviewCountBar(
                              count: found[i].userRatingCount,
                              baseline: origin.userRatingCount,
                              title: PlaceTitle.of(found[i].title),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              if (found.length < AlternativesScreen.enoughCandidates &&
                  nextRadius != null) ...<Widget>[
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: () => _widen(nextRadius),
                    icon: const Icon(Icons.zoom_out_map),
                    label: Text(l10n.widenRange),
                  ),
                ),
              ],
            ],
          ),
        ],
    };

    final bool pushed = widget.initialQuery != null;
    return Scaffold(
      appBar: pushed ? AppBar() : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (state case _Found(isMock: true)) const MockBanner(),
            // 幅に任せて折り返すと「ここ。」の途中で切れ、最後の行に1文字だけ残るため、読点の後で改行する
            if (!pushed)
              ScreenHeader(
                title: l10n.alternativesTitle,
                trailing: SettingsButton(),
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  _sidePadding(context),
                  8,
                  _sidePadding(context),
                  bottom,
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: <Widget>[
                  ListenableBuilder(
                    listenable: _query,
                    builder: (BuildContext context, Widget? _) => Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _query,
                            focusNode: _focus,
                            textInputAction: TextInputAction.search,
                            onSubmitted: _submit,
                            decoration: InputDecoration(
                              hintText: l10n.famousSpotHint,
                              suffixIcon: _query.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: l10n.clearInput,
                                      icon: const Icon(Icons.close),
                                      onPressed: () {
                                        _query.clear();
                                        _focus.requestFocus();
                                      },
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: l10n.search,
                          iconSize: 28,
                          icon: const Icon(Icons.search),
                          onPressed: _query.text.trim().isEmpty
                              ? null
                              : () => _submit(_query.text),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Column(
                      key: ValueKey<Object>(state),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: content,
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

/// 候補を有名スポットから近い順に並べる。距離が分からない候補は最後に置く
List<Place> sortAlternatives(List<Place> places) {
  final List<Place> sorted = List<Place>.of(places);
  sorted.sort((Place a, Place b) {
    final int da = a.distanceMeters ?? 1 << 30;
    final int db = b.distanceMeters ?? 1 << 30;
    return da.compareTo(db);
  });
  return sorted;
}

/// 候補を提案した理由。有名スポットと同じジャンルであることとレビュー数の比率を示す
String? alternativeReason(Place place, Place origin) {
  final PlaceGenre? genre = PlaceGenre.of(place);
  // 展望は観光名所全般を含むため、記念碑にも「同じ展望」と表示されてしまう。買い物は「同じ買い物」と読めない
  final bool sameGenre =
      genre != null &&
      genre == PlaceGenre.of(origin) &&
      genre != PlaceGenre.view &&
      genre != PlaceGenre.shopping;
  final List<String> parts = <String>[
    if (sameGenre) l10n.sameGenre(genre.label),
    if (place.userRatingCount > 0 &&
        origin.userRatingCount >= place.userRatingCount * 2)
      l10n.reviewRatio(origin.userRatingCount ~/ place.userRatingCount),
  ];
  return parts.isEmpty ? null : parts.join('・');
}

/// 候補の選定理由の1行
class _Reason extends StatelessWidget {
  const _Reason({required this.place, required this.origin});

  final Place place;
  final Place origin;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? reason = alternativeReason(place, origin);
    if (reason == null) {
      return const SizedBox.shrink();
    }
    return Text(
      reason,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.primary,
      ),
    );
  }
}

/// 特定した有名スポット。レビュー数を大きな数字で表示し、候補と比べる基準にする
class _OriginCard extends StatelessWidget {
  const _OriginCard({required this.origin});

  final Place origin;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Card(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.groups_outlined, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    origin.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.placeName(18),
                  ),
                ),
                const SizedBox(width: 8),
                TitleBadge.of(origin),
              ],
            ),
            const SizedBox(height: 8),
            PlaceFacts(place: origin, showReviews: false),
          ],
        ),
      ),
    );
  }
}

/// 有名スポットと比べて、候補のレビュー数が何分の1以下かを示す
class _FewerReviews extends StatelessWidget {
  const _FewerReviews({required this.origin, required this.alternatives});

  final Place origin;
  final List<Place> alternatives;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? text = fewerReviewsLabel(origin, alternatives);
    if (text == null) {
      return const SizedBox(height: 16);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.south, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 候補のレビュー数が有名スポットの何分の1以下かを表す文字列。2分の1より多ければ null
String? fewerReviewsLabel(Place origin, List<Place> alternatives) {
  int most = 0;
  for (final Place p in alternatives) {
    if (p.userRatingCount > most) {
      most = p.userRatingCount;
    }
  }
  if (most == 0) {
    return origin.userRatingCount > 0 ? l10n.onlyZeroReviews : null;
  }
  final int times = origin.userRatingCount ~/ most;
  if (times < 2) {
    return null;
  }
  return l10n.reviewRatioOrLess(formatCount(times));
}

class _CandidatesHeading extends StatelessWidget {
  const _CandidatesHeading({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: l10n.otherCandidates,
            style: theme.textTheme.titleMedium,
          ),
          TextSpan(
            text: l10n.candidateCount(count),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// いちばん上の候補。有名スポットとレビュー数を並べて比べ、人の少なさを見せる
class _TopCandidate extends StatelessWidget {
  const _TopCandidate({
    super.key,
    required this.place,
    required this.origin,
    required this.onTap,
  });

  final Place place;
  final Place origin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    // キーカラーの枠線で囲むと角丸の輪郭が名前や棒と競うため、薄く色を付けた地でほかの候補と分ける
    return Card(
      color: Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.08),
        scheme.surfaceContainerLowest,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  TitleBadge.of(place),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Reason(place: place, origin: origin),
                  ),
                  Icon(Icons.chevron_right, color: scheme.outline),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(place.name, style: AppTheme.placeName(26)),
              ),
              const SizedBox(height: 8),
              PlaceFacts(place: place),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  children: <Widget>[
                    _CompareRow(
                      label: origin.name,
                      count: origin.userRatingCount,
                      baseline: origin.userRatingCount,
                      title: PlaceTitle.famous,
                    ),
                    const SizedBox(height: 14),
                    _CompareRow(
                      label: l10n.here,
                      count: place.userRatingCount,
                      baseline: origin.userRatingCount,
                      title: PlaceTitle.of(place.title),
                      emphasized: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 名前と件数の下に、レビュー数の棒を並べる
class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.label,
    required this.count,
    required this.baseline,
    required this.title,
    this.emphasized = false,
  });

  final String label;
  final int count;
  final int baseline;
  final PlaceTitle? title;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: emphasized
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              l10n.countLabel(formatCount(count)),
              style: emphasized
                  ? AppTheme.number(22, color: scheme.primary)
                  : AppTheme.number(16, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ReviewCountBar(
          count: count,
          baseline: baseline,
          title: title,
          thickness: 10,
        ),
      ],
    );
  }
}

/// 広い画面で、左右の余白を広げて一覧の幅を抑える
double _sidePadding(BuildContext context) {
  const double maxWidth = 1120;
  final double width = MediaQuery.sizeOf(context).width;
  return width > maxWidth + 32 ? (width - maxWidth) / 2 : 16;
}

/// 有名スポットといちばんの候補の比べ（[lead]）と、ほかの候補（[rest]）。
/// 広い画面では左右に並べ、比べた結果とほかの候補を同時に見られるようにする
class _SplitColumns extends StatelessWidget {
  const _SplitColumns({required this.lead, required this.rest});

  final List<Widget> lead;
  final List<Widget> rest;

  @override
  Widget build(BuildContext context) {
    if (WindowSize.of(context) != WindowSize.expanded || rest.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ...lead,
          if (rest.isNotEmpty) const SizedBox(height: 24),
          ...rest,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: lead,
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rest,
          ),
        ),
      ],
    );
  }
}
