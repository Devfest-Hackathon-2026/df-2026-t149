import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/core/models/place.dart';
import 'package:uramichi/core/theme.dart';

void main() {
  final ThemeData light = AppTheme.light();
  final ThemeData dark = AppTheme.dark();

  test('ライトとダークのテーマを作れる', () {
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.colorScheme.brightness, Brightness.light);
    expect(dark.colorScheme.brightness, Brightness.dark);
  });

  test('白い文字が読める濃さのキーカラーは、ライトのテーマの主な色にそのまま使う', () {
    const Color key = Color(0xFF5B4FE9);
    expect(AppTheme.light(key: key).colorScheme.primary, key);
  });

  test('キーカラーを変えると、主な色と未踏の称号の色が変わる', () {
    const Color other = Color(0xFF0B7A5A);
    final ThemeData changed = AppTheme.light(key: other);
    expect(changed.colorScheme.primary, other);
    expect(
      changed.extension<TitleColors>()!.forTitle(PlaceTitle.untrodden).color,
      other,
    );

    final ThemeData changedDark = AppTheme.dark(key: other);
    expect(changedDark.colorScheme.primary, isNot(dark.colorScheme.primary));
  });

  test('明るいキーカラーを選んでも、主な色の上の文字は読める', () {
    for (final Color key in <Color>[
      const Color(0xFFFFEB3B),
      const Color(0xFF8BC34A),
      const Color(0xFF00BCD4),
    ]) {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.light(key: key),
        AppTheme.dark(key: key),
      ]) {
        final ColorScheme s = theme.colorScheme;
        expect(
          AppTheme.contrastRatio(s.onPrimary, s.primary),
          greaterThanOrEqualTo(4.5),
          reason: '$key ${theme.brightness}',
        );
      }
    }
  });

  test('地と文字の明るさが、ライトとダークで逆になる', () {
    expect(
      light.colorScheme.surface.computeLuminance(),
      greaterThan(light.colorScheme.onSurface.computeLuminance()),
    );
    expect(
      dark.colorScheme.surface.computeLuminance(),
      lessThan(dark.colorScheme.onSurface.computeLuminance()),
    );
  });

  test('文字と地のコントラスト比は、両方のテーマで 4.5 以上', () {
    for (final ThemeData theme in <ThemeData>[light, dark]) {
      final ColorScheme s = theme.colorScheme;
      expect(_contrast(s.onSurface, s.surface), greaterThanOrEqualTo(4.5));
      expect(
        _contrast(s.onSurfaceVariant, s.surfaceContainerLowest),
        greaterThanOrEqualTo(4.5),
      );
      expect(_contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5));
    }
  });

  test('両方のテーマに、称号の色とダミーデータの帯の色が入る', () {
    for (final ThemeData theme in <ThemeData>[light, dark]) {
      final TitleColors titles = theme.extension<TitleColors>()!;
      final Set<Color> colors = <Color>{
        for (final PlaceTitle t in PlaceTitle.values) titles.forTitle(t).color,
      };
      expect(colors, hasLength(PlaceTitle.values.length));
      expect(titles.forTitle(null), titles.famous);
      expect(theme.extension<AppColors>(), isNotNull);
    }
  });

  test('称号の文字は、両方のテーマでカードの上で読める', () {
    for (final ThemeData theme in <ThemeData>[light, dark]) {
      final TitleColors titles = theme.extension<TitleColors>()!;
      final Color card = theme.colorScheme.surfaceContainerLowest;
      for (final PlaceTitle t in PlaceTitle.values) {
        expect(
          _contrast(titles.forTitle(t).color, card),
          greaterThanOrEqualTo(3),
          reason: '${theme.brightness} ${t.label}',
        );
      }
    }
  });

  test('文字の大きさと太さは docs/design.md の表のとおり', () {
    final TextTheme t = light.textTheme;
    expect(t.headlineSmall!.fontSize, 28);
    expect(t.headlineSmall!.fontWeight, FontWeight.w700);
    expect(t.titleLarge!.fontSize, 20);
    expect(t.titleLarge!.fontWeight, FontWeight.w700);
    expect(t.bodyLarge!.fontSize, 16);
    expect(t.bodyLarge!.fontWeight, FontWeight.w400);
    expect(t.bodyMedium!.fontSize, 15);
    expect(t.labelMedium!.fontSize, 14);
    expect(t.labelMedium!.fontWeight, FontWeight.w700);
  });

  test('いちばん小さい文字も 12 以上にする', () {
    final TextTheme t = light.textTheme;
    for (final TextStyle? style in <TextStyle?>[
      t.bodySmall,
      t.labelSmall,
      t.labelMedium,
      t.bodyMedium,
    ]) {
      expect(style!.fontSize, greaterThanOrEqualTo(12));
    }
  });

  test('場所の名前は太字で、数字は等幅になる', () {
    final TextStyle name = AppTheme.placeName(18);
    expect(name.fontSize, 18);
    expect(name.fontWeight, FontWeight.w700);

    final TextStyle number = AppTheme.number(48);
    expect(number.fontSize, 48);
    expect(number.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  test('押せる部分の高さは 48 以上、主な操作は 52 以上', () {
    final Size filled = light.filledButtonTheme.style!.minimumSize!.resolve(
      <WidgetState>{},
    )!;
    final Size outlined = light.outlinedButtonTheme.style!.minimumSize!.resolve(
      <WidgetState>{},
    )!;
    final Size text = light.textButtonTheme.style!.minimumSize!.resolve(
      <WidgetState>{},
    )!;
    expect(filled.height, greaterThanOrEqualTo(52));
    expect(outlined.height, greaterThanOrEqualTo(48));
    expect(text.height, greaterThanOrEqualTo(48));
  });

  test('カードの角丸は 16', () {
    final RoundedRectangleBorder shape =
        light.cardTheme.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(16));
  });
}

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
