import 'package:flutter/material.dart';

/// タブの画面の上に置く大きな見出し
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final Widget? trailing = this.trailing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
