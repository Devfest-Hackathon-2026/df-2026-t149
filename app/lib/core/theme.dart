import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models/place.dart';

/// 色、文字、形の共通設定（docs/design.md）。画面ごとに色や文字の大きさを直接記述せず、ここから使う。
abstract final class AppTheme {
  /// アプリの標準のキーカラー。利用者が設定で別の色を選ぶと、その色からテーマを作る。
  /// ライトとダークの両方のテーマの主な色と、未踏の称号の色はキーカラーから作る
  static const Color keyColor = Color.fromARGB(255, 93, 225, 101);

  /// false のとき、フォントをネットワークから取得せず端末の標準のフォントを使う。
  // GoogleFonts.config.allowRuntimeFetching = false は assets にフォントがないと例外を投げるため、テストではこの値で取得自体を止める
  static bool useGoogleFonts = true;

  /// ★評価の★の色（明るい背景と暗い背景のどちらでも見える黄色）
  static const Color starColor = Color(0xFFF5A623);

  /// チェックインスタンプの朱色。御朱印の朱肉の色
  static const Color sealRed = Color(0xFFC53D2B);

  /// 1人目の訪問者のチェックインスタンプの金色
  static const Color sealGold = Color(0xFFB8860B);

  /// 実績のめずらしさの色（ふつう・レア・すごくレア・伝説）。
  /// テーマ（キーカラー）と混ざらず、どのテーマでも目立つよう、決まった鮮やかな色にする
  static const List<Color> rarityColors = <Color>[
    Color(0xFF0FA697), // ふつう：青緑
    Color(0xFF2F6FED), // レア：青
    Color(0xFF9B3FE0), // すごくレア：紫
    Color(0xFFE5486C), // 伝説：紅
  ];

  /// 段階のある実績の色（ブロンズ・シルバー・ゴールド）。明るい色と暗い色の組で、メダルの光沢を描く
  static const List<(Color, Color)> tierColors = <(Color, Color)>[
    (Color(0xFFE09A5B), Color(0xFF9A5424)),
    (Color(0xFFDCE3EA), Color(0xFF7D8B99)),
    (Color(0xFFFFDA4A), Color(0xFFD08A00)),
  ];

  /// 角丸の段階。押せる部品と小さなラベルは完全な丸（StadiumBorder）にし、
  /// カード、地図、写真、帯は radiusCard、シート、ダイアログ、浮かせた入れ物は radiusSheet にする
  static const double radiusCard = 16;
  static const double radiusSheet = 28;

  /// 入力欄の角丸。1行の入力欄の高さ 52 の半分なので、1行では完全な丸になり、複数行でも角の形が変わらない
  static const double radiusField = 26;

  static ThemeData light({Color key = keyColor}) =>
      _build(Brightness.light, key);

  static ThemeData dark({Color key = keyColor}) => _build(Brightness.dark, key);

  /// キーカラーから色の役割を作る。地と文字は無彩色に近い色に固定し、主な色だけをキーカラーから取る
  static ColorScheme colorScheme(
    Brightness brightness, {
    Color key = keyColor,
  }) {
    final ColorScheme seeded = ColorScheme.fromSeed(
      seedColor: key,
      brightness: brightness,
    );
    final _Neutrals n = brightness == Brightness.light
        ? _Neutrals.light
        : _Neutrals.dark;
    return seeded.copyWith(
      primary: _primary(brightness, key, seeded),
      onPrimary: _keepsKey(brightness, key)
          ? const Color(0xFFFFFFFF)
          : seeded.onPrimary,
      surface: n.background,
      surfaceContainerLowest: n.card,
      surfaceContainerLow: n.card,
      surfaceContainer: n.raised,
      surfaceContainerHigh: n.raised,
      surfaceContainerHighest: n.raisedHigh,
      onSurface: n.text,
      onSurfaceVariant: n.subtext,
      outline: n.outline,
      outlineVariant: n.divider,
      shadow: const Color(0xFF14142B),
    );
  }

  /// ライトではキーカラーをそのまま主な色にする。ただし白い文字との
  /// コントラスト比が 4.5 に届かない明るい色（黄色など）と、ダークのテーマでは、
  /// キーカラーから作った読みやすい明るさの色を使う
  static Color _primary(Brightness brightness, Color key, ColorScheme seeded) =>
      _keepsKey(brightness, key) ? key : seeded.primary;

  static bool _keepsKey(Brightness brightness, Color key) =>
      brightness == Brightness.light &&
      contrastRatio(const Color(0xFFFFFFFF), key) >= 4.5;

  /// 2色のコントラスト比（WCAG 2.1 の定義）
  static double contrastRatio(Color a, Color b) {
    final double la = a.computeLuminance();
    final double lb = b.computeLuminance();
    final double hi = la > lb ? la : lb;
    final double lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  static ThemeData _build(Brightness brightness, Color key) {
    final ColorScheme scheme = colorScheme(brightness, key: key);
    final ThemeData base = ThemeData(
      colorScheme: scheme,
      brightness: brightness,
      useMaterial3: true,
    );
    final TextTheme textTheme = _textTheme(
      base.textTheme,
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    const StadiumBorder controlShape = StadiumBorder();

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      extensions: <ThemeExtension<dynamic>>[
        TitleColors.fromKey(brightness, key: key),
        AppColors.of(brightness),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 3,
        // Material 3 の上部アプリバーの見出しは titleLarge
        titleTextStyle: textTheme.titleLarge,
      ),
      // Material 3 の下から出すシート：角は 28、地は surfaceContainerLow、つまみを出す
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
        dragHandleSize: const Size(32, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radiusSheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSheet),
        ),
        titleTextStyle: textTheme.headlineSmall,
      ),
      // Material 3 の FAB：地は primaryContainer。形はほかの押せる部品と同じく完全な丸にする
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: 3,
        shape: const StadiumBorder(),
        smallSizeConstraints: const BoxConstraints.tightFor(
          width: 48,
          height: 48,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: textTheme.labelLarge,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 8,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(48, 40),
          side: BorderSide(color: scheme.outline),
          selectedBackgroundColor: scheme.secondaryContainer,
          selectedForegroundColor: scheme.onSecondaryContainer,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.secondaryContainer,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: controlShape,
          textStyle: textTheme.titleSmall,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          // 塗りのボタンと並べたときに高さをそろえる
          minimumSize: const Size(64, 52),
          shape: controlShape,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: textTheme.titleSmall,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: controlShape,
          textStyle: textTheme.titleSmall,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        hintStyle: textTheme.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }

  // 一覧の行ごとに書体を作り直さないよう、大きさごとに作った書体を使い回す
  static final Map<double, TextStyle> _placeNames = <double, TextStyle>{};
  static final Map<double, TextStyle> _numbers = <double, TextStyle>{};

  /// 場所の名前の書体。大きさは画面ごとに指定する
  static TextStyle placeName(double size, {Color? color}) {
    final TextStyle base = _placeNames.putIfAbsent(size, () {
      final TextStyle style = TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1.35,
      );
      return useGoogleFonts
          ? GoogleFonts.zenKakuGothicNew(textStyle: style)
          : style;
    });
    return color == null ? base : base.copyWith(color: color);
  }

  /// 強調する数字の書体。桁がそろうよう等幅の数字にする
  static TextStyle number(double size, {Color? color}) {
    final TextStyle base = _numbers.putIfAbsent(size, () {
      final TextStyle style = TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1.1,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );
      return useGoogleFonts
          ? GoogleFonts.zenKakuGothicNew(textStyle: style)
          : style;
    });
    return color == null ? base : base.copyWith(color: color);
  }

  /// 1行の文字の行の高さ。同梱の書体は行の上の余白が下より広く、既定の行の高さでは文字が約 0.06 文字分下に寄る。
  /// 行の余白を書体の上下の比で配分し、行の高さを 1.22 にすると、かなと英字の中心が行の中心から 0.02 文字以内に収まる
  static const double lineHeightSingle = 1.22;

  static TextTheme _textTheme(TextTheme base) {
    // 太さを 400 と 700 の 2 つにそろえ、読み込むフォントファイルを 2 つに抑える（500 を残すと 1 ファイル約 2.3MB 増える）
    TextStyle? sized(TextStyle? s, double size, FontWeight weight) =>
        s?.copyWith(fontSize: size, fontWeight: weight);
    // ボタン、チップ、見出しなど1行で使う文字は、アイコンと上下の中心がそろう行の高さにする
    TextStyle? line(TextStyle? s, double size, FontWeight weight) =>
        sized(s, size, weight)?.copyWith(
          height: lineHeightSingle,
          // Material 3 の既定（even）は余白を上下に均等に分け、書体の上下の差が残るため、書体の比で分ける
          leadingDistribution: TextLeadingDistribution.proportional,
        );
    final TextTheme sizedTheme = base.copyWith(
      // 本文を 16 にし、そこから約 1.2 倍ずつの段階で大きさを決める。いちばん小さい文字も 12 より小さくしない
      headlineSmall: line(base.headlineSmall, 28, FontWeight.w700),
      titleLarge: line(base.titleLarge, 20, FontWeight.w700),
      titleMedium: line(base.titleMedium, 18, FontWeight.w700),
      titleSmall: line(base.titleSmall, 16, FontWeight.w700),
      bodyLarge: sized(base.bodyLarge, 16, FontWeight.w400),
      bodyMedium: sized(base.bodyMedium, 15, FontWeight.w400),
      bodySmall: sized(base.bodySmall, 13, FontWeight.w400),
      labelLarge: line(base.labelLarge, 15, FontWeight.w700),
      labelMedium: line(base.labelMedium, 14, FontWeight.w700),
      labelSmall: line(base.labelSmall, 12, FontWeight.w700),
    );
    return useGoogleFonts
        ? GoogleFonts.zenKakuGothicNewTextTheme(sizedTheme)
        : sizedTheme;
  }
}

/// 地と文字の色。ライトとダークで1組ずつ持つ
class _Neutrals {
  const _Neutrals({
    required this.background,
    required this.card,
    required this.raised,
    required this.raisedHigh,
    required this.text,
    required this.subtext,
    required this.outline,
    required this.divider,
  });

  static const _Neutrals light = _Neutrals(
    background: Color(0xFFF5F5F9),
    card: Color(0xFFFFFFFF),
    raised: Color(0xFFEDEDF3),
    raisedHigh: Color(0xFFE3E3EB),
    text: Color(0xFF1A1A22),
    subtext: Color(0xFF686876),
    outline: Color(0xFFB4B4C0),
    divider: Color(0xFFE6E6EE),
  );

  static const _Neutrals dark = _Neutrals(
    background: Color(0xFF111116),
    card: Color(0xFF1C1C24),
    raised: Color(0xFF26262F),
    raisedHigh: Color(0xFF30303A),
    text: Color(0xFFEDEDF2),
    subtext: Color(0xFFA3A3B0),
    outline: Color(0xFF5C5C68),
    divider: Color(0xFF2E2E38),
  );

  final Color background;
  final Color card;
  final Color raised;
  final Color raisedHigh;
  final Color text;
  final Color subtext;
  final Color outline;
  final Color divider;
}

/// 称号1つ分の色。[color] は文字、棒、ピンに使い、[container] はバッジの地に使う
@immutable
class TitleColor {
  const TitleColor({
    required this.color,
    required this.onColor,
    required this.container,
  });

  /// [color] から、バッジの地に使う薄い色を作る
  factory TitleColor.from(Color color, Brightness brightness) => TitleColor(
    color: color,
    onColor: color.computeLuminance() > 0.45
        ? const Color(0xFF1A1A22)
        : const Color(0xFFFFFFFF),
    container: color.withValues(
      alpha: brightness == Brightness.light ? 0.12 : 0.22,
    ),
  );

  final Color color;

  /// [color] で塗った面の上の文字の色
  final Color onColor;
  final Color container;

  static TitleColor lerp(TitleColor a, TitleColor b, double t) => TitleColor(
    color: Color.lerp(a.color, b.color, t)!,
    onColor: Color.lerp(a.onColor, b.onColor, t)!,
    container: Color.lerp(a.container, b.container, t)!,
  );
}

/// 称号の色。ピン、バッジ、比較の棒で共通に使う。
///
/// いちばん知られていない「未踏」はキーカラーから作り、アプリの主な色と結び付ける。
@immutable
class TitleColors extends ThemeExtension<TitleColors> {
  const TitleColors({
    required this.untrodden,
    required this.hidden,
    required this.known,
    required this.famous,
  });

  factory TitleColors.fromKey(
    Brightness brightness, {
    Color key = AppTheme.keyColor,
  }) {
    final bool light = brightness == Brightness.light;
    TitleColor of(Color c) => TitleColor.from(c, brightness);
    return TitleColors(
      untrodden: of(AppTheme.colorScheme(brightness, key: key).primary),
      hidden: of(light ? const Color(0xFF0F8A7A) : const Color(0xFF4CC7B5)),
      known: of(light ? const Color(0xFFC07D0A) : const Color(0xFFE9B44C)),
      famous: of(light ? const Color(0xFF8A8A97) : const Color(0xFF8F8F9C)),
    );
  }

  final TitleColor untrodden;
  final TitleColor hidden;
  final TitleColor known;
  final TitleColor famous;

  static TitleColors of(BuildContext context) =>
      Theme.of(context).extension<TitleColors>() ??
      TitleColors.fromKey(Theme.of(context).brightness);

  /// 称号が分からない場所は、目立たせないよう超有名と同じ色にする
  TitleColor forTitle(PlaceTitle? title) => switch (title) {
    PlaceTitle.untrodden => untrodden,
    PlaceTitle.hidden => hidden,
    PlaceTitle.known => known,
    PlaceTitle.famous || null => famous,
  };

  @override
  TitleColors copyWith({
    TitleColor? untrodden,
    TitleColor? hidden,
    TitleColor? known,
    TitleColor? famous,
  }) => TitleColors(
    untrodden: untrodden ?? this.untrodden,
    hidden: hidden ?? this.hidden,
    known: known ?? this.known,
    famous: famous ?? this.famous,
  );

  @override
  TitleColors lerp(TitleColors? other, double t) {
    if (other == null) {
      return this;
    }
    return TitleColors(
      untrodden: TitleColor.lerp(untrodden, other.untrodden, t),
      hidden: TitleColor.lerp(hidden, other.hidden, t),
      known: TitleColor.lerp(known, other.known, t),
      famous: TitleColor.lerp(famous, other.famous, t),
    );
  }
}

/// ColorScheme の役割にない色
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.mockBackground, required this.mockForeground});

  factory AppColors.of(Brightness brightness) => brightness == Brightness.light
      ? const AppColors(
          mockBackground: Color(0xFFFFF3CF),
          mockForeground: Color(0xFF4A3500),
        )
      : const AppColors(
          mockBackground: Color(0xFF3A2F10),
          mockForeground: Color(0xFFFFE08A),
        );

  /// ダミーデータを表示しているときの帯
  final Color mockBackground;
  final Color mockForeground;

  static AppColors read(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ??
      AppColors.of(Theme.of(context).brightness);

  @override
  AppColors copyWith({Color? mockBackground, Color? mockForeground}) =>
      AppColors(
        mockBackground: mockBackground ?? this.mockBackground,
        mockForeground: mockForeground ?? this.mockForeground,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) {
      return this;
    }
    return AppColors(
      mockBackground: Color.lerp(mockBackground, other.mockBackground, t)!,
      mockForeground: Color.lerp(mockForeground, other.mockForeground, t)!,
    );
  }
}
