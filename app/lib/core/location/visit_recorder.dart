import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../geo.dart';
import 'background_samples.dart';
import 'location_service.dart';
import 'stay_detector.dart';

/// 行ったかもしれない場所 1 件
///
/// 端末に保存するのは位置と時刻だけで、スポットの名前は表示するときに API から受け取る。
/// Google Maps Platform の利用規約が Places API の内容の保存を制限しており、
/// 圏外で記録した滞在も、通信できるようになってから問い合わせればスポットを特定できる
@immutable
class Visit {
  const Visit({
    required this.id,
    required this.lat,
    required this.lng,
    required this.startedAt,
    required this.endedAt,
  });

  factory Visit.fromJson(Map<String, dynamic> j) => Visit(
    id: j['id'] as String,
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    startedAt: DateTime.parse(j['startedAt'] as String),
    endedAt: DateTime.parse(j['endedAt'] as String),
  );

  final String id;
  final double lat;
  final double lng;
  final DateTime startedAt;
  final DateTime endedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'lat': lat,
    'lng': lng,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
  };
}

/// 提案しない地点。[until] が null なら期限なし
@immutable
class _Muted {
  const _Muted(this.lat, this.lng, this.until);

  factory _Muted.fromJson(Map<String, dynamic> j) => _Muted(
    (j['lat'] as num).toDouble(),
    (j['lng'] as num).toDouble(),
    switch (j['until']) {
      final String until => DateTime.parse(until),
      _ => null,
    },
  );

  final double lat;
  final double lng;
  final DateTime? until;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'lat': lat,
    'lng': lng,
    if (until != null) 'until': until!.toIso8601String(),
  };
}

/// 滞在した場所の記録。位置情報を定期的に受け取り、行ったかもしれない場所として端末に保存する
class VisitRecorder extends ChangeNotifier {
  VisitRecorder({
    required LocationService location,
    SharedPreferences? prefs,
    DateTime Function() now = DateTime.now,
  }) : _location = location,
       _prefs = prefs,
       _now = now {
    try {
      _load();
    } catch (error) {
      // 読めない記録のために起動できなくなるよりは、記録を空にして動かす
      debugPrint('滞在の記録を読めませんでした: $error');
    }
  }

  static const String _key = 'visitRecorder';

  /// 位置の履歴を必要以上に持たないよう、これより古い記録は消す
  static const Duration retention = Duration(days: 14);
  static const int maxVisits = 30;

  /// 同じ場所を離れて戻ったときに、1 件の滞在として扱う間隔
  static const Duration mergeGap = Duration(minutes: 30);

  /// チェックインした場所やチェックインしないと答えた場所を、そこにいる間は提案し直さない期間
  static const Duration muteAfterAnswer = Duration(hours: 12);

  final LocationService _location;
  final SharedPreferences? _prefs;
  final DateTime Function() _now;

  bool _enabled = false;
  List<Visit> _visits = <Visit>[];
  List<_Muted> _muted = <_Muted>[];
  StayDetector _detector = StayDetector();

  /// 利用者が記録を頼んだが、設定の画面で「常に許可」を選ぶのを待っている
  bool _awaitingBackgroundAccess = false;

  /// 位置情報を定期的に記録しているか
  bool get enabled => _enabled;

  /// 行ったかもしれない場所（新しい順）
  List<Visit> get visits => List<Visit>.unmodifiable(_visits);

  bool get canTrack => _location.canTrack;

  void _load() {
    final String? raw = _prefs?.getString(_key);
    if (raw == null) {
      return;
    }
    final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;
    final DateTime oldest = _now().subtract(retention);
    _enabled = j['enabled'] as bool? ?? false;
    _visits = <Visit>[
      for (final Object? e
          in j['visits'] as List<Object?>? ?? const <Object?>[])
        Visit.fromJson((e! as Map).cast<String, dynamic>()),
    ].where((Visit v) => v.endedAt.isAfter(oldest)).toList();
    _muted = <_Muted>[
      for (final Object? e in j['muted'] as List<Object?>? ?? const <Object?>[])
        _Muted.fromJson((e! as Map).cast<String, dynamic>()),
    ];
    _detector = StayDetector.fromJson(
      (j['detector'] as Map?)?.cast<String, dynamic>(),
    );
  }

  void _save() {
    final DateTime now = _now();
    _muted.removeWhere((_Muted m) => m.until?.isBefore(now) ?? false);
    _prefs?.setString(
      _key,
      jsonEncode(<String, dynamic>{
        'enabled': _enabled,
        'visits': _visits.map((Visit v) => v.toJson()).toList(),
        'muted': _muted.map((_Muted m) => m.toJson()).toList(),
        'detector': _detector.toJson(),
      }),
    );
  }

  /// 前回の起動で記録を有効にしていれば、続きから記録する
  Future<void> resume() async {
    if (_enabled && _location.canTrack) {
      // 起動しただけで許可の確認を出さない。端末の設定で許可を外した場合は、スイッチの表示も実際の状態に合わせる
      final LocationAccess access = await _location.requestBackgroundAccess(
        ask: false,
      );
      if (access == LocationAccess.granted) {
        await _location.startBackground();
        await _drainBackgroundSamples();
      } else {
        await disable();
      }
    }
  }

  /// アプリに戻ったときに呼ぶ。設定の画面から戻っていれば記録を始め、バックグラウンドの測定値を処理する
  Future<void> refresh() async {
    if (_awaitingBackgroundAccess) {
      final LocationAccess access = await _location.requestBackgroundAccess(
        ask: false,
      );
      if (access == LocationAccess.granted) {
        await _start();
      }
    }
    if (_enabled) {
      await _drainBackgroundSamples();
    }
  }

  Future<void> _drainBackgroundSamples() async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) {
      return;
    }
    // バックグラウンドの isolate が書いた内容は、読み直すまでこの isolate の値に反映されない
    await prefs.reload();
    readBackgroundSamples(prefs).forEach(addSample);
    await prefs.remove(backgroundSamplesKey);
  }

  /// 記録を始める。位置情報を使えないときは始めずに、その理由を返す
  Future<LocationAccess> enable() async {
    final LocationAccess access = await _location.requestBackgroundAccess();
    _awaitingBackgroundAccess = access == LocationAccess.backgroundNeeded;
    if (access == LocationAccess.granted) {
      await _start();
    }
    return access;
  }

  Future<void> _start() async {
    _awaitingBackgroundAccess = false;
    await _location.startBackground();
    _enabled = true;
    _save();
    notifyListeners();
  }

  Future<void> disable() async {
    _enabled = false;
    _awaitingBackgroundAccess = false;
    await _location.stopBackground();
    await _prefs?.remove(backgroundSamplesKey);
    _detector = StayDetector();
    _save();
    notifyListeners();
  }

  /// 記録を止め、端末に保存した滞在と提案しない地点を消す。ログアウトしたときに呼ぶ
  Future<void> clear() async {
    _visits = <Visit>[];
    _muted = <_Muted>[];
    if (_enabled || _awaitingBackgroundAccess) {
      await disable();
      return;
    }
    _detector = StayDetector();
    await _prefs?.remove(backgroundSamplesKey);
    _save();
    notifyListeners();
  }

  /// 測定値を 1 件加える
  void addSample(GeoSample sample) {
    final Stay? stay = _detector.add(sample);
    if (stay != null && !_isMuted(stay.lat, stay.lng)) {
      _upsert(stay);
      notifyListeners();
    }
    _save();
  }

  /// いまの場所を記録する。圏外でスポットを読み込めないときに使う
  void saveCurrent(GeoSample sample) {
    _upsert(
      Stay(
        lat: sample.lat,
        lng: sample.lng,
        startedAt: sample.at,
        endedAt: sample.at,
      ),
    );
    _save();
    notifyListeners();
  }

  /// チェックインしたので、同じ場所を提案しない
  void markCheckedIn(double lat, double lng) {
    _removeNear(lat, lng);
    _mute(lat, lng, _now().add(muteAfterAnswer));
  }

  /// 今回はチェックインしない
  void skip(Visit visit) {
    _visits.removeWhere((Visit v) => v.id == visit.id);
    _mute(visit.lat, visit.lng, _now().add(muteAfterAnswer));
  }

  /// この場所を今後は提案しない。自宅や職場のように、毎日とどまる場所に使う
  void neverSuggest(Visit visit) {
    _removeNear(visit.lat, visit.lng);
    _mute(visit.lat, visit.lng, null);
  }

  void _mute(double lat, double lng, DateTime? until) {
    _muted.add(_Muted(lat, lng, until));
    _save();
    notifyListeners();
  }

  void _removeNear(double lat, double lng) => _visits.removeWhere(
    (Visit v) =>
        distanceMeters(v.lat, v.lng, lat, lng) <= StayDetector.radiusMeters,
  );

  bool _isMuted(double lat, double lng) {
    final DateTime now = _now();
    return _muted.any(
      (_Muted m) =>
          (m.until?.isAfter(now) ?? true) &&
          distanceMeters(m.lat, m.lng, lat, lng) <= StayDetector.radiusMeters,
    );
  }

  void _upsert(Stay stay) {
    final int index = _visits.indexWhere(
      (Visit v) =>
          distanceMeters(v.lat, v.lng, stay.lat, stay.lng) <=
              StayDetector.radiusMeters &&
          !stay.startedAt.isAfter(v.endedAt.add(mergeGap)),
    );
    if (index >= 0) {
      final Visit v = _visits[index];
      _visits[index] = Visit(
        id: v.id,
        lat: v.lat,
        lng: v.lng,
        startedAt: v.startedAt,
        endedAt: stay.endedAt,
      );
      return;
    }
    _visits.insert(
      0,
      Visit(
        id: '${stay.startedAt.millisecondsSinceEpoch}',
        lat: stay.lat,
        lng: stay.lng,
        startedAt: stay.startedAt,
        endedAt: stay.endedAt,
      ),
    );
    if (_visits.length > maxVisits) {
      _visits.removeRange(maxVisits, _visits.length);
    }
  }
}
