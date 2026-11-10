import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'location_service.dart';
import 'stay_detector.dart';

/// バックグラウンドの測定値を一時的に保存するキー。
///
/// バックグラウンドの処理は別の isolate で動くので、滞在の記録本体を両方から書くと、
/// アプリの古い内容で上書きして記録を失う。測定値だけをここに追加し、アプリを開いたときに処理する
const String backgroundSamplesKey = 'visitSamples';

/// 保存する測定値の上限。15 分ごとの測定で約 10 日分
const int maxBackgroundSamples = 1000;

Map<String, Object> _encode(GeoSample s) => <String, Object>{
  'lat': s.lat,
  'lng': s.lng,
  'accuracy': s.accuracyMeters,
  'at': s.at.toIso8601String(),
};

GeoSample _decode(Map<String, dynamic> j) => GeoSample(
  lat: (j['lat'] as num).toDouble(),
  lng: (j['lng'] as num).toDouble(),
  accuracyMeters: (j['accuracy'] as num).toDouble(),
  at: DateTime.parse(j['at'] as String),
);

/// 保存している測定値を古い順に返す。読めない内容は空として扱う
List<GeoSample> readBackgroundSamples(SharedPreferences prefs) {
  final String? raw = prefs.getString(backgroundSamplesKey);
  if (raw == null) {
    return const <GeoSample>[];
  }
  try {
    return <GeoSample>[
      for (final Object? e in jsonDecode(raw) as List<Object?>)
        _decode((e! as Map).cast<String, dynamic>()),
    ];
  } catch (error) {
    debugPrint('バックグラウンドの測定値を読めません: $error');
    return const <GeoSample>[];
  }
}

Future<void> appendBackgroundSample(
  SharedPreferences prefs,
  GeoSample sample,
) async {
  final List<GeoSample> samples = <GeoSample>[
    ...readBackgroundSamples(prefs),
    sample,
  ];
  final int excess = samples.length - maxBackgroundSamples;
  await prefs.setString(
    backgroundSamplesKey,
    jsonEncode(<Map<String, Object>>[
      for (final GeoSample s in excess > 0 ? samples.sublist(excess) : samples)
        _encode(s),
    ]),
  );
}

/// バックグラウンドで測った値の最後に、同じ場所での滞在が続いているか。
/// 続いていれば、その滞在を返す（通知で記録をうながすのに使う）
Stay? currentBackgroundStay(List<GeoSample> samples) {
  if (samples.isEmpty) {
    return null;
  }
  final StayDetector detector = StayDetector();
  Stay? stay;
  // 直近の数時間だけを見ればよい
  final DateTime since = samples.last.at.subtract(const Duration(hours: 3));
  for (final GeoSample s in samples) {
    if (s.at.isBefore(since)) {
      continue;
    }
    stay = detector.add(s);
  }
  return stay != null && stay.endedAt == samples.last.at ? stay : null;
}
