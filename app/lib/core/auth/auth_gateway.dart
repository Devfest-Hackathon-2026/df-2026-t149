import 'package:flutter/foundation.dart';

import '../api/uramichi_api.dart';

/// ログインしている Google アカウント
@immutable
class AuthUser {
  const AuthUser({required this.uid, this.email});

  final String uid;

  /// 設定の画面で、どのアカウントでログインしているかを示すために使う。タイムラインには表示しない
  final String? email;

  @override
  bool operator ==(Object other) =>
      other is AuthUser && other.uid == uid && other.email == email;

  @override
  int get hashCode => Object.hash(uid, email);
}

/// ログインに失敗したこと。[message] は利用者に見せてよい日本語の文
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => 'AuthFailure: $message';
}

/// Google アカウントでのログイン。画面からは [AccountController] を通して使う
abstract interface class AuthGateway {
  /// 前回からログインしたままのアカウント。ログインしていなければ null
  Future<AuthUser?> currentUser();

  /// Google アカウントでログインする。利用者がキャンセルしたら null を返し、失敗したら [AuthFailure] を投げる
  Future<AuthUser?> signIn();

  Future<void> signOut();

  /// API サーバーに付ける ID トークン
  Future<String> idToken();

  /// [uid] の利用者がログインしているときだけ、その利用者の ID トークンを返す。
  /// 別の利用者がログインしているか、ログインしていなければ 401 の [ApiException] を投げる
  Future<String> idTokenFor(String uid);
}

/// Firebase を設定していない開発中のビルドで使うログイン。ボタンを押すとすぐにログインした扱いになる
///
/// AUTH_MODE=fake のサーバーは、ID トークンの文字列をそのまま uid として受け取る
class LocalAuthGateway implements AuthGateway {
  static const AuthUser _user = AuthUser(uid: 'local-dev');

  AuthUser? _current;

  @override
  Future<AuthUser?> currentUser() async => _current;

  @override
  Future<AuthUser?> signIn() async => _current = _user;

  @override
  Future<void> signOut() async => _current = null;

  @override
  Future<String> idToken() async => _user.uid;

  @override
  Future<String> idTokenFor(String uid) async {
    if (_current?.uid != uid) {
      throw ApiException.signedOut;
    }
    return uid;
  }
}
