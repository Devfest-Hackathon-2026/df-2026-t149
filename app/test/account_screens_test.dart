import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/core/api/uramichi_api.dart';
import 'package:uramichi/core/auth/account_controller.dart';
import 'package:uramichi/core/auth/auth_gateway.dart';
import 'package:uramichi/core/theme.dart';
import 'package:uramichi/features/account/account_gate.dart';

import 'fake_account.dart';

Widget _gate(AccountController account) => MaterialApp(
  theme: AppTheme.light(),
  home: AccountGate(
    account: account,
    child: const Scaffold(body: Text('ホームの画面')),
  ),
);

void main() {
  testWidgets('ログインして、ニックネームとアイコンを決めるまでアプリを使えない', (tester) async {
    final FakeProfileRepository profiles = FakeProfileRepository();
    final AccountController account = AccountController(
      auth: FakeAuthGateway(),
      profiles: profiles,
    );
    await account.start();
    await tester.pumpWidget(_gate(account));

    expect(find.text('ホームの画面'), findsNothing);
    await tester.tap(find.text('Google でログイン'));
    await tester.pumpAndSettle();

    expect(find.text('ホームの画面'), findsNothing);
    final Finder start = find.widgetWithText(FilledButton, 'はじめる');
    expect(tester.widget<FilledButton>(start).onPressed, isNull);

    // Google アカウントの名前を初期値にしない
    expect(find.text('uramichi.taro@gmail.com'), findsNothing);
    await tester.enterText(find.byType(TextField), '  路地裏の旅人 ');
    await tester.tap(find.byTooltip('足あと'));
    await tester.pump();
    expect(find.text('6/20'), findsOneWidget);
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);

    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.text('ホームの画面'), findsOneWidget);
    expect(profiles.saved?.nickname, '路地裏の旅人');
    expect(profiles.saved?.icon, 'pets');
  });

  testWidgets('ログインに失敗したら、理由を表示し、もう一度ログインできる', (tester) async {
    final FakeAuthGateway auth = FakeAuthGateway()
      ..nextError = const AuthFailure('ログインできませんでした。通信を確かめて、もう一度お試しください');
    final AccountController account = AccountController(
      auth: auth,
      profiles: FakeProfileRepository(testProfile),
    );
    await account.start();
    await tester.pumpWidget(_gate(account));

    await tester.tap(find.text('Google でログイン'));
    await tester.pumpAndSettle();
    expect(find.text('ログインできませんでした。通信を確かめて、もう一度お試しください'), findsOneWidget);

    auth.nextError = null;
    await tester.tap(find.text('Google でログイン'));
    await tester.pumpAndSettle();
    expect(find.text('ホームの画面'), findsOneWidget);
  });

  testWidgets('プロフィールを保存できなければ、入力を残したまま理由を表示する', (tester) async {
    final FakeProfileRepository profiles = FakeProfileRepository()
      ..saveError = const ApiException(500, 'internal', 'プロフィールを保存できませんでした');
    final AccountController account = AccountController(
      auth: FakeAuthGateway(current: testUser),
      profiles: profiles,
    );
    await account.start();
    await tester.pumpWidget(_gate(account));

    await tester.enterText(find.byType(TextField), 'たろう');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'はじめる'));
    await tester.pumpAndSettle();
    expect(find.text('プロフィールを保存できませんでした'), findsOneWidget);
    expect(find.text('たろう'), findsWidgets);
    expect(find.text('ホームの画面'), findsNothing);
  });

  testWidgets('プロフィールを読めなければ、読み直すかログアウトできる', (tester) async {
    final FakeProfileRepository profiles = FakeProfileRepository(testProfile)
      ..fetchError = const ApiException(500, 'internal', 'プロフィールを読めませんでした');
    final AccountController account = AccountController(
      auth: FakeAuthGateway(current: testUser),
      profiles: profiles,
    );
    await account.start();
    await tester.pumpWidget(_gate(account));

    expect(find.text('プロフィールを読めませんでした'), findsOneWidget);
    expect(find.text('ログアウト'), findsOneWidget);
    await tester.tap(find.text('もう一度読み込む'));
    await tester.pumpAndSettle();
    expect(find.text('ホームの画面'), findsOneWidget);
  });

  testWidgets('ログアウトすると、ログインの画面に戻る', (tester) async {
    final AccountController account = await readyAccount();
    await tester.pumpWidget(_gate(account));
    expect(find.text('ホームの画面'), findsOneWidget);

    await account.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Google でログイン'), findsOneWidget);
  });
}
