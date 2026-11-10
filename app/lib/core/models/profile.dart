import 'package:flutter/material.dart';
import '../strings.dart';

/// タイムラインで投稿者として表示するニックネームとアイコン。サーバー（GET /api/me）と同じ JSON 形式
///
/// Google アカウントの名前と写真は実名と顔写真の場合があるため使わず、利用者が決めた値だけを表示する
@immutable
class Profile {
  const Profile({required this.nickname, required this.icon});

  factory Profile.fromJson(Map<String, dynamic> j) =>
      Profile(nickname: j['nickname'] as String, icon: j['icon'] as String);

  final String nickname;

  /// [ProfileIcon.id]
  final String icon;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'nickname': nickname,
    'icon': icon,
  };

  /// ニックネームの最大の文字数。サーバーの nicknameMaxLength と同じ値にする
  static const int nicknameMaxLength = 20;

  /// ニックネームの文字数。サーバーと同じく Unicode の文字（コードポイント）の単位で数える
  static int nicknameLength(String text) => text.trim().runes.length;

  /// 保存できるニックネームなら前後の空白を除いて返し、保存できなければ null を返す
  static String? normalizeNickname(String text) {
    final String trimmed = text.trim();
    final int length = nicknameLength(trimmed);
    if (length == 0 || length > nicknameMaxLength) {
      return null;
    }
    if (trimmed.contains(RegExp(r'[\u0000-\u001F\u007F]'))) {
      return null;
    }
    return trimmed;
  }

  @override
  bool operator ==(Object other) =>
      other is Profile && other.nickname == nickname && other.icon == icon;

  @override
  int get hashCode => Object.hash(nickname, icon);
}

/// プロフィールで選べるアイコン。散策と旅に関係する絵から選ぶ
enum ProfileIcon {
  hiking('hiking', Icons.hiking),
  pets('pets', Icons.pets),
  cafe('local_cafe', Icons.local_cafe),
  ramen('ramen_dining', Icons.ramen_dining),
  camera('photo_camera', Icons.photo_camera),
  bike('directions_bike', Icons.directions_bike),
  train('train', Icons.train),
  leaf('eco', Icons.eco),
  mountain('landscape', Icons.landscape),
  waves('waves', Icons.waves),
  temple('temple_buddhist', Icons.temple_buddhist),
  tree('park', Icons.park);

  const ProfileIcon(this.id, this.icon);

  /// サーバーに保存する ID
  final String id;
  final IconData icon;

  /// 読み上げとツールチップで伝える名前
  String get label => switch (this) {
    hiking => l10n.iconHiking,
    pets => l10n.iconPets,
    cafe => l10n.iconCafe,
    ramen => l10n.iconRamen,
    camera => l10n.iconCamera,
    bike => l10n.iconBike,
    train => l10n.iconTrain,
    leaf => l10n.iconLeaf,
    mountain => l10n.iconMountain,
    waves => l10n.iconWaves,
    temple => l10n.iconTemple,
    tree => l10n.iconTree,
  };

  /// 知らない ID（新しい版のアプリで追加したアイコンなど）は最初のアイコンとして表示する
  static ProfileIcon of(String id) => values.firstWhere(
    (ProfileIcon icon) => icon.id == id,
    orElse: () => values.first,
  );
}
