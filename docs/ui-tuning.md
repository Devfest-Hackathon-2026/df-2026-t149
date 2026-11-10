# 見た目の調整

文字の大きさ、色、余白、角丸などを手で調整するときに、どのファイルのどの値を変えればよいかをまとめる。全ての画面に効く値は [theme.dart](../app/lib/core/theme.dart) に集めてあり、部品や画面ごとの値はそれぞれのファイルに書いてある。決まった色や大きさを画面のファイルに直接書かず、まず theme.dart の値で調整できないかを確かめる。

## 変えた結果の確かめ方

`app/` で `flutter run` を実行しておき、ファイルを保存してから `r` を押すと、変えた見た目が画面に反映される。`static const` の値（`AppTheme.keyColor` など）を変えて反映されないときは、`R` でアプリを最初から起動し直す。ライトとダークの両方を確かめるには、アプリの設定の画面で「ライト」と「ダーク」を切り替える。

## 全ての画面に効く値

どれも [app/lib/core/theme.dart](../app/lib/core/theme.dart) にある。

| 変えたいもの | 場所 | 今の値と注意 |
|---|---|---|
| 文字の大きさと太さ | `AppTheme._textTheme` の `sized(…)` の行 | 本文（`bodyLarge`）16、補足（`bodyMedium`）15、ラベル（`labelMedium`）14、画面の見出し（`headlineSmall`）28 など。太さは 400 と 700 だけを使う。ほかの太さを使うと、太さごとに約 2.3MB のフォントを追加で読み込む |
| 場所の名前の書体 | `AppTheme.placeName` | 太字で、行の高さは 1.35。大きさは呼び出す画面ごとに指定する（下の「画面ごとの値」） |
| 強調する数字の書体 | `AppTheme.number` | 太字の等幅の数字で、行の高さは 1.1 |
| 標準のキーカラー | `AppTheme.keyColor` | 利用者が設定の画面で「ウラミチ」を選んだときの色。白い文字とのコントラスト比が 4.5 に届かない明るい色にすると、ライトのテーマでは自動で濃い色に置き換わる |
| 地と文字の色 | `_Neutrals.light`、`_Neutrals.dark` | 画面の地（`background`）、カード（`card`）、文字（`text`）、補助の文字（`subtext`）、区切り線（`divider`）など。ライトとダークで1組ずつある |
| 称号の色 | `TitleColors.fromKey` | 穴場、定番、超有名の色をライトとダークで1つずつ指定する。未踏はキーカラーから作る。バッジの地の薄さは `TitleColor.from` の `alpha`（ライト 0.12、ダーク 0.22） |
| ダミーデータの帯の色 | `AppColors.of` | ライトとダークで、背景と文字を1組ずつ指定する |
| カード、地図、写真、案内の帯の角丸 | `AppTheme.radiusCard` | 16 |
| シート、ダイアログ、浮かせた入れ物の角丸 | `AppTheme.radiusSheet` | 28 |
| 入力欄の角丸 | `AppTheme.radiusField` | 26。1行の入力欄では完全な丸になる |
| ボタン、チップ、ラベルの形 | `controlShape`、`chipTheme`、`floatingActionButtonTheme` | 完全な丸（`StadiumBorder`） |
| ボタンの高さ | `filledButtonTheme`、`outlinedButtonTheme`、`textButtonTheme` の `minimumSize` | 主な操作 52、ほかは 48。押せる部分は 48 より低くしない |
| 入力欄の内側の余白 | `inputDecorationTheme` の `contentPadding` | 左右 16、上下 14 |

## 部品ごとの値

どれも `app/lib/core/widgets/` にある。

| 部品 | 変えたいもの | 場所と今の値 |
|---|---|---|
| 一覧の行（[place_card.dart](../app/lib/core/widgets/place_card.dart) の `PlaceRow`） | 行の余白 | `EdgeInsets.fromLTRB(16, 14, 8, 14)` |
| | 順位の数字 | 欄の幅 36、`AppTheme.number(20, …)` |
| | 場所の名前の大きさ | `AppTheme.placeName(18)` |
| 種類・レビュー数・距離（同じファイルの `PlaceFacts`、`_Fact`） | 項目の間隔とアイコン | `Wrap` の `spacing: 14`、アイコンの `size: 16` |
| タブバー（[floating_tab_bar.dart](../app/lib/core/widgets/floating_tab_bar.dart)） | 高さ | `FloatingTabBar.height` の 64 |
| | 画面の端からの距離 | `SafeArea` の `minimum`（左右 16、下 12） |
| | 角丸 | `BorderRadius.circular(24)` |
| | 選択中のアイコンの地 | 幅 52、高さ 36 |
| 縦のタブ（同じファイルの `FloatingTabRail`） | 幅、画面の端からの距離、角丸 | `width` の 80、`margin` の 12、`BorderRadius.circular(28)` |
| 条件のボタン（[condition_pill.dart](../app/lib/features/map/condition_pill.dart)） | 高さと左右の余白 | `minHeight: 36`、`horizontal: 12` |
| 画面の見出し（[screen_header.dart](../app/lib/core/widgets/screen_header.dart)） | 見出しの周りの余白 | `EdgeInsets.fromLTRB(20, 12, 8, 8)` |
| 称号のバッジ（[title_badge.dart](../app/lib/core/widgets/title_badge.dart)） | 余白と角丸 | 左右 8、上下 3、角丸 6 |
| レビュー数の棒（[review_count_bar.dart](../app/lib/core/widgets/review_count_bar.dart)） | 太さ | `thickness` の既定値 6。呼び出す側で指定もできる |
| 地図のピン（[places_map.dart](../app/lib/core/widgets/places_map.dart)） | ピンの大きさ | 選択中 40、ほか 30（`selected ? 40 : 30`）。数字は `AppTheme.number(12, …)` |

## 画面ごとの値

| 画面 | 変えたいもの | 場所と今の値 |
|---|---|---|
| 代わり（[alternatives_screen.dart](../app/lib/features/alternatives/alternatives_screen.dart)） | いちばん上の候補の名前 | `_TopCandidate` の `AppTheme.placeName(26)` |
| | いちばん上の候補のカードの角丸 | `_TopCandidate` の `BorderRadius.circular(20)` |
| | 比べるレビュー数の数字 | `_CompareRow` の `AppTheme.number(22, …)`（ここ）と `AppTheme.number(16, …)`（有名スポット） |
| | 比べる棒の太さ | `_CompareRow` の `thickness: 10` |
| | 有名スポットの名前 | `_OriginCard` の `AppTheme.placeName(18)` |
| 地図（[map_screen.dart](../app/lib/features/map/map_screen.dart)） | 広い画面の結果のパネルの幅 | `_WideLayoutState` の `panelWidth`（幅の 42%、320〜400） |
| 場所の詳細（[place_detail_screen.dart](../app/lib/features/place/place_detail_screen.dart)） | 場所の名前 | `AppTheme.placeName(24)` |
| | 地図の高さと角丸 | `height: 200`、`BorderRadius.circular(20)` |
| | レビュー数などの値 | `_Stat` の `AppTheme.number(18)` |
| 設定（[settings_screen.dart](../app/lib/features/settings/settings_screen.dart)） | 色の見本の大きさ | `_Swatch._size` の 44 |

## 変えたあとに合わせて直すもの

テストの一部は仕様として決めた値を確かめている。値を変えたら、次のテストと [design.md](design.md) の表を同じ値に直す。

- [theme_test.dart](../app/test/theme_test.dart)：文字の大きさと太さ、いちばん小さい文字が 12 以上であること、ボタンの高さ、カードの角丸、文字と地のコントラスト比
- [widgets_test.dart](../app/test/widgets_test.dart)：タブバーの選択中の色、本文の下の余白にタブバーの高さが入ること
- [design.md](design.md)：色、文字、余白と形の表

直したら、`app/` で次を実行し、全て成功することを確かめる。

```bash
dart format . && flutter analyze && flutter test
```

## 調整するときに守ること

- 文字は 12 より小さくしない。
- 押せる部分の高さは 48 より低くしない。
- 文字と地のコントラスト比は 4.5 以上にする。称号の色はカードの上で 3 以上にする。どちらも theme_test.dart が確かめている。
- 色は ColorScheme の役割（`primary`、`onSurfaceVariant` など）か `TitleColors`、`AppColors` から取り出し、画面のファイルに色の値を直接書かない。
