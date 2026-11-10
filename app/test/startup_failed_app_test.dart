import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/startup_failed_app.dart';

void main() {
  testWidgets('Firebase を初期化できないときは、ログインの画面ではなく、やり直す操作を示す', (
    WidgetTester tester,
  ) async {
    final Completer<void> retry = Completer<void>();
    int retries = 0;
    await tester.pumpWidget(
      StartupFailedApp(
        onRetry: () {
          retries++;
          return retry.future;
        },
      ),
    );

    expect(find.text('ログインを準備できませんでした'), findsOneWidget);
    expect(find.textContaining('Google でログイン'), findsNothing);

    await tester.tap(find.text('もう一度試す'));
    await tester.pump();
    expect(retries, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    retry.complete();
    await tester.pumpAndSettle();
    expect(find.text('もう一度試す'), findsOneWidget);
  });
}
