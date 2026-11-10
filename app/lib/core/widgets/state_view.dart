import 'dart:async';

import 'package:flutter/material.dart';

import '../api/uramichi_api.dart';
import '../strings.dart';
import 'phrase_text.dart';

/// [StateView] に置く操作1つ分
@immutable
class StateViewAction {
  const StateViewAction(this.label, this.onPressed, {this.icon});

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
}

/// 0件とエラーの表示。見出しと説明に続けて、利用者が次に行える操作を置く。
///
/// 高さが足りない画面では、呼び出す側でスクロールできる部品に入れる
class StateView extends StatelessWidget {
  const StateView({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.primary,
    this.secondary,
  });

  final String title;
  final String? message;
  final IconData? icon;

  /// 次の操作。OutlinedButton で表示する
  final StateViewAction? primary;

  /// 補助の操作。TextButton で表示する
  final StateViewAction? secondary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final StateViewAction? primary = this.primary;
    final StateViewAction? secondary = this.secondary;
    final IconData? icon = this.icon;
    final String? message = this.message;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 40, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
            ],
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              PhraseText(
                message,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (primary != null) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: primary.onPressed,
                icon: primary.icon == null ? null : Icon(primary.icon),
                label: Text(primary.label),
              ),
            ],
            if (secondary != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: secondary.onPressed,
                icon: secondary.icon == null ? null : Icon(secondary.icon),
                label: Text(secondary.label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 読み込み中に、何を探しているかを一行で示す
class LoadingLabel extends StatelessWidget {
  const LoadingLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 読み込みの失敗を、利用者に表示する一文にする
String describeError(Object error) => switch (error) {
  ApiException(:final String message) => message,
  TimeoutException() => l10n.errorServerTimeout,
  _ => l10n.errorServerUnreachable,
};
