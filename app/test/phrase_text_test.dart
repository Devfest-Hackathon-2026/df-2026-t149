import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/core/widgets/phrase_text.dart';

void main() {
  testWidgets('文節の境界で折り返し、読み上げには元の文章を渡す', (tester) async {
    const text = '今日はいい天気ですね。';
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox(width: 100, child: PhraseText(text))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Wrap), findsOneWidget);
    expect(find.bySemanticsLabel(text), findsOneWidget);
    final segments = find.descendant(
      of: find.byType(Wrap),
      matching: find.byType(Text),
    );
    expect(segments.evaluate().length, greaterThan(1));
    expect(
      tester.getTopLeft(segments.first).dy,
      lessThan(tester.getTopLeft(segments.last).dy),
    );
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('絵文字を含む文章は文字を壊さずに表示する', (tester) async {
    const text = '散歩に行こう🌱';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox(width: 80, child: PhraseText(text))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(text), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
