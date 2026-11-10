import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uramichi/core/api/uramichi_api.dart';
import 'package:uramichi/core/auth/account_controller.dart';
import 'package:uramichi/core/auth/auth_gateway.dart';
import 'package:uramichi/core/data/profile_repository.dart';
import 'package:uramichi/core/models/profile.dart';

import 'fake_account.dart';

void main() {
  group('ログインの状態', () {
    test('ログインしていなければ、ログインを求める', () async {
      final AccountController account = AccountController(
        auth: FakeAuthGateway(),
        profiles: FakeProfileRepository(),
      );
      expect(account.state, isA<AccountChecking>());
      await account.start();
      expect(account.state, isA<AccountSignedOut>());
      expect((account.state as AccountSignedOut).error, isNull);
    });

    test('初めてログインした人には、プロフィールの入力を求め、保存すると使える', () async {
      final FakeProfileRepository profiles = FakeProfileRepository();
      final AccountController account = AccountController(
        auth: FakeAuthGateway(),
        profiles: profiles,
      );
      await account.start();
      await account.signIn();
      expect(account.state, isA<AccountNeedsProfile>());

      await account.saveProfile(testProfile);
      expect(account.state, isA<AccountReady>());
      expect((account.state as AccountReady).profile, testProfile);
      expect((account.state as AccountReady).user, testUser);
      expect(profiles.saved, testProfile);
    });

    test('プロフィールを保存済みの人は、ログインするとすぐ使える', () async {
      final AccountController account = AccountController(
        auth: FakeAuthGateway(),
        profiles: FakeProfileRepository(testProfile),
      );
      await account.start();
      await account.signIn();
      expect(account.state, isA<AccountReady>());
    });

    test('前回ログインしたままなら、起動するとすぐ使える', () async {
      final AccountController account = await readyAccount();
      expect(account.state, isA<AccountReady>());
    });

    test('ログインの途中は、ログイン中の状態になる', () async {
      final AccountController account = AccountController(
        auth: FakeAuthGateway(),
        profiles: FakeProfileRepository(testProfile),
      );
      await account.start();
      final List<Type> seen = <Type>[];
      account.addListener(() => seen.add(account.state.runtimeType));
      await account.signIn();
      expect(seen.first, AccountSigningIn);
      expect(seen.last, AccountReady);
    });

    test('ログインをキャンセルしたら、エラーを出さずにログインを求める', () async {
      final FakeAuthGateway auth = FakeAuthGateway()..nextUser = null;
      final AccountController account = AccountController(
        auth: auth,
        profiles: FakeProfileRepository(),
      );
      await account.start();
      await account.signIn();
      expect(account.state, isA<AccountSignedOut>());
      expect((account.state as AccountSignedOut).error, isNull);
    });

    test('ログインに失敗したら、理由を添えてログインを求める', () async {
      final FakeAuthGateway auth = FakeAuthGateway()
        ..nextError = const AuthFailure('ログインできませんでした');
      final AccountController account = AccountController(
        auth: auth,
        profiles: FakeProfileRepository(),
      );
      await account.start();
      await account.signIn();
      expect(account.state, isA<AccountSignedOut>());
      expect((account.state as AccountSignedOut).error, 'ログインできませんでした');
    });

    test('プロフィールを読めなければ、やり直せる状態にする', () async {
      final FakeProfileRepository profiles = FakeProfileRepository(testProfile)
        ..fetchError = const ApiException(500, 'internal', 'サーバーでエラーが起きました');
      final AccountController account = AccountController(
        auth: FakeAuthGateway(current: testUser),
        profiles: profiles,
      );
      await account.start();
      expect(account.state, isA<AccountProfileFailed>());

      await account.retry();
      expect(account.state, isA<AccountReady>());
    });

    test('プロフィールを保存できなければ、入力を続けられるようエラーを投げ、状態を変えない', () async {
      final FakeProfileRepository profiles = FakeProfileRepository()
        ..saveError = const ApiException(
          400,
          'bad_request',
          'ニックネームは1〜20文字で入力してください',
        );
      final AccountController account = AccountController(
        auth: FakeAuthGateway(current: testUser),
        profiles: profiles,
      );
      await account.start();
      await expectLater(
        account.saveProfile(testProfile),
        throwsA(isA<ApiException>()),
      );
      expect(account.state, isA<AccountNeedsProfile>());
    });

    test('使える状態でプロフィールを変更すると、新しいプロフィールになる', () async {
      final AccountController account = await readyAccount();
      const Profile changed = Profile(nickname: 'たろう', icon: 'pets');
      await account.saveProfile(changed);
      expect((account.state as AccountReady).profile, changed);
    });

    test('ログアウトすると、ログインを求める', () async {
      final FakeAuthGateway auth = FakeAuthGateway(current: testUser);
      final AccountController account = AccountController(
        auth: auth,
        profiles: FakeProfileRepository(testProfile),
      );
      await account.start();
      await account.signOut();
      expect(account.state, isA<AccountSignedOut>());
      expect(auth.signOutCalls, 1);
    });
  });

  group('ニックネーム', () {
    test('前後の空白を除いた1〜20文字を受け付ける', () {
      expect(Profile.normalizeNickname('  路地裏の旅人  '), '路地裏の旅人');
      expect(Profile.normalizeNickname('あ' * 20), 'あ' * 20);
    });

    test('空、21文字以上、改行を含むものは受け付けない', () {
      expect(Profile.normalizeNickname(''), isNull);
      expect(Profile.normalizeNickname('   '), isNull);
      expect(Profile.normalizeNickname('あ' * 21), isNull);
      expect(Profile.normalizeNickname('二行\nの名前'), isNull);
    });

    test('文字数は、サーバーと同じく Unicode の文字単位で数える', () {
      expect(Profile.nicknameLength('😀たろう'), 4);
    });
  });

  group('アイコン', () {
    test('12種類から選べ、ID はサーバーが受け付ける形である', () {
      expect(ProfileIcon.values, hasLength(12));
      final RegExp idPattern = RegExp(r'^[a-z0-9_]{1,32}$');
      for (final ProfileIcon icon in ProfileIcon.values) {
        expect(idPattern.hasMatch(icon.id), isTrue, reason: icon.id);
      }
    });

    test('知らない ID は最初のアイコンとして表示する', () {
      expect(ProfileIcon.of('unknown'), ProfileIcon.values.first);
      expect(ProfileIcon.of('pets'), ProfileIcon.pets);
    });
  });

  group('プロフィールの JSON', () {
    test('サーバーの形と相互に変換できる', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'nickname': 'たろう',
        'icon': 'hiking',
      };
      expect(
        Profile.fromJson(json),
        const Profile(nickname: 'たろう', icon: 'hiking'),
      );
      expect(const Profile(nickname: 'たろう', icon: 'hiking').toJson(), json);
    });
  });

  group('プロフィールの保存先', () {
    UramichiApi api(Future<http.Response> Function(http.Request) handler) =>
        UramichiApi(baseUrl: 'http://test', client: MockClient(handler));

    http.Response json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );

    test('通信できないときは、最後に読めた本人のプロフィールを返す', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      bool offline = false;
      final ApiProfileRepository repo = ApiProfileRepository(
        api: api((http.Request r) async {
          if (offline) {
            throw http.ClientException('offline');
          }
          return json(<String, Object>{'profile': testProfile.toJson()});
        }),
        idToken: () async => 'tok',
        prefs: prefs,
      );
      expect(await repo.fetch(testUser), testProfile);

      offline = true;
      expect(await repo.fetch(testUser), testProfile);
      await expectLater(
        repo.fetch(const AuthUser(uid: 'someone-else')),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('サーバーの処理の失敗は、端末に残したプロフィールで隠さない', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'profile.u1': jsonEncode(testProfile.toJson()),
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ApiProfileRepository repo = ApiProfileRepository(
        api: api(
          (http.Request r) async =>
              http.Response('{"error":{"code":"internal","message":"x"}}', 500),
        ),
        idToken: () async => 'tok',
        prefs: prefs,
      );
      await expectLater(repo.fetch(testUser), throwsA(isA<ApiException>()));
    });
  });
}
