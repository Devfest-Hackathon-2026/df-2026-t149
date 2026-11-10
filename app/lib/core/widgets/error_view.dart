import 'package:flutter/material.dart';
import '../strings.dart';

/// 画面の作成中に例外が起きたときに、配布用のビルドで出す表示。
///
/// Flutter の標準では、配布用のビルドは内容のないグレーの四角を出すため、利用者から何が起きたか分からない。
/// 報告してもらえるよう、例外の内容を短く出す。開発中のビルドは標準の赤い表示のままにする
class BuildErrorView extends StatelessWidget {
  const BuildErrorView({super.key, required this.details});

  final FlutterErrorDetails details;

  /// 配布用のビルドで [ErrorWidget.builder] に入れる
  static Widget builder(FlutterErrorDetails details) =>
      BuildErrorView(details: details);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String message = details.exceptionAsString();
    return Material(
      color: scheme.errorContainer,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.error_outline, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.errorViewMessage,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              message.length > 600 ? '${message.substring(0, 600)}…' : message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
