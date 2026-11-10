import 'package:flutter/widgets.dart';

/// Material 3 の画面幅の区分。画面の幅で、タブの位置と画面の配置を切り替える
enum WindowSize {
  /// 600 未満。スマートフォンの縦向き。下のタブと、下から引き上げる一覧で表示する
  compact,

  /// 600 以上 840 未満。タブレットの縦向きや、狭くしたブラウザ。左の列のタブで切り替える
  medium,

  /// 840 以上。タブレットの横向きや PC。左の列のタブと、2列の配置で表示する
  expanded;

  static const double mediumMinWidth = 600;
  static const double expandedMinWidth = 840;

  static WindowSize forWidth(double width) {
    if (width >= expandedMinWidth) {
      return WindowSize.expanded;
    }
    if (width >= mediumMinWidth) {
      return WindowSize.medium;
    }
    return WindowSize.compact;
  }

  /// 画面全体の幅で決める。左の列のタブの分を引いた幅で決めると、同じ端末でもタブの有無で配置が変わるため
  static WindowSize of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);

  bool get isCompact => this == WindowSize.compact;
}
