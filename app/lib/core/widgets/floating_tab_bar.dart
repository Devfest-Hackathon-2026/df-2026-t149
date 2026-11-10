import 'package:flutter/material.dart';

import '../theme.dart';

/// [FloatingTabBar] の1項目
@immutable
class FloatingTabItem {
  const FloatingTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.showDot = false,
  });

  /// 確認してほしいものがあることを、アイコンの右上の点で示す
  final bool showDot;

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// 画面の下端から浮かせて表示するタブバー。
///
/// Scaffold の bottomNavigationBar に置き、extendBody を true にすると、画面の内容がタブバーの後ろまで表示される。
/// そのとき本文の MediaQuery.padding.bottom にタブバーの高さが入るため、各画面はその分の余白を下に取る。
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.showLabels = true,
  });

  static const double height = 64;

  /// false ならアイコンだけを表示する。項目名は長押しのツールチップと読み上げで伝える
  final bool showLabels;

  final List<FloatingTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppTheme.radiusSheet),
          // 枠線と影の両方で縁を描くと輪郭が二重になるため、どちらか一方にする
          // 暗い地では影が見えないので、ダークのテーマだけ枠線で地と分ける
          border: dark ? Border.all(color: scheme.outlineVariant) : null,
          boxShadow: dark
              ? null
              : <BoxShadow>[
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.14),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: SizedBox(
          height: height,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: _TabButton(
                    item: items[i],
                    showLabel: showLabels,
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.showLabel,
    required this.selected,
    required this.onTap,
  });

  final FloatingTabItem item;
  final bool showLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: Tooltip(
        message: showLabel ? '' : item.label,
        triggerMode: TooltipTriggerMode.longPress,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: 52,
                height: 36,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: Badge(
                    isLabelVisible: item.showDot,
                    smallSize: 8,
                    child: Icon(
                      selected ? item.selectedIcon : item.icon,
                      size: 26,
                      color: color,
                    ),
                  ),
                ),
              ),
              if (showLabel) ...<Widget>[
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// タブレットと PC で、画面の左端の中央に浮かせて表示する縦のタブ。
///
/// [FloatingTabBar] と同じ見た目で、アイコンの下に項目名を表示する。[trailing] は区切り線の下に置く（設定のボタンなど）。
/// 画面の内容は後ろの全面に表示し、左から [space] の幅をタブのために空ける
class FloatingTabRail extends StatelessWidget {
  const FloatingTabRail({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.trailing,
    this.showSurface = true,
  });

  static const double width = 128;
  static const double margin = 12;
  static const Duration transitionDuration = Duration(milliseconds: 360);
  static const Curve transitionCurve = Curves.easeInOutCubic;

  /// 画面の左端からタブの右側の余白までの幅。画面の内容はこの幅を空けて配置する
  static const double space = margin + width + margin;

  /// ボタンを全て並べたときの高さ
  static double compactHeightFor(int itemCount, {required bool hasTrailing}) =>
      20 + itemCount * 64 + (hasTrailing ? 65 : 0);

  /// タブの面の見た目。地図の画面は、この見た目でタブと結果パネルを1枚の面として描く
  static BoxDecoration surfaceDecoration(ThemeData theme) {
    final ColorScheme scheme = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;
    return BoxDecoration(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppTheme.radiusSheet),
      // FloatingTabBar と同じく、暗い地では影が見えないので枠線で地と分ける
      border: dark ? Border.all(color: scheme.outlineVariant) : null,
      boxShadow: dark
          ? null
          : <BoxShadow>[
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.14),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
    );
  }

  final List<FloatingTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget? trailing;

  /// false のときはボタンだけを描き、面は下に置いた画面に任せる。
  /// タブと結果パネルで別々の面を描くと、開閉の途中に角丸や影の継ぎ目が見えるため
  final bool showSurface;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Widget? trailing = this.trailing;
    return Container(
      width: width,
      constraints: BoxConstraints(
        maxHeight: compactHeightFor(
          items.length,
          hasTrailing: trailing != null,
        ),
      ),
      decoration: showSurface ? surfaceDecoration(theme) : null,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (int i = 0; i < items.length; i++)
                      SizedBox(
                        height: 64,
                        child: _TabButton(
                          item: items[i],
                          showLabel: true,
                          selected: i == selectedIndex,
                          onTap: () => onSelected(i),
                        ),
                      ),
                    if (trailing != null) ...<Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(
                          width: 28,
                          child: Divider(
                            height: 1,
                            color: scheme.outlineVariant,
                          ),
                        ),
                      ),
                      trailing,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
