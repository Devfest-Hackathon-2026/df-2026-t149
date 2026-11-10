import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/models/timeline_entry.dart';
import '../../core/services.dart';
import '../../core/strings.dart';

/// 口コミへの反応（「行ってみたい」と「参考になった」）。押すと付け外しし、数を見せる。
/// 自分の口コミには反応できないので、数だけを見せる
class ReactionBar extends StatefulWidget {
  const ReactionBar({super.key, required this.entry, this.onChanged});

  final TimelineEntry entry;

  /// 反応を変えた後の記録。一覧と詳細で同じ状態を見せるために使う
  final ValueChanged<TimelineEntry>? onChanged;

  @override
  State<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends State<ReactionBar> {
  late TimelineEntry _entry = widget.entry;
  final Set<ReactionKind> _sending = <ReactionKind>{};

  @override
  void didUpdateWidget(ReactionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sending.isEmpty) {
      _entry = widget.entry;
    }
  }

  Future<void> _toggle(ReactionKind kind) async {
    final bool on = !(kind == ReactionKind.want
        ? _entry.myWant
        : _entry.myHelpful);
    final TimelineEntry before = _entry;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Services services = Services.of(context);
    if (on) {
      Haptics.tap();
    }
    // 待たせないよう先に見た目を変え、失敗したら戻す
    setState(() {
      _sending.add(kind);
      _entry = _entry.withReaction(kind, on: on);
    });
    try {
      final TimelineEntry after = await services.checkins.react(
        before,
        kind,
        on: on,
      );
      if (!mounted) {
        return;
      }
      setState(() => _entry = after);
      widget.onChanged?.call(after);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _entry = before);
      messenger.showSnackBar(SnackBar(content: Text(l10n.reactionFailed)));
    } finally {
      if (mounted) {
        setState(() => _sending.remove(kind));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final TimelineEntry e = _entry;
    final bool canReact = !e.mine;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        _ReactionChip(
          icon: Icons.flag_circle_outlined,
          selectedIcon: Icons.flag_circle,
          label: l10n.reactionWant,
          count: e.wantCount,
          selected: e.myWant,
          onPressed: canReact && !_sending.contains(ReactionKind.want)
              ? () => _toggle(ReactionKind.want)
              : null,
        ),
        _ReactionChip(
          icon: Icons.thumb_up_alt_outlined,
          selectedIcon: Icons.thumb_up_alt,
          label: l10n.reactionHelpful,
          count: e.helpfulCount,
          selected: e.myHelpful,
          onPressed: canReact && !_sending.contains(ReactionKind.helpful)
              ? () => _toggle(ReactionKind.helpful)
              : null,
        ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextStyle? style = Theme.of(context).textTheme.labelMedium;
    final String text = count > 0 ? '$label $count' : label;
    // 自分の口コミ（押せない）は、数のあるときだけ控えめに見せる
    if (onPressed == null && !selected) {
      return Semantics(
        label: l10n.reactionCount(label, count),
        excludeSemantics: true,
        child: Chip(
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          avatar: Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          label: Text(text, style: style),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          labelPadding: const EdgeInsets.only(left: 2, right: 6),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      );
    }
    return FilterChip(
      visualDensity: VisualDensity.compact,
      showCheckmark: false,
      avatar: Icon(
        selected ? selectedIcon : icon,
        size: 16,
        color: selected ? scheme.onSecondaryContainer : scheme.primary,
      ),
      label: Text(text, style: style),
      // 2つのボタンを狭いカードでも横に並べられるよう、内側の余白を詰める
      padding: const EdgeInsets.symmetric(horizontal: 4),
      labelPadding: const EdgeInsets.only(left: 2, right: 6),
      tooltip: count > 0 ? l10n.reactionCount(label, count) : null,
      selected: selected,
      onSelected: onPressed == null ? null : (_) => onPressed!(),
    );
  }
}
