import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/core/models/place.dart';
import 'package:uramichi/core/theme.dart';
import 'package:uramichi/core/widgets/floating_tab_bar.dart';
import 'package:uramichi/core/widgets/mock_banner.dart';
import 'package:uramichi/core/widgets/place_card.dart';
import 'package:uramichi/core/widgets/place_labels.dart';
import 'package:uramichi/core/widgets/review_count_bar.dart';
import 'package:uramichi/core/widgets/state_view.dart';
import 'package:uramichi/core/widgets/title_badge.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: child),
);

const _place = Place(
  id: 'p1',
  name: '路地裏の古書喫茶',
  lat: 34.69,
  lng: 135.19,
  primaryType: 'cafe',
  userRatingCount: 1234,
  obscurity: 84,
  title: 'untrodden',
  distanceMeters: 820,
);

void main() {
  group('表示用の文字列', () {
    test('件数は3桁ごとに区切る', () {
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
      expect(formatCount(1234), '1,234');
      expect(formatCount(15400), '15,400');
      expect(formatCount(1234567), '1,234,567');
    });

    test('ピンの件数は 1,000件以上を k で短くする', () {
      expect(formatCompactCount(999), '999');
      expect(formatCompactCount(1000), '1k');
      expect(formatCompactCount(1500), '1.5k');
      expect(formatCompactCount(9800), '9.8k');
      expect(formatCompactCount(15400), '15k');
    });

    test('距離は 1km 未満を m、1km 以上を km で表し、末尾の .0 は付けない', () {
      expect(formatDistance(0), '0 m');
      expect(formatDistance(820), '820 m');
      expect(formatDistance(999), '999 m');
      expect(formatDistance(1000), '1 km');
      expect(formatDistance(3000), '3 km');
      expect(formatDistance(1250), '1.3 km');
    });

    test('場所の種類は日本語で表し、分からない種類は null にする', () {
      expect(placeTypeLabel('cafe'), 'カフェ');
      expect(placeTypeLabel('shinto_shrine'), '神社');
      expect(placeTypeLabel('unknown_type'), isNull);
      expect(placeTypeLabel(null), isNull);
    });
  });

  group('TitleBadge', () {
    testWidgets('称号の文字を称号の色で表示し、未知度の数値は表示しない', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(const TitleBadge(title: PlaceTitle.untrodden)),
      );

      expect(find.text('未踏'), findsOneWidget);
      expect(find.textContaining('84'), findsNothing);

      final TitleColor color = TitleColors.fromKey(Brightness.light).untrodden;
      final Text text = tester.widget<Text>(find.text('未踏'));
      expect(text.style?.color, color.color);
      final DecoratedBox box = tester.widget<DecoratedBox>(
        find
            .ancestor(of: find.text('未踏'), matching: find.byType(DecoratedBox))
            .first,
      );
      expect((box.decoration as ShapeDecoration).color, color.container);
    });
  });

  group('PlaceCard', () {
    testWidgets('順位、名前、称号、種類、レビュー数、距離を表示し、押すと onTap が呼ばれる', (
      WidgetTester tester,
    ) async {
      int tapped = 0;
      await tester.pumpWidget(
        _wrap(PlaceCard(place: _place, rank: 1, onTap: () => tapped++)),
      );

      expect(find.text('1'), findsOneWidget);
      expect(find.text('未踏'), findsOneWidget);
      expect(find.text('路地裏の古書喫茶'), findsOneWidget);
      expect(find.text('カフェ'), findsOneWidget);
      expect(find.text('1,234'), findsOneWidget);
      expect(find.textContaining('レビュー'), findsNothing);
      expect(find.byIcon(Icons.rate_review_outlined), findsOneWidget);
      // 画面では数字だけを見せ、読み上げでは何の数かを伝える
      expect(find.bySemanticsLabel(RegExp('レビュー 1,234件')), findsOneWidget);
      expect(find.text('820 m'), findsOneWidget);
      expect(find.byIcon(Icons.local_cafe_outlined), findsOneWidget);
      expect(find.textContaining('・'), findsNothing);

      await tester.tap(find.byType(PlaceCard));
      expect(tapped, 1);
    });

    testWidgets('数字だけのレビュー数を長押しすると、何の数かを少しのあいだ表示する', (
      WidgetTester tester,
    ) async {
      int tapped = 0;
      await tester.pumpWidget(
        _wrap(PlaceCard(place: _place, onTap: () => tapped++)),
      );

      await tester.longPress(find.text('1,234'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('レビュー 1,234件'), findsOneWidget);
      expect(tapped, 0);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('レビュー 1,234件'), findsNothing);
    });

    testWidgets('距離を渡すと、場所の距離の代わりにその距離を表示する', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(PlaceCard(place: _place, distanceMeters: 1500, onTap: () {})),
      );
      expect(find.textContaining('1.5 km'), findsOneWidget);
      expect(find.textContaining('820 m'), findsNothing);
    });

    testWidgets('評価（星の数）は表示しない', (WidgetTester tester) async {
      const Place rated = Place(
        id: 'p2',
        name: '評価のある場所',
        lat: 0,
        lng: 0,
        rating: 4.6,
        title: 'hidden',
      );
      await tester.pumpWidget(_wrap(PlaceCard(place: rated, onTap: () {})));
      expect(find.textContaining('4.6'), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
    });
  });

  group('ReviewCountBar', () {
    test('幅は log(1 + 件数) / log(1 + 基準の件数) で求める', () {
      expect(ReviewCountBar.ratio(9800, 9800), 1.0);
      expect(ReviewCountBar.ratio(0, 9800), 0.0);
      expect(ReviewCountBar.ratio(99, 9999), closeTo(0.5, 0.001));
    });

    test('基準より多い件数は全幅で止める', () {
      expect(ReviewCountBar.ratio(20000, 9800), 1.0);
    });

    testWidgets('基準の全幅の地に称号の色の棒を重ね、0件でも丸を表示する', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 300,
            child: ReviewCountBar(
              count: 0,
              baseline: 9800,
              title: PlaceTitle.untrodden,
            ),
          ),
        ),
      );

      final Size track = tester.getSize(find.byKey(ReviewCountBar.trackKey));
      final Size bar = tester.getSize(find.byKey(ReviewCountBar.barKey));
      expect(track.width, 300);
      expect(bar.width, greaterThan(0));
      expect(bar.width, bar.height);

      final DecoratedBox fill = tester.widget<DecoratedBox>(
        find.byKey(ReviewCountBar.barKey),
      );
      expect(
        (fill.decoration as BoxDecoration).color,
        TitleColors.fromKey(Brightness.light).untrodden.color,
      );
    });
  });

  group('FloatingTabBar', () {
    testWidgets('選択の背景とアイコンの中心は通知の点の有無にかかわらず一致する', (WidgetTester tester) async {
      Future<void> show(int selected, bool showDot) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              bottomNavigationBar: FloatingTabBar(
                items: <FloatingTabItem>[
                  const FloatingTabItem(
                    icon: Icons.map_outlined,
                    selectedIcon: Icons.map,
                    label: '地図',
                  ),
                  FloatingTabItem(
                    icon: Icons.where_to_vote_outlined,
                    selectedIcon: Icons.where_to_vote,
                    label: 'チェックイン',
                    showDot: showDot,
                  ),
                ],
                selectedIndex: selected,
                showLabels: false,
                onSelected: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      for (final bool dot in <bool>[false, true]) {
        for (final int selected in <int>[0, 1]) {
          await show(selected, dot);
          final Finder icon = find.byIcon(
            selected == 0 ? Icons.map : Icons.where_to_vote,
          );
          final Finder background = find
              .ancestor(of: icon, matching: find.byType(AnimatedContainer))
              .first;
          expect(tester.getCenter(icon), tester.getCenter(background));
          expect(tester.widget<Icon>(icon).size, 26);
        }
      }
    });

    testWidgets('項目を押すと、その番号で onSelected が呼ばれ、選択中の項目はキーカラーで表示する', (
      WidgetTester tester,
    ) async {
      final List<int> selected = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            extendBody: true,
            bottomNavigationBar: FloatingTabBar(
              items: const <FloatingTabItem>[
                FloatingTabItem(
                  icon: Icons.map_outlined,
                  selectedIcon: Icons.map,
                  label: '地図',
                ),
                FloatingTabItem(
                  icon: Icons.alt_route_outlined,
                  selectedIcon: Icons.alt_route,
                  label: '代わり',
                ),
              ],
              selectedIndex: 0,
              onSelected: selected.add,
            ),
          ),
        ),
      );

      await tester.tap(find.text('代わり'));
      expect(selected, <int>[1]);

      final Text label = tester.widget<Text>(find.text('地図'));
      expect(label.style?.color, AppTheme.light().colorScheme.primary);
      expect(find.byIcon(Icons.map), findsOneWidget);
      expect(find.byIcon(Icons.alt_route_outlined), findsOneWidget);
    });

    testWidgets('本文の下の余白にタブバーの高さが入る', (WidgetTester tester) async {
      double? bottom;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            extendBody: true,
            body: Builder(
              builder: (BuildContext context) {
                bottom = MediaQuery.paddingOf(context).bottom;
                return const SizedBox.expand();
              },
            ),
            bottomNavigationBar: FloatingTabBar(
              items: const <FloatingTabItem>[
                FloatingTabItem(
                  icon: Icons.map_outlined,
                  selectedIcon: Icons.map,
                  label: '地図',
                ),
              ],
              selectedIndex: 0,
              onSelected: (int _) {},
            ),
          ),
        ),
      );
      expect(bottom, greaterThanOrEqualTo(FloatingTabBar.height));
    });
  });

  group('MockBanner', () {
    testWidgets('ダミーデータであることを表示する', (tester) async {
      await tester.pumpWidget(_wrap(const MockBanner()));
      expect(find.text('ダミーデータ'), findsOneWidget);
    });
  });

  group('StateView', () {
    testWidgets('見出し、説明、主な操作、補助の操作を表示し、押すとそれぞれ呼ばれる', (tester) async {
      int primary = 0;
      int secondary = 0;
      await tester.pumpWidget(
        _wrap(
          StateView(
            title: '見つかりませんでした',
            message: '半径 1.5 km',
            primary: StateViewAction('範囲を広げる', () => primary++),
            secondary: StateViewAction('地図を動かす', () => secondary++),
          ),
        ),
      );

      expect(find.text('見つかりませんでした'), findsOneWidget);
      expect(find.text('半径 1.5 km'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, '範囲を広げる'));
      await tester.tap(find.widgetWithText(TextButton, '地図を動かす'));
      expect(primary, 1);
      expect(secondary, 1);
    });

    testWidgets('説明と操作は省略できる', (tester) async {
      await tester.pumpWidget(_wrap(const StateView(title: '見つかりませんでした')));
      expect(find.text('見つかりませんでした'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });
  });
}
