import 'package:flutter/material.dart';

/// カードを、幅に応じた列数で並べる。同じ行のカードは、いちばん高いカードの高さにそろえる。
/// GridView は子の高さを決め打ちにするため、文の長さで高さが変わるカードの下が切れる。そのため行ごとに並べる
abstract final class ResponsiveGrid {
  /// 1枚のカードの最小の幅
  static const double minItemWidth = 320;
  static const int maxColumns = 3;

  /// [width] の中に、幅が [minItemWidth] 以上のカードを何列並べられるか
  static int columnsFor(double width, {double spacing = 12}) =>
      ((width + spacing) / (minItemWidth + spacing)).floor().clamp(
        1,
        maxColumns,
      );

  /// [children] を [columns] 列の行に分ける。ListView の子として並べると、見えている行だけを作る
  static List<Widget> rows(
    List<Widget> children, {
    required int columns,
    double spacing = 12,
  }) => <Widget>[
    for (int start = 0; start < children.length; start += columns) ...<Widget>[
      if (start > 0) SizedBox(height: spacing),
      if (columns == 1)
        children[start]
      else
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = start; i < start + columns; i++) ...<Widget>[
                if (i > start) SizedBox(width: spacing),
                Expanded(
                  child: i < children.length
                      ? children[i]
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
    ],
  ];
}
