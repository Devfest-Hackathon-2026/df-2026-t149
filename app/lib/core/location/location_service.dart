import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../notifications.dart';
import '../strings.dart';
import 'background_samples.dart';
import 'stay_detector.dart';

/// 位置情報の測定値 1 件
@immutable
class GeoSample {
  const GeoSample({
    required this.lat,
    required this.lng,
    required this.accuracyMeters,
    required this.at,
  });

  final double lat;
  final double lng;
  final double accuracyMeters;
  final DateTime at;
}

/// 位置情報を使えるかどうか
enum LocationAccess {
  granted,
  denied,
  deniedForever,
  serviceOff,

  /// アプリの使用中は使えるが、アプリを閉じている間の記録に必要な「常に許可」がない
  backgroundNeeded,
}

/// 端末の位置情報を読む窓口。画面と記録の処理はこのインターフェースだけを使う
abstract class LocationService {
  /// アプリを閉じている間も位置情報を記録できる端末か
  bool get canTrack;

  /// 位置情報を使えるかを返す。[ask] が true なら、まだ許可されていないときに許可を求める
  Future<LocationAccess> requestAccess({bool ask = true});

  /// アプリを閉じている間の記録に使えるかを返す。[ask] が true なら、まだ許可されていないときに許可を求める
  Future<LocationAccess> requestBackgroundAccess({bool ask = true});

  /// 現在地を返す。測定できないときは例外を投げる
  Future<GeoSample> current();

  /// アプリを閉じていても定期的に測定する処理を始める。すでに動いていれば何もしない
  Future<void> startBackground();

  Future<void> stopBackground();

  /// 端末の設定の画面を開く。[LocationAccess.serviceOff] のときは位置情報の設定を開く
  Future<void> openSettings(LocationAccess access);
}

/// geolocator で端末の位置情報を読む版
class DeviceLocationService implements LocationService {
  /// 測定の間隔。WorkManager の定期実行の下限であり、Android の省電力機能でさらに空くことがある
  static const Duration backgroundInterval = Duration(minutes: 15);

  static const String _taskName = 'uramichi-visit-sample';

  @override
  bool get canTrack =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<LocationAccess> requestAccess({bool ask = true}) async {
    if (kIsWeb) {
      return _requestWebAccess();
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (ask && permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.whileInUse ||
      LocationPermission.always => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      LocationPermission.denied ||
      LocationPermission.unableToDetermine => LocationAccess.denied,
    };
  }

  /// Web 版の許可。geolocator の Web 版の requestPermission は、内部で位置を一度測り、
  /// 時間切れなどで測れないだけでも「拒否された」と返すため使わない。
  /// 許可を求める画面はブラウザに任せ、位置を読む（[current]）ときに出してもらう。
  /// 許可の状態を確かめられないブラウザ（Permissions API のない Safari など）では、読んでみることにする
  Future<LocationAccess> _requestWebAccess() async {
    try {
      final LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        return LocationAccess.deniedForever;
      }
    } catch (error) {
      debugPrint('ブラウザの位置情報の許可を確かめられません: $error');
    }
    return LocationAccess.granted;
  }

  // Android 11 以降は「常に許可」をダイアログで選べず、設定の画面で選ぶ
  @override
  Future<LocationAccess> requestBackgroundAccess({bool ask = true}) async {
    final LocationAccess access = await requestAccess(ask: ask);
    if (access != LocationAccess.granted) {
      return access;
    }
    if (ask &&
        await Geolocator.checkPermission() != LocationPermission.always) {
      try {
        await Geolocator.requestPermission();
      } on PermissionRequestInProgressException catch (error) {
        debugPrint('位置情報の許可を求められません: $error');
      }
    }
    return await Geolocator.checkPermission() == LocationPermission.always
        ? LocationAccess.granted
        : LocationAccess.backgroundNeeded;
  }

  /// 直前の測定値をそのまま使える新しさと精度。GPS を測り直すと数秒かかり、画面を開くたびに待たせるため
  static const Duration _reuseWithin = Duration(minutes: 1);
  static const double _reuseAccuracyMeters = 50;

  @override
  Future<GeoSample> current() async {
    if (kIsWeb) {
      return _currentOnWeb();
    }
    final Position? recent = await Geolocator.getLastKnownPosition();
    if (recent != null &&
        recent.accuracy <= _reuseAccuracyMeters &&
        DateTime.now().difference(recent.timestamp).abs() < _reuseWithin) {
      return _sample(recent);
    }
    try {
      return _sample(
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        ),
      );
    } on TimeoutException {
      // 屋内で GPS が届かなくても、直前の測定値があればスポットの候補を出せる
      final Position? last = await Geolocator.getLastKnownPosition();
      if (last == null) {
        rethrow;
      }
      return _sample(last);
    }
  }

  /// Web 版の現在地。パソコンには GPS がなく、高い精度では時間切れになりやすいので、
  /// まず高い精度で短く待ち、測れなければ精度を落として、少し前の測定値も使う
  Future<GeoSample> _currentOnWeb() async {
    try {
      return _sample(
        await Geolocator.getCurrentPosition(
          locationSettings: WebSettings(
            accuracy: LocationAccuracy.high,
            maximumAge: const Duration(minutes: 1),
            timeLimit: const Duration(seconds: 8),
          ),
        ),
      );
    } on PermissionDeniedException {
      rethrow;
    } catch (error) {
      debugPrint('高い精度で現在地を測れないので、精度を落とします: $error');
      return _sample(
        await Geolocator.getCurrentPosition(
          locationSettings: WebSettings(
            accuracy: LocationAccuracy.low,
            maximumAge: const Duration(minutes: 10),
            timeLimit: const Duration(seconds: 20),
          ),
        ),
      );
    }
  }

  // 通知付きのフォアグラウンドサービスなら間隔を短くできるが、記録中は通知を消せないため使わない
  @override
  Future<void> startBackground() async {
    await Workmanager().initialize(visitSampleDispatcher);
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: backgroundInterval,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  @override
  Future<void> stopBackground() async {
    await Workmanager().initialize(visitSampleDispatcher);
    await Workmanager().cancelByUniqueName(_taskName);
  }

  @override
  Future<void> openSettings(LocationAccess access) async {
    if (access == LocationAccess.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  static GeoSample _sample(Position p) => GeoSample(
    lat: p.latitude,
    lng: p.longitude,
    accuracyMeters: p.accuracy,
    at: p.timestamp.toLocal(),
  );
}

/// WorkManager が別の isolate で呼ぶ入口。測定値を1件保存する
@pragma('vm:entry-point')
void visitSampleDispatcher() {
  Workmanager().executeTask((String _, Map<String, dynamic>? _) async {
    try {
      if (await Geolocator.checkPermission() != LocationPermission.always) {
        return true;
      }
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await appendBackgroundSample(
        prefs,
        DeviceLocationService._sample(position),
      );
      // 同じ場所にしばらくいたら、記録をうながす通知を出す（チェックインはアプリを開いてから）
      if (currentBackgroundStay(readBackgroundSamples(prefs))
          case final Stay stay) {
        await AppNotifications.notifyStay(
          prefs,
          lat: stay.lat,
          lng: stay.lng,
          now: DateTime.now(),
          title: l10n.notifyStayTitle,
          body: l10n.notifyStayBody,
          channelName: l10n.notifyStayChannel,
        );
      }
    } catch (error) {
      // 次の測定で続けられるので、やり直しを頼まずに終える。すぐにやり直すと電池を余計に使う
      debugPrint('バックグラウンドで位置情報を測定できません: $error');
    }
    return true;
  });
}
