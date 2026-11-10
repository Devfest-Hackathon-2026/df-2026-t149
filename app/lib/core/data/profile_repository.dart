import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/uramichi_api.dart';
import '../auth/auth_gateway.dart';
import '../models/profile.dart';

/// 自分のプロフィールの保存先。画面からは [AccountController] を通して使う
abstract interface class ProfileRepository {
  /// [user] のプロフィール。まだ保存していなければ null を返す
  Future<Profile?> fetch(AuthUser user);

  Future<Profile> save(AuthUser user, Profile profile);
}

/// API サーバー（GET /api/me と PUT /api/me）に保存する
///
/// 最後に読めたプロフィールを端末にも残し、通信できないときはそれを返す。
/// 圏外で起動してもアプリを使え、チェックインを端末に保存できるようにするため
class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository({
    required this.api,
    required this.idToken,
    required this.prefs,
  });

  final UramichiApi api;
  final Future<String> Function() idToken;
  final SharedPreferences prefs;

  static String _cacheKey(AuthUser user) => 'profile.${user.uid}';

  @override
  Future<Profile?> fetch(AuthUser user) async {
    try {
      final Profile? profile = await api.fetchProfile(idToken: await idToken());
      await _remember(user, profile);
      return profile;
    } catch (error) {
      final String? cached = prefs.getString(_cacheKey(user));
      if (cached != null && UramichiApi.isUnavailable(error)) {
        return Profile.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      }
      rethrow;
    }
  }

  @override
  Future<Profile> save(AuthUser user, Profile profile) async {
    final Profile saved = await api.saveProfile(
      profile,
      idToken: await idToken(),
    );
    await _remember(user, saved);
    return saved;
  }

  Future<void> _remember(AuthUser user, Profile? profile) async {
    if (profile == null) {
      await prefs.remove(_cacheKey(user));
    } else {
      await prefs.setString(_cacheKey(user), jsonEncode(profile.toJson()));
    }
  }
}

/// API サーバーがない開発中のビルドで、端末だけに保存する
class LocalProfileRepository implements ProfileRepository {
  LocalProfileRepository({required this.prefs});

  final SharedPreferences prefs;

  static String _key(AuthUser user) => 'profile.${user.uid}';

  @override
  Future<Profile?> fetch(AuthUser user) async {
    final String? raw = prefs.getString(_key(user));
    return raw == null
        ? null
        : Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<Profile> save(AuthUser user, Profile profile) async {
    await prefs.setString(_key(user), jsonEncode(profile.toJson()));
    return profile;
  }
}
