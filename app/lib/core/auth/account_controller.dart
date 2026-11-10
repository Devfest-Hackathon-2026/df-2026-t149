import 'package:flutter/foundation.dart';

import '../api/uramichi_api.dart';
import '../data/profile_repository.dart';
import '../models/profile.dart';
import 'auth_gateway.dart';
import '../strings.dart';

/// ログインとプロフィールの状態。アプリを使えるのは [AccountReady] のときだけである
sealed class AccountState {
  const AccountState();
}

/// 起動して、前回のログインを確かめている
class AccountChecking extends AccountState {
  const AccountChecking();
}

/// ログインしていない。[error] は直前のログインに失敗した理由
class AccountSignedOut extends AccountState {
  const AccountSignedOut({this.error});

  final String? error;
}

/// Google アカウントでログインしている途中
class AccountSigningIn extends AccountState {
  const AccountSigningIn();
}

/// ログインして、プロフィールを読んでいる
class AccountLoadingProfile extends AccountState {
  const AccountLoadingProfile(this.user);

  final AuthUser user;
}

/// ログインしたが、プロフィールを読めなかった
class AccountProfileFailed extends AccountState {
  const AccountProfileFailed(this.user, this.message);

  final AuthUser user;
  final String message;
}

/// ログインしたが、まだプロフィールを保存していない
class AccountNeedsProfile extends AccountState {
  const AccountNeedsProfile(this.user);

  final AuthUser user;
}

/// ログインしてプロフィールを保存しており、アプリを使える
class AccountReady extends AccountState {
  const AccountReady(this.user, this.profile);

  final AuthUser user;
  final Profile profile;
}

/// ログインからプロフィールの保存までの状態を管理する
class AccountController extends ChangeNotifier {
  AccountController({
    required AuthGateway auth,
    required ProfileRepository profiles,
    @visibleForTesting AccountState initial = const AccountChecking(),
  }) : _auth = auth,
       _profiles = profiles,
       _state = initial;

  final AuthGateway _auth;
  final ProfileRepository _profiles;

  AccountState _state;
  AccountState get state => _state;

  /// ログインしている利用者。ログインしていないか、確かめている途中なら null
  AuthUser? get user => switch (_state) {
    AccountLoadingProfile(:final AuthUser user) ||
    AccountProfileFailed(:final AuthUser user) ||
    AccountNeedsProfile(:final AuthUser user) ||
    AccountReady(:final AuthUser user) => user,
    AccountChecking() || AccountSignedOut() || AccountSigningIn() => null,
  };

  void _set(AccountState next) {
    _state = next;
    notifyListeners();
  }

  /// 前回からログインしたままか確かめる。アプリの起動時に1回呼ぶ
  Future<void> start() async {
    final AuthUser? user = await _auth.currentUser();
    if (user == null) {
      _set(const AccountSignedOut());
      return;
    }
    await _loadProfile(user);
  }

  Future<void> signIn() async {
    _set(const AccountSigningIn());
    final AuthUser? user;
    try {
      user = await _auth.signIn();
    } on AuthFailure catch (error) {
      _set(AccountSignedOut(error: error.message));
      return;
    }
    if (user == null) {
      _set(const AccountSignedOut());
      return;
    }
    await _loadProfile(user);
  }

  /// プロフィールを読めなかったときに、読み直す
  Future<void> retry() async {
    final AccountState state = _state;
    if (state is AccountProfileFailed) {
      await _loadProfile(state.user);
    }
  }

  Future<void> _loadProfile(AuthUser user) async {
    _set(AccountLoadingProfile(user));
    try {
      final Profile? profile = await _profiles.fetch(user);
      _set(
        profile == null
            ? AccountNeedsProfile(user)
            : AccountReady(user, profile),
      );
    } on ApiException catch (error) {
      _set(AccountProfileFailed(user, error.message));
    } catch (_) {
      _set(AccountProfileFailed(user, l10n.errorProfileLoad));
    }
  }

  /// プロフィールを保存する。保存できなければ例外を投げ、状態は変えない（入力の画面に理由を表示するため）
  Future<void> saveProfile(Profile profile) async {
    final AuthUser? user = switch (_state) {
      AccountNeedsProfile(:final AuthUser user) => user,
      AccountReady(:final AuthUser user) => user,
      _ => null,
    };
    if (user == null) {
      throw StateError('ログインしていないときはプロフィールを保存できない');
    }
    final Profile saved = await _profiles.save(user, profile);
    _set(AccountReady(user, saved));
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _set(const AccountSignedOut());
  }

  /// API サーバーに付ける ID トークン
  Future<String> idToken() => _auth.idToken();
}
