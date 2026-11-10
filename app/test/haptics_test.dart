import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uramichi/core/haptics.dart';
import 'package:uramichi/core/models/memory_log.dart';
import 'package:uramichi/core/settings.dart';
import 'package:uramichi/core/widgets/star_rating.dart';
import 'package:uramichi/features/achievements/achievements.dart';
import 'package:uramichi/features/checkin/checkin_celebration.dart';

/// 端末へ送った振動の種類（HapticFeedbackType.mediumImpact など）
List<String> _recordHaptics(WidgetTester tester) {
  final List<String> calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add('${call.arguments}'.replaceFirst('HapticFeedbackType.', ''));
      }
      return null;
    },
  );
  return calls;
}

void main() {
  tearDown(() => Haptics.enabled = true);

  testWidgets('オンのときは振動させ、オフのときは何もしない', (WidgetTester tester) async {
    final List<String> calls = _recordHaptics(tester);
    await Haptics.tap();
    await Haptics.select();
    expect(calls, <String>['lightImpact', 'selectionClick']);

    Haptics.enabled = false;
    await Haptics.tap();
    await Haptics.star(5);
    expect(calls, hasLength(2));
  });

  testWidgets('祝うときは強い振動を続けて鳴らす', (WidgetTester tester) async {
    final List<String> calls = _recordHaptics(tester);
    await tester.runAsync(Haptics.celebrate);
    expect(calls, <String>['heavyImpact', 'mediumImpact', 'heavyImpact']);
    calls.clear();
    await tester.runAsync(Haptics.success);
    expect(calls, <String>['mediumImpact', 'heavyImpact']);
  });

  test('振動の設定を端末に保存し、読み直せる', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final AppSettings settings = AppSettings.load(prefs);
    expect(settings.hapticsEnabled, isTrue);
    expect(Haptics.enabled, isTrue);

    settings.hapticsEnabled = false;
    expect(Haptics.enabled, isFalse);
    expect(prefs.getBool('haptics'), isFalse);

    Haptics.enabled = true;
    final AppSettings reloaded = AppSettings.load(prefs);
    expect(reloaded.hapticsEnabled, isFalse);
    expect(Haptics.enabled, isFalse);
  });

  testWidgets('★が多いほど強く振動させる', (WidgetTester tester) async {
    final List<String> calls = _recordHaptics(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StarRatingInput(value: null, onChanged: (int _) {}),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('★1、${starsLabel(1)}'));
    await tester.tap(find.bySemanticsLabel('★4、${starsLabel(4)}'));
    await tester.tap(find.bySemanticsLabel('★5、${starsLabel(5)}'));
    await tester.pump();
    expect(calls, <String>['selectionClick', 'lightImpact', 'mediumImpact']);
  });

  testWidgets('チェックインの振動は、はじめての場所と1人目ほど長く強い', (WidgetTester tester) async {
    final List<String> calls = _recordHaptics(tester);
    final List<MethodCall> native = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('uramichi/haptics'),
      (MethodCall call) async {
        native.add(call);
        return true;
      },
    );
    for (final CelebrationLevel level in CelebrationLevel.values) {
      await tester.runAsync(() => Haptics.checkin(level));
    }
    // Android では端末の振動の機能で、強さと長さを決めて鳴らす
    expect(native, hasLength(3));
    int total(MethodCall c) =>
        ((c.arguments as Map)['timings'] as List<Object?>)
            .cast<int>()
            .fold<int>(0, (int a, int b) => a + b);
    expect(total(native[0]), lessThan(total(native[1])));
    expect(total(native[1]), lessThan(total(native[2])));
    expect(calls, isEmpty);

    // 端末の振動の機能を使えないときは、Flutter の振動を続けて鳴らす
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('uramichi/haptics'),
      (MethodCall call) async => false,
    );
    await tester.runAsync(() => Haptics.checkin(CelebrationLevel.pioneer));
    expect(calls, contains('heavyImpact'));
  });

  testWidgets('祝う画面は、印とメダルに合わせて振動する', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2700);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final List<String> calls = _recordHaptics(tester);
    final MemoryLog log = MemoryLog(
      id: 'a',
      placeId: 'p',
      placeName: '祠',
      verdict: Verdict.hit,
      rating: 5,
      order: 12,
      createdAt: DateTime(2026, 11, 8, 12),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CheckinCelebrationScreen(
          log: log,
          unlocked: newlyUnlocked(const <MemoryLog>[], <MemoryLog>[log]),
          openUrl: (Uri _) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 印が押されたとき（はじめての場所）と、メダルが正面を向いたとき（解除）に振動する
    expect(
      calls.where((String c) => c == 'heavyImpact').length,
      greaterThanOrEqualTo(2),
    );

    // オフにすると、祝う画面でも振動しない
    calls.clear();
    Haptics.enabled = false;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: CheckinCelebrationScreen(
          log: log,
          openUrl: (Uri _) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });
}
