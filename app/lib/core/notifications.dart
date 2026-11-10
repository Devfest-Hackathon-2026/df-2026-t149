import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'geo.dart';

/// 端末の通知。スマホ（Android・iOS）だけで使い、Web では出さない。
///
/// Web 版の通知の部品は Flutter の Service Worker を差し替えるため、Firebase Hosting の配信と合わせて確かめるまでは使わない
abstract final class AppNotifications {
  /// 通知を出すか（設定の「通知」）。バックグラウンドの処理からも読むため、端末に保存する
  static const String enabledKey = 'notifications';

  static const String _stayNotifiedKey = 'stayNotifiedAt';
  static const String _reactionTotalKey = 'reactionTotal';

  static const int _stayId = 1;
  static const int _reactionId = 2;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static Future<bool>? _ready;

  /// 通知を出せる端末か
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool enabled(SharedPreferences prefs) =>
      prefs.getBool(enabledKey) ?? true;

  /// 通知の部品を準備する。何度呼んでもよい（バックグラウンドの isolate からも呼ぶ）
  static Future<bool> init() => _ready ??= _init();

  static Future<bool> _init() async {
    if (!supported) {
      return false;
    }
    try {
      return await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              // 許可は設定で通知をオンにしたとき（requestPermission）に聞く
              iOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
            ),
          ) ??
          false;
    } catch (error) {
      debugPrint('通知を準備できません: $error');
      return false;
    }
  }

  /// 通知の許可を聞く（Android 13 以降と iOS）。許可されれば true
  static Future<bool> requestPermission() async {
    if (!await init()) {
      return false;
    }
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false;
      }
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
    } catch (error) {
      debugPrint('通知の許可を聞けません: $error');
      return false;
    }
  }

  static Future<void> _show(
    int id,
    String title,
    String body, {
    required String channelId,
    required String channelName,
  }) async {
    if (!await init()) {
      return;
    }
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(channelId, channelName),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (error) {
      debugPrint('通知を出せません: $error');
    }
  }

  /// 同じ場所での滞在を通知したのは、この時間より前ならもう一度知らせる
  static const Duration stayRenotifyAfter = Duration(hours: 6);

  /// 滞在を見つけたときに、記録をうながす。同じ場所には [stayRenotifyAfter] の間に1回だけ知らせる
  static Future<void> notifyStay(
    SharedPreferences prefs, {
    required double lat,
    required double lng,
    required DateTime now,
    required String title,
    required String body,
    required String channelName,
  }) async {
    if (!enabled(prefs)) {
      return;
    }
    final List<String>? last = prefs.getStringList(_stayNotifiedKey);
    if (last != null && last.length == 3) {
      final double? lastLat = double.tryParse(last[0]);
      final double? lastLng = double.tryParse(last[1]);
      final DateTime? at = DateTime.tryParse(last[2]);
      if (lastLat != null &&
          lastLng != null &&
          at != null &&
          now.difference(at) < stayRenotifyAfter &&
          distanceMeters(lastLat, lastLng, lat, lng) < 300) {
        return;
      }
    }
    await prefs.setStringList(_stayNotifiedKey, <String>[
      '$lat',
      '$lng',
      now.toIso8601String(),
    ]);
    await _show(
      _stayId,
      title,
      body,
      channelId: 'stay',
      channelName: channelName,
    );
  }

  /// 自分の口コミへの反応の合計が前に見たときより増えていれば、増えた数を返して覚え直す。
  /// はじめて数えたときは、これまでの反応を新しい反応として知らせないよう 0 を返す
  static Future<int> takeNewReactions(
    SharedPreferences prefs,
    int total,
  ) async {
    final int? before = prefs.getInt(_reactionTotalKey);
    if (before != total) {
      await prefs.setInt(_reactionTotalKey, total);
    }
    return before == null ? 0 : (total - before).clamp(0, total);
  }

  /// 自分の口コミに反応が付いたことを知らせる
  static Future<void> notifyReactions(
    SharedPreferences prefs, {
    required String title,
    required String body,
    required String channelName,
  }) async {
    if (!enabled(prefs)) {
      return;
    }
    await _show(
      _reactionId,
      title,
      body,
      channelId: 'reactions',
      channelName: channelName,
    );
  }
}
