import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/core/models/memory_log.dart';
import 'package:uramichi/core/models/place_genre.dart';
import 'package:uramichi/core/share.dart';
import 'package:uramichi/core/strings.dart';
import 'package:uramichi/core/haptics.dart';
import 'package:uramichi/core/widgets/stamp_celebration.dart';
import 'package:uramichi/features/achievements/achievement_widgets.dart';
import 'package:uramichi/features/achievements/achievements.dart';
import 'package:uramichi/features/checkin/checkin_celebration.dart';

MemoryLog _log({int? order = 1, int rating = 5, String comment = '静かでよかった'}) =>
    MemoryLog(
      id: 'a',
      placeId: 'p',
      placeName: '坂の上の祠',
      verdict: Verdict.fromStars(rating),
      rating: rating,
      order: order,
      comment: comment,
      createdAt: DateTime(2026, 11, 8, 12),
    );

void main() {
  test('シェアする文に、場所・何人目か・★評価・ひとことを入れる', () {
    final String text = checkinShareText(
      placeName: '坂の上の祠',
      order: 1,
      stars: 4,
      comment: ' 静か ',
    );
    expect(text, contains('「坂の上の祠」に1人目の訪問者として'));
    expect(text, contains('一番乗り'));
    expect(text, contains('★★★★☆ よかった'));
    expect(text, contains('「静か」'));
    expect(text, contains('#ウラミチ'));

    // 低い★は、場所の悪い評判を広めているように見えるためシェアしない
    final String low = checkinShareText(placeName: '祠', order: 3, stars: 2);
    expect(low, isNot(contains('★')));
    expect(low, isNot(contains(starsLabel(2))));

    final String pending = checkinShareText(placeName: '祠');
    expect(pending, contains('チェックインしました'));
    expect(pending, isNot(contains('人目')));
    expect(pending, isNot(contains('★')));
  });

  test('シェア先の URL に文を入れる', () {
    final Uri x = ShareTarget.x.uri('こんにちは #ウラミチ');
    expect(x.host, 'x.com');
    expect(x.queryParameters['text'], 'こんにちは #ウラミチ');
    // LINE は文を送る URL（line.me/R/share）。空白は「+」ではなく %20 にする（LINE が「+」をそのまま出すため）
    final Uri line = ShareTarget.line.uri('こんにちは ウラミチ\n#旅');
    expect(line.host, 'line.me');
    expect(line.path, '/R/share');
    expect(line.queryParameters['text'], 'こんにちは ウラミチ\n#旅');
    expect(line.toString(), isNot(contains('+')));
    expect(line.toString(), contains('%20'));
  });

  testWidgets('紙吹雪を降らせ、何人目かと解除した実績を見せ、シェアできる', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2700);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final List<Uri> opened = <Uri>[];
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    final MemoryLog log = _log();
    await tester.pumpWidget(
      MaterialApp(
        home: CheckinCelebrationScreen(
          log: log,
          unlocked: newlyUnlocked(const <MemoryLog>[], <MemoryLog>[log]),
          openUrl: (Uri u) async {
            opened.add(u);
            return true;
          },
        ),
      ),
    );
    // 紙吹雪ではなく、チェックインスタンプが押される。1人目なので金色の「一番乗り」
    final StampCelebration stamp = tester.widget(find.byType(StampCelebration));
    expect(stamp.level, CelebrationLevel.newPlace);
    expect(stamp.label, '1人目');
    await tester.pumpAndSettle();
    // 解除した実績はメダルで見せる
    expect(find.byType(MedalReveal), findsWidgets);
    expect(find.text('最高！'), findsOneWidget);
    expect(find.text('実績を解除！'), findsOneWidget);
    expect(find.text('開拓者'), findsOneWidget);

    await tester.ensureVisible(find.text(ShareTarget.x.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ShareTarget.x.label));
    await tester.pump();
    expect(opened.single.host, 'x.com');
    expect(opened.single.queryParameters['text'], contains('坂の上の祠'));

    await tester.ensureVisible(find.text(l10n.shareCopyText));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.shareCopyText));
    await tester.pump();
    expect(copied, contains('#ウラミチ'));
    expect(find.text('シェアする文をコピーしました'), findsOneWidget);
  });

  testWidgets('Instagram へは、印の部分を画像にして共有し、文をコピーしておく', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2700);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    Uint8List? shared;
    String? sharedText;
    await tester.pumpWidget(
      MaterialApp(
        home: CheckinCelebrationScreen(
          log: _log(),
          shareImage: (Uint8List png, String text) async {
            shared = png;
            sharedText = text;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Instagram で共有'));
    await tester.pumpAndSettle();
    // 画像を作るのは実際の時間で進む処理なので、テストの時計の外で待つ
    await tester.runAsync(() async {
      await tester.tap(find.text('Instagram で共有'));
      for (int i = 0; i < 50 && shared == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(shared, isNotNull);
    // PNG の先頭の印
    expect(shared!.sublist(1, 4), utf8.encode('PNG'));
    expect(sharedText, contains('#ウラミチ'));
    expect(copied, contains('坂の上の祠'));
    expect(find.textContaining('Instagram を選んでください'), findsOneWidget);
    // 印の演出の振動の続きを終わらせる
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('シェアの画面を開けなければ知らせる', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2700);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CheckinCelebrationScreen(
          log: _log(order: null, rating: 2, comment: ''),
          openUrl: (Uri _) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.checkinPendingOrder), findsOneWidget);
    await tester.ensureVisible(find.text(ShareTarget.line.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ShareTarget.line.label));
    await tester.pump();
    expect(find.textContaining('開けませんでした'), findsOneWidget);
  });

  testWidgets('アニメーションを減らす設定では、印が押された後の姿だけを出す', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Center(
            child: StampCelebration(
              level: CelebrationLevel.pioneer,
              label: '1人目',
              haptics: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('1人目'), findsOneWidget);
    expect(find.text('一番乗り'), findsOneWidget);
    // アニメーションが動いていない
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('1人目は「一番乗り」の金のスタンプ、前にも来た場所は帯なし', (WidgetTester tester) async {
    for (final (CelebrationLevel level, bool ribbon)
        in <(CelebrationLevel, bool)>[
          (CelebrationLevel.pioneer, true),
          (CelebrationLevel.newPlace, false),
          (CelebrationLevel.revisit, false),
        ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: StampCelebration(
              key: ValueKey<CelebrationLevel>(level),
              level: level,
              label: '3人目',
              haptics: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('一番乗り'), ribbon ? findsOneWidget : findsNothing);
      expect(find.text('3人目'), findsOneWidget);
    }
  });

  testWidgets('印は押された後も、画面を閉じるまで動き続ける', (WidgetTester tester) async {
    StampCelebration.loop = true;
    addTearDown(() => StampCelebration.loop = false);
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: StampCelebration(
            level: CelebrationLevel.newPlace,
            label: '3人目',
            haptics: false,
          ),
        ),
      ),
    );
    // 押される演出が終わったあとも動いている
    await tester.pump(const Duration(seconds: 3));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(seconds: 10));
    expect(tester.hasRunningAnimations, isTrue);
    // 画面を閉じると止まる
    await tester.pumpWidget(const SizedBox());
    expect(tester.hasRunningAnimations, isFalse);
  });

  test('チェックインスタンプは、場所のジャンルで種類が変わる', () {
    expect(StampDesign.of(PlaceGenre.worship), StampDesign.worship);
    expect(StampDesign.of(PlaceGenre.food), StampDesign.food);
    expect(StampDesign.of(null), StampDesign.plain);
    expect(StampDesign.of(PlaceGenre.other), StampDesign.plain);
    // 種類ごとに色が違う（寺社と、ジャンルのない場所は朱色）
    final Set<Color> inks = <Color>{
      for (final StampDesign d in StampDesign.values) d.ink,
    };
    expect(inks.length, StampDesign.values.length - 1);
  });

  testWidgets('どの種類の印も描ける', (WidgetTester tester) async {
    for (final StampDesign d in StampDesign.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: StampCelebration(
              key: ValueKey<StampDesign>(d),
              level: CelebrationLevel.pioneer,
              label: '1人目',
              design: d,
              haptics: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: d.name);
      expect(find.text('1人目'), findsOneWidget);
    }
  });

  testWidgets('解除した実績のカードは、重ならず 8 以上の間を空けて並ぶ', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2700);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final MemoryLog log = _log();
    final List<AchievementProgress> unlocked = <AchievementProgress>[
      for (final AchievementProgress a in computeAchievements(<MemoryLog>[log]))
        if (a.unlocked) a,
    ];
    expect(unlocked.length, greaterThanOrEqualTo(2));
    await tester.pumpWidget(
      MaterialApp(
        home: CheckinCelebrationScreen(log: log, unlocked: unlocked),
      ),
    );
    await tester.pumpAndSettle();

    final List<Rect> cards = <Rect>[
      for (final Element e
          in find
              .ancestor(
                of: find.byType(MedalReveal),
                matching: find.byType(Card),
              )
              .evaluate())
        tester.getRect(find.byWidget(e.widget)),
    ]..sort((Rect a, Rect b) => a.top.compareTo(b.top));
    expect(cards.length, unlocked.length);
    for (int i = 1; i < cards.length; i++) {
      expect(cards[i].top - cards[i - 1].bottom, greaterThanOrEqualTo(8));
    }
  });

  testWidgets('3ボタンのナビゲーションバーがあっても、下までスクロールすると「次の場所を探す」がバーより上に出る', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    // 3ボタンのナビゲーションバー（高さ 48）を、画面の下端の余白として渡す
    tester.view.padding = const FakeViewPadding(bottom: 48 * 3);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48 * 3);
    addTearDown(tester.view.reset);
    final MemoryLog log = _log();
    await tester.pumpWidget(
      MaterialApp(
        home: CheckinCelebrationScreen(
          log: log,
          unlocked: newlyUnlocked(const <MemoryLog>[], <MemoryLog>[log]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pumpAndSettle();

    final Rect button = tester.getRect(
      find.ancestor(
        of: find.text('次の場所を探す'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.bottom, lessThanOrEqualTo(640 - 48));
  });
}
