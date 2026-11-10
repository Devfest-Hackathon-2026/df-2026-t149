import 'package:flutter/widgets.dart';

import 'api/uramichi_api.dart';
import 'auth/account_controller.dart';
import 'config.dart';
import 'data/checkin_repository.dart';
import 'data/favorites.dart';
import 'location/location_service.dart';
import 'location/visit_recorder.dart';
import 'settings.dart';

/// 画面から API と保存先を取り出すための入れ物。
///
/// 使い方: `final s = Services.of(context); s.api.explore(...)`
class Services extends InheritedWidget {
  const Services({
    super.key,
    required this.api,
    required this.account,
    required this.checkins,
    required this.location,
    required this.visits,
    required this.settings,
    required this.config,
    this.favorites,
    required super.child,
  });

  final UramichiApi api;

  /// ログインとプロフィール。設定の画面で変更とログアウトに使う
  final AccountController account;
  final CheckinRepository checkins;
  final LocationService location;

  /// 行ったかもしれない場所の記録
  final VisitRecorder visits;

  /// テーマとキーカラーの設定
  final AppSettings settings;

  /// assets/config/app_config.json の設定
  final AppConfig config;

  /// お気に入りの場所。null なら★を出さない（部品だけを試すテストなど）
  final FavoritesController? favorites;

  /// [Services] の外（部品だけを試すテストなど）では null
  static Services? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>();

  static Services of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<Services>();
    assert(s != null, 'Services が見つかりません（main.dart で包んでいるか確認）');
    return s!;
  }

  @override
  bool updateShouldNotify(Services oldWidget) =>
      api != oldWidget.api ||
      account != oldWidget.account ||
      checkins != oldWidget.checkins ||
      settings != oldWidget.settings;
}
