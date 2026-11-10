import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/core/haptics.dart';
import 'package:uramichi/core/sounds.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uramichi/app.dart';
import 'package:uramichi/core/api/uramichi_api.dart';
import 'package:uramichi/core/data/checkin_repository.dart';
import 'package:uramichi/core/settings.dart';
import 'package:uramichi/core/widgets/mock_banner.dart';
import 'package:uramichi/core/theme.dart';
import 'fake_account.dart';
import 'fake_location.dart';

void main() {
  group('キーカラーの選び方の保存', () {
    test('アプリの色、壁紙の色、選んだ色を文字列にして戻せる', () {
      for (final KeyColorChoice c in <KeyColorChoice>[
        const AppKeyColor(),
        const WallpaperKeyColor(),
        const CustomKeyColor(Color(0xFF1E88E5)),
      ]) {
        expect(KeyColorChoice.decode(c.encode()), c);
      }
      expect(const CustomKeyColor(Color(0xFF1E88E5)).encode(), '#1E88E5');
    });

    test('初回は壁紙の色を使い、不正な設定はアプリの色として扱う', () {
      expect(KeyColorChoice.decode(null), isA<WallpaperKeyColor>());
      expect(AppSettings().keyColor, isA<WallpaperKeyColor>());
      expect(KeyColorChoice.decode('app'), isA<AppKeyColor>());
      expect(KeyColorChoice.decode('#XYZ'), isA<AppKeyColor>());
      expect(KeyColorChoice.decode('purple'), isA<AppKeyColor>());
    });

    test('壁紙の色を選んでいても、端末が対応していなければアプリの色を使う', () {
      final AppSettings settings = AppSettings(
        keyColor: const WallpaperKeyColor(),
      );
      expect(settings.resolveKeyColor(), AppTheme.keyColor);
      settings.wallpaperColor = const Color(0xFF00897B);
      expect(settings.resolveKeyColor(), const Color(0xFF00897B));
    });

    test('変えた設定は端末に保存され、次に起動したときに読み込まれる', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      AppSettings.load(prefs)
        ..themeMode = ThemeMode.dark
        ..keyColor = const CustomKeyColor(Color(0xFFD81B60));

      final AppSettings next = AppSettings.load(prefs);
      expect(next.themeMode, ThemeMode.dark);
      expect(next.keyColor, const CustomKeyColor(Color(0xFFD81B60)));
    });
  });

  group('設定の画面', () {
    Future<AppSettings> openSettings(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2700);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final AppSettings settings = AppSettings();
      await tester.pumpWidget(
        UramichiApp(
          account: readyAccountNow(),
          api: UramichiApi(
            baseUrl: 'http://test',
            client: MockClient(
              (http.Request r) async => throw http.ClientException('x', r.url),
            ),
          ),
          checkins: LocalCheckinRepository(),
          location: FakeLocationService(),
          settings: settings,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('設定').first);
      await tester.pumpAndSettle();
      return settings;
    }

    ThemeData currentTheme(WidgetTester tester) =>
        Theme.of(tester.element(find.text('キーカラー')));

    testWidgets('ダークを選ぶと、アプリがダークのテーマに切り替わる', (WidgetTester tester) async {
      final AppSettings settings = await openSettings(tester);
      await tester.tap(find.text('ダーク'));
      await tester.pumpAndSettle();

      expect(settings.themeMode, ThemeMode.dark);
      expect(currentTheme(tester).brightness, Brightness.dark);
    });

    testWidgets('用意した色を選ぶと、その色がアプリの主な色になる', (WidgetTester tester) async {
      final AppSettings settings = await openSettings(tester);
      await tester.tap(find.bySemanticsLabel('#1E88E5'));
      await tester.pumpAndSettle();

      expect(settings.keyColor, const CustomKeyColor(Color(0xFF1E88E5)));
      expect(
        currentTheme(tester).colorScheme.primary,
        AppTheme.light(key: const Color(0xFF1E88E5)).colorScheme.primary,
      );
    });

    testWidgets('ほかの色を押すとカラーピッカーが開き、選んだ色がキーカラーになる', (
      WidgetTester tester,
    ) async {
      final AppSettings settings = await openSettings(tester);
      await tester.tap(find.bySemanticsLabel('ほかの色'));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Slider).first, const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('この色にする'));
      await tester.pumpAndSettle();

      expect(settings.keyColor, isA<CustomKeyColor>());
    });

    testWidgets('端末が壁紙の色に対応していないときは、壁紙の色の候補を表示しない', (
      WidgetTester tester,
    ) async {
      await openSettings(tester);
      expect(find.bySemanticsLabel('壁紙'), findsNothing);
      expect(find.bySemanticsLabel('ウラミチ'), findsOneWidget);
      final Semantics swatch = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == 'ウラミチ',
        ),
      );
      expect(swatch.properties.selected, isTrue);
    });

    testWidgets('デモデータで動かすをオンにしたときだけ、地図にデモデータの帯が出る', (
      WidgetTester tester,
    ) async {
      final AppSettings settings = await openSettings(tester);
      expect(settings.demoMode, isFalse);
      await tester.scrollUntilVisible(
        find.text('デモデータで動かす'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('デモデータで動かす'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('デモデータで動かす'));
      await tester.pumpAndSettle();
      expect(settings.demoMode, isTrue);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('このエリアを探す'));
      await tester.pumpAndSettle();

      expect(find.byType(MockBanner), findsOneWidget);
    });

    testWidgets('プロフィールを押すと、ニックネームとアイコンを変更できる', (WidgetTester tester) async {
      await openSettings(tester);
      expect(find.text('路地裏の旅人'), findsOneWidget);
      expect(find.text('uramichi.taro@gmail.com'), findsOneWidget);

      await tester.tap(find.text('路地裏の旅人'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'たろう');
      await tester.tap(find.byTooltip('電車'));
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.text('たろう'), findsOneWidget);
      expect(find.text('キーカラー'), findsOneWidget);
    });

    testWidgets('効果音をオフにでき、オフのあいだは鳴らさない', (WidgetTester tester) async {
      final _RecordingBackend played = _RecordingBackend();
      Sounds.backend = played;
      addTearDown(() => Sounds.backend = null);
      final AppSettings settings = await openSettings(tester);
      await tester.scrollUntilVisible(
        find.text('効果音'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(settings.soundEnabled, isTrue);

      await tester.tap(find.text('効果音'));
      await tester.pumpAndSettle();
      expect(settings.soundEnabled, isFalse);
      expect(Sounds.enabled, isFalse);
      await Sounds.stamp();
      expect(played.sounds, isEmpty);

      // オンにすると、試しに音を鳴らす
      await tester.tap(find.text('効果音'));
      await tester.pumpAndSettle();
      expect(Sounds.enabled, isTrue);
      expect(played.sounds, <Sound>[Sound.success]);
    });

    test('効果音の設定を保存し、次の起動で読み込む', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      AppSettings.load(prefs).soundEnabled = false;
      expect(AppSettings.load(prefs).soundEnabled, isFalse);
      expect(Sounds.enabled, isFalse);
      AppSettings.load(prefs).soundEnabled = true;
    });

    testWidgets('振動（ハプティクス）をオフにできる', (WidgetTester tester) async {
      final AppSettings settings = await openSettings(tester);
      await tester.scrollUntilVisible(
        find.text('振動（ハプティクス）'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(settings.hapticsEnabled, isTrue);

      await tester.tap(find.text('振動（ハプティクス）'));
      await tester.pumpAndSettle();
      expect(settings.hapticsEnabled, isFalse);
      expect(Haptics.enabled, isFalse);

      await tester.tap(find.text('振動（ハプティクス）'));
      await tester.pumpAndSettle();
      expect(Haptics.enabled, isTrue);
    });

    testWidgets('ログアウトすると、ログインの画面になる', (WidgetTester tester) async {
      await openSettings(tester);
      await tester.scrollUntilVisible(
        find.text('ログアウト'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ログアウト'));
      await tester.pumpAndSettle();

      expect(find.text('Google でログイン'), findsOneWidget);
    });
  });
}

/// 鳴らした音を覚えるだけの、効果音の代わり
class _RecordingBackend implements SoundBackend {
  final List<Sound> sounds = <Sound>[];

  @override
  Future<void> play(Sound sound) async => sounds.add(sound);
}
