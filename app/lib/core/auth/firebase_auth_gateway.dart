import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../firebase_options.dart';
import '../api/uramichi_api.dart';
import 'auth_gateway.dart';
import '../strings.dart';

/// Firebase Authentication で Google アカウントにログインする
///
/// Web 版は Firebase のポップアップでログインする。signInWithRedirect は、サードパーティの
/// ストレージをブロックするブラウザで動かず、web.app で公開する場合は authDomain の変更も必要になるため使わない。
/// Android 版は google_sign_in（Credential Manager）で ID トークンを受け取り、Firebase に渡す。
class FirebaseAuthGateway implements AuthGateway {
  FirebaseAuthGateway({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Future<void>? _googleSignInReady;

  static AuthUser? _toAuthUser(User? user) => user == null || user.isAnonymous
      ? null
      : AuthUser(uid: user.uid, email: user.email);

  @override
  Future<AuthUser?> currentUser() async {
    // Web 版は前回のログインを非同期で復元するため、最初の通知を待ってから確かめる
    final User? user = await _auth.authStateChanges().first;
    if (user != null && user.isAnonymous) {
      // 以前の版が匿名でログインした記録は引き継がず、Google アカウントでログインし直してもらう
      await _auth.signOut();
      return null;
    }
    return _toAuthUser(user);
  }

  @override
  Future<AuthUser?> signIn() async {
    try {
      final UserCredential credential = kIsWeb
          ? await _auth.signInWithPopup(GoogleAuthProvider())
          : await _signInOnDevice();
      return _toAuthUser(credential.user);
    } on _Canceled {
      return null;
    } on FirebaseAuthException catch (error) {
      return switch (error.code) {
        'popup-closed-by-user' || 'cancelled-popup-request' => null,
        'popup-blocked' => throw AuthFailure(l10n.errorLoginPopup),
        'network-request-failed' => throw AuthFailure(l10n.errorLoginNetwork),
        _ => throw AuthFailure(l10n.errorLoginCode(error.code)),
      };
    }
  }

  Future<UserCredential> _signInOnDevice() async {
    final GoogleSignIn google = GoogleSignIn.instance;
    // initialize は1回だけ呼ぶ必要がある
    final String? webClientId = await DefaultFirebaseOptions.loadWebClientId();
    await (_googleSignInReady ??= google.initialize(
      serverClientId: webClientId,
    ));
    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        throw const _Canceled();
      }
      throw AuthFailure(l10n.errorLoginCode(error.code.name));
    }
    return _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: account.authentication.idToken),
    );
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb && _googleSignInReady != null) {
      // 次のログインでアカウントを選び直せるよう、端末の Google ログインも終える
      await GoogleSignIn.instance.signOut();
    }
  }

  @override
  Future<String> idToken() => _tokenOf(_auth.currentUser);

  @override
  Future<String> idTokenFor(String uid) {
    final User? user = _auth.currentUser;
    if (user?.uid != uid) {
      throw ApiException.signedOut;
    }
    return _tokenOf(user);
  }

  Future<String> _tokenOf(User? user) async {
    if (user == null || user.isAnonymous) {
      throw ApiException.signedOut;
    }
    try {
      final String? token = await user.getIdToken();
      if (token == null) {
        throw ApiException.signedOut;
      }
      return token;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'network-request-failed') {
        // 通信できないことは API サーバーに接続できないときと同じなので、端末に保存する対象にする
        throw http.ClientException(error.message ?? error.code);
      }
      rethrow;
    }
  }
}

/// 利用者がログインをキャンセルしたこと
class _Canceled implements Exception {
  const _Canceled();
}
