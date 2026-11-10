import '../../core/widgets/google_maps_notice.dart';
import 'package:flutter/material.dart';

import '../../core/models/assistant_answer.dart';
import '../../core/models/place.dart';
import '../../core/theme.dart';
import '../../core/widgets/mock_banner.dart';
import '../../core/widgets/place_card.dart';
import '../../core/widgets/title_badge.dart';
import '../../core/widgets/favorite_button.dart';
import '../alternatives/alternatives_screen.dart';
import 'assistant_controller.dart';
import 'assistant_situation.dart';
import '../../core/strings.dart';

/// Geminiちゃんのおすすめを開く。距離の基準とダミーかどうかは、そのおすすめを含む [answer] から決める
typedef OpenSuggestion =
    void Function(AssistantSuggestion suggestion, AssistantAnswer answer);

/// Geminiちゃんを下のシートで開く。
///
/// [mapCenter] は話しかけたときの地図の中心（lat, lng）を返す。
/// [onShowOnMap] は答えの地点と条件を地図に反映する。シートは閉じてから呼ぶ
Future<void> showAssistantSheet(
  BuildContext context, {
  required AssistantController controller,
  required (double, double) Function() mapCenter,
  required ValueChanged<AssistantAnswer> onShowOnMap,
  required OpenSuggestion onOpenSuggestion,
  AssistantSituation Function()? situation,
  ValueChanged<AssistantAnswer>? onShowSuggestions,
  ValueChanged<AssistantAnswer>? onExploreWide,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (BuildContext context) => AssistantSheet(
    controller: controller,
    mapCenter: mapCenter,
    onShowOnMap: (AssistantAnswer answer) {
      Navigator.of(context).pop();
      onShowOnMap(answer);
    },
    onOpenSuggestion: onOpenSuggestion,
    situation: situation,
    onShowSuggestions: onShowSuggestions == null
        ? null
        : (AssistantAnswer answer) {
            Navigator.of(context).pop();
            onShowSuggestions(answer);
          },
    onExploreWide: onExploreWide == null
        ? null
        : (AssistantAnswer answer) {
            Navigator.of(context).pop();
            onExploreWide(answer);
          },
  ),
);

/// Geminiちゃん：一言を話しかけると、答えと、地図で見る・場所を開くといった次の操作を返す。
/// チャットの履歴は並べず、最新の一言と答えだけを表示する
class AssistantSheet extends StatefulWidget {
  const AssistantSheet({
    super.key,
    required this.controller,
    required this.mapCenter,
    required this.onShowOnMap,
    required this.onOpenSuggestion,
    this.situation,
    this.onShowSuggestions,
    this.onExploreWide,
  });

  final AssistantController controller;
  final (double, double) Function() mapCenter;
  final ValueChanged<AssistantAnswer> onShowOnMap;
  final OpenSuggestion onOpenSuggestion;

  /// 利用者の状況。例文を選び、Gemini に参考として渡す。null なら決まった例文を出す
  final AssistantSituation Function()? situation;

  /// おすすめをそのまま地図と一覧に出す。null ならボタンを出さない
  final ValueChanged<AssistantAnswer>? onShowSuggestions;

  /// 答えの地点を広い範囲で探す（遠くを調べる）。null ならボタンを出さない
  final ValueChanged<AssistantAnswer>? onExploreWide;

  /// 状況が分からないときに最初に出す例文
  static List<String> examples = <String>[
    l10n.assistantPromptQuiet,
    l10n.assistantPromptCafe,
    l10n.assistantPromptView,
    l10n.assistantPromptNightView,
  ];

  /// 答えの後に出す、続きの依頼の例
  static final List<String> followUps = <String>[
    l10n.assistantPromptOtherGenre,
    l10n.assistantPromptWorship,
    l10n.assistantPromptPark,
  ];

  @override
  State<AssistantSheet> createState() => _AssistantSheetState();
}

class _AssistantSheetState extends State<AssistantSheet> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// 例文。状況が分かれば状況に合わせ、答えのあとは答えの種類に合わせる
  List<String> _chips(AssistantAnswer? answer) {
    final AssistantSituation? s = widget.situation?.call();
    if (s == null) {
      return answer == null
          ? AssistantSheet.examples
          : AssistantSheet.followUps;
    }
    return answer == null
        ? assistantExamples(s)
        : assistantFollowUps(answer, s);
  }

  void _ask(String text) {
    if (text.trim().isEmpty || widget.controller.loading) {
      return;
    }
    final (double lat, double lng) = widget.mapCenter();
    widget.controller.ask(
      text,
      lat: lat,
      lng: lng,
      context: widget.situation?.call().toContextJson(),
    );
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (BuildContext context, Widget? _) {
          final AssistantController c = widget.controller;
          final AssistantAnswer? answer = c.answer;
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Header(
                  answer: answer,
                  onReset: c.message == null ? null : c.reset,
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    children: <Widget>[
                      if (c.message == null)
                        Text(
                          l10n.assistantGreeting,
                          style: Theme.of(context).textTheme.bodyLarge,
                        )
                      else
                        _UserLine(text: c.message!),
                      if (c.loading) ...<Widget>[
                        const SizedBox(height: 16),
                        const _Thinking(),
                      ] else if (c.error != null) ...<Widget>[
                        const SizedBox(height: 16),
                        Text(
                          c.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ] else if (answer != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _AnswerView(
                          answer: answer,
                          onShowOnMap: () => widget.onShowOnMap(answer),
                          onOpenSuggestion: widget.onOpenSuggestion,
                          onShowSuggestions: widget.onShowSuggestions == null
                              ? null
                              : () => widget.onShowSuggestions!(answer),
                          onExploreWide: widget.onExploreWide == null
                              ? null
                              : () => widget.onExploreWide!(answer),
                        ),
                        if (!answer.isMock && answer.mentionsPlaces)
                          const GoogleMapsAttribution(),
                      ],
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final String e in _chips(answer))
                            ActionChip(
                              label: Text(e),
                              onPressed: c.loading ? null : () => _ask(e),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                _InputRow(
                  controller: _text,
                  enabled: !c.loading,
                  onSubmit: _ask,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.answer, required this.onReset});

  final AssistantAnswer? answer;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AssistantAnswer? answer = this.answer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
      child: Row(
        children: <Widget>[
          const AssistantAvatar(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l10n.assistantName, style: theme.textTheme.titleMedium),
                Text(
                  answer == null || answer.byGemini
                      ? l10n.assistantSubtitle
                      : l10n.assistantSimpleMode,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onReset != null)
            IconButton(
              tooltip: l10n.assistantRestart,
              onPressed: onReset,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
    );
  }
}

/// Geminiちゃんのアイコン
class AssistantAvatar extends StatelessWidget {
  const AssistantAvatar({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[scheme.primary, scheme.tertiary],
        ),
      ),
      child: Icon(
        Icons.auto_awesome,
        color: scheme.onPrimary,
        size: size * 0.55,
      ),
    );
  }
}

class _UserLine extends StatelessWidget {
  const _UserLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: l10n.assistantThinking,
    child: Row(
      children: <Widget>[
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(
          l10n.assistantThinkingEllipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}

class _AnswerView extends StatelessWidget {
  const _AnswerView({
    required this.answer,
    required this.onShowOnMap,
    required this.onOpenSuggestion,
    this.onShowSuggestions,
    this.onExploreWide,
  });

  final AssistantAnswer answer;
  final VoidCallback onShowOnMap;
  final OpenSuggestion onOpenSuggestion;
  final VoidCallback? onShowSuggestions;
  final VoidCallback? onExploreWide;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool canShowOnMap = answer.center != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          liveRegion: true,
          child: Text(answer.reply, style: theme.textTheme.bodyLarge),
        ),
        if (answer.isMock && answer.suggestions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            child: const MockBanner(),
          ),
        ],
        // 「近くの駅」のように場所そのものを探したときは、見つかった場所を先に見せ、そばの穴場を続ける
        if (answer.targets.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(l10n.assistantTargetsTitle, style: theme.textTheme.titleSmall),
          for (final Place p in answer.targets) ...<Widget>[
            const SizedBox(height: 8),
            _SuggestionCard(
              suggestion: AssistantSuggestion(
                place: p,
                reason: l10n.assistantTargetReason,
              ),
              onTap: () => onOpenSuggestion(
                AssistantSuggestion(
                  place: p,
                  reason: l10n.assistantTargetReason,
                ),
                answer,
              ),
            ),
          ],
          if (answer.suggestions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              l10n.assistantHiddenNearbyTitle,
              style: theme.textTheme.titleSmall,
            ),
          ],
        ],
        for (final AssistantSuggestion s in answer.suggestions) ...<Widget>[
          const SizedBox(height: 10),
          _SuggestionCard(
            suggestion: s,
            onTap: () => onOpenSuggestion(s, answer),
          ),
        ],
        const SizedBox(height: 12),
        // 答えから、アプリの機能へそのまま進めるようにする
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if ((answer.suggestions.isNotEmpty || answer.targets.isNotEmpty) &&
                onShowSuggestions != null)
              FilledButton.icon(
                onPressed: onShowSuggestions,
                icon: const Icon(Icons.pin_drop_outlined),
                label: Text(l10n.assistantShowOnMap),
              ),
            if (canShowOnMap)
              FilledButton.tonalIcon(
                onPressed: onShowOnMap,
                icon: const Icon(Icons.map_outlined),
                label: Text(
                  answer.intent == AssistantIntent.locate
                      ? l10n.assistantMoveTo(answer.center!.name)
                      : l10n.assistantSearchHere,
                ),
              ),
            if (answer.intent == AssistantIntent.locate &&
                canShowOnMap &&
                onExploreWide != null)
              OutlinedButton.icon(
                onPressed: onExploreWide,
                icon: const Icon(Icons.travel_explore),
                label: Text(l10n.assistantExploreWide(answer.center!.name)),
              ),
            if (answer.intent == AssistantIntent.alternatives &&
                answer.query != null)
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext _) =>
                        AlternativesScreen(initialQuery: answer.query),
                  ),
                ),
                icon: const Icon(Icons.alt_route),
                label: Text(l10n.assistantMoreAlternatives),
              ),
          ],
        ),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestion, required this.onTap});

  final AssistantSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Place place = suggestion.place;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      place.name,
                      style: AppTheme.placeName(17),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TitleBadge(title: PlaceTitle.of(place.title)),
                  FavoriteButton(place: place, compact: true),
                ],
              ),
              const SizedBox(height: 6),
              PlaceFacts(place: place),
              if (suggestion.reason.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        suggestion.reason,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.controller,
    required this.enabled,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              maxLength: AssistantController.maxMessageLength,
              textInputAction: TextInputAction.send,
              onSubmitted: onSubmit,
              decoration: InputDecoration(
                hintText: l10n.assistantInputHint,
                counterText: '',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            tooltip: l10n.send,
            onPressed: enabled ? () => onSubmit(controller.text) : null,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    ),
  );
}
