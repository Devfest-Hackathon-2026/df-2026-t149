import 'package:flutter/material.dart';

import '../theme.dart';
import '../strings.dart';

/// ダミーデータを表示しているときに、画面の上に出す帯
class MockBanner extends StatelessWidget {
  const MockBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.read(context);
    final TextStyle? style = Theme.of(context).textTheme.labelMedium;
    return Semantics(
      container: true,
      liveRegion: true,
      child: ColoredBox(
        color: colors.mockBackground,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.science_outlined,
                size: 16,
                color: colors.mockForeground,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.mockData,
                  style: style?.copyWith(color: colors.mockForeground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
