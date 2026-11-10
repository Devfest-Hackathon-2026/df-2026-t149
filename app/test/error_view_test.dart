import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/core/widgets/error_view.dart';

void main() {
  testWidgets('例外の内容を、グレーの四角ではなく文字で見せる', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BuildErrorView(
          details: FlutterErrorDetails(exception: StateError('壊れた値')),
        ),
      ),
    );
    expect(find.text('この部分を表示できませんでした'), findsOneWidget);
    expect(find.textContaining('壊れた値'), findsOneWidget);
  });
}
