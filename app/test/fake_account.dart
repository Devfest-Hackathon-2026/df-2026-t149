import 'package:uramichi/core/api/uramichi_api.dart';
import 'package:uramichi/core/auth/account_controller.dart';
import 'package:uramichi/core/auth/auth_gateway.dart';
import 'package:uramichi/core/data/profile_repository.dart';
import 'package:uramichi/core/models/profile.dart';

const AuthUser testUser = AuthUser(uid: 'u1', email: 'uramichi.taro@gmail.com');

/// テストで使う Google アカウントのログイン。結果を差し替えられる
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({this.current});

  AuthUser? current;

  /// 次の signIn の結果。null ならキャンセルされたことにする
  AuthUser? nextUser = testUser;

  /// 次の signIn で投げるエラー
  Object? nextError;

  int signOutCalls = 0;

  @override
  Future<AuthUser?> currentUser() async => current;

  @override
  Future<AuthUser?> signIn() async {
    final Object? error = nextError;
    if (error != null) {
      throw error;
    }
    current = nextUser;
    return current;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    current = null;
  }

  @override
  Future<String> idToken() async => current?.uid ?? '';

  @override
  Future<String> idTokenFor(String uid) async {
    if (current?.uid != uid) {
      throw ApiException.signedOut;
    }
    return uid;
  }
}

/// テストで使うプロフィールの保存先
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository([this.saved]);

  Profile? saved;

  /// 次の fetch で投げるエラー
  Object? fetchError;

  /// 次の save で投げるエラー
  Object? saveError;

  @override
  Future<Profile?> fetch(AuthUser user) async {
    final Object? error = fetchError;
    if (error != null) {
      fetchError = null;
      throw error;
    }
    return saved;
  }

  @override
  Future<Profile> save(AuthUser user, Profile profile) async {
    final Object? error = saveError;
    if (error != null) {
      saveError = null;
      throw error;
    }
    return saved = profile;
  }
}

const Profile testProfile = Profile(nickname: '路地裏の旅人', icon: 'hiking');

/// ログインしてプロフィールを保存した状態のアカウント
Future<AccountController> readyAccount({Profile profile = testProfile}) async {
  final AccountController account = AccountController(
    auth: FakeAuthGateway(current: testUser),
    profiles: FakeProfileRepository(profile),
  );
  await account.start();
  return account;
}

/// ログインしてプロフィールを保存した状態から始まるアカウント。最初の描画からアプリの画面を表示する
AccountController readyAccountNow({Profile profile = testProfile}) =>
    AccountController(
      auth: FakeAuthGateway(current: testUser),
      profiles: FakeProfileRepository(profile),
      initial: AccountReady(testUser, profile),
    );
