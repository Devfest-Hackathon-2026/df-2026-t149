import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'haptics_stub.dart' if (dart.library.js_interop) 'haptics_web.dart';

/// 振動の1区切り。[pause] だけ止めてから、[strength]（1〜255）で [vibrate] だけ振動する
typedef Pulse = ({int pause, int vibrate, int strength});

/// チェックインの祝い方の強さ
enum CelebrationLevel {
  /// 前にも来た場所
  revisit,

  /// はじめて来た場所
  newPlace,

  /// その場所の1人目の訪問者
  pioneer,
}

/// 操作に合わせて端末を振動させる（ハプティクス）。
///
/// 設定の画面でオフにできる（[AppSettings.hapticsEnabled]）。オフのときは何もしない。
/// 軽い振動は Flutter の [HapticFeedback] を使う。祝う演出の強い振動は、Android では端末の振動の機能
/// （MainActivity の uramichi/haptics）で強さと長さを決めて鳴らし、Web ではブラウザの Vibration API を使う。
/// どちらも使えない端末では [HapticFeedback] を続けて鳴らす（docs/decisions.md の D-025、D-027）
abstract final class Haptics {
  /// 振動させるか。[AppSettings] が設定の値を入れる
  static bool enabled = true;

  /// 連続して鳴らす振動の間隔
  static const Duration gap = Duration(milliseconds: 90);

  static Future<void> _run(Future<void> Function() call) async {
    if (!enabled) {
      return;
    }
    try {
      await call();
    } catch (_) {
      // 振動できない端末でも、操作は続ける
    }
  }

  static Future<void> _sequence(List<Future<void> Function()> steps) async {
    for (int i = 0; i < steps.length; i++) {
      if (!enabled) {
        return;
      }
      if (i > 0) {
        await Future<void>.delayed(gap);
      }
      await _run(steps[i]);
    }
  }

  /// ボタンを押したとき
  static Future<void> tap() => _run(HapticFeedback.lightImpact);

  /// スライダーの目盛りや選択肢を切り替えたとき
  static Future<void> select() => _run(HapticFeedback.selectionClick);

  /// ★を選んだとき。★が多いほど強くする
  static Future<void> star(int stars) => _run(switch (stars) {
    >= 5 => HapticFeedback.mediumImpact,
    4 => HapticFeedback.lightImpact,
    _ => HapticFeedback.selectionClick,
  });

  /// 数を数え上げる間の小さな振動
  static Future<void> tick() => _run(HapticFeedback.selectionClick);

  static const MethodChannel _channel = MethodChannel('uramichi/haptics');

  /// 強さと長さを決めた振動を鳴らす。端末が対応しなければ [fallback] を続けて鳴らす
  static Future<void> _pattern(
    List<Pulse> pulses,
    List<Future<void> Function()> fallback,
  ) async {
    if (!enabled) {
      return;
    }
    if (kIsWeb) {
      // ブラウザの形式は「振動する・止める」の順なので、最初の止める長さを除く
      final List<int> web = <int>[
        for (int i = 0; i < pulses.length; i++) ...<int>[
          if (i > 0) pulses[i].pause,
          pulses[i].vibrate,
        ],
      ];
      if (webVibrate(web)) {
        return;
      }
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final bool? ok = await _channel.invokeMethod<bool>(
          'pattern',
          <String, Object>{
            'timings': <int>[
              for (final Pulse p in pulses) ...<int>[p.pause, p.vibrate],
            ],
            'amplitudes': <int>[
              for (final Pulse p in pulses) ...<int>[0, p.strength],
            ],
          },
        );
        if (ok ?? false) {
          return;
        }
      } catch (_) {
        // 古い版のアプリや、振動の機能がない端末
      }
    }
    await _sequence(fallback);
  }

  /// チェックインできて、何人目かが決まったとき。はじめての場所と1人目ほど強く長くする
  static Future<void> checkin(CelebrationLevel level) => switch (level) {
    CelebrationLevel.revisit => _pattern(
      const <Pulse>[
        (pause: 0, vibrate: 40, strength: 180),
        (pause: 70, vibrate: 60, strength: 255),
      ],
      <Future<void> Function()>[
        HapticFeedback.mediumImpact,
        HapticFeedback.heavyImpact,
      ],
    ),
    CelebrationLevel.newPlace => _pattern(
      const <Pulse>[
        (pause: 0, vibrate: 60, strength: 200),
        (pause: 60, vibrate: 60, strength: 255),
        (pause: 60, vibrate: 160, strength: 255),
      ],
      <Future<void> Function()>[
        HapticFeedback.heavyImpact,
        HapticFeedback.heavyImpact,
        HapticFeedback.vibrate,
      ],
    ),
    CelebrationLevel.pioneer => _pattern(
      const <Pulse>[
        (pause: 0, vibrate: 40, strength: 110),
        (pause: 40, vibrate: 40, strength: 170),
        (pause: 40, vibrate: 40, strength: 220),
        (pause: 40, vibrate: 280, strength: 255),
        (pause: 120, vibrate: 100, strength: 255),
      ],
      <Future<void> Function()>[
        HapticFeedback.mediumImpact,
        HapticFeedback.heavyImpact,
        HapticFeedback.heavyImpact,
        HapticFeedback.vibrate,
      ],
    ),
  };

  /// お気に入りに入れたときなど、小さな成功
  static Future<void> success() => _sequence(<Future<void> Function()>[
    HapticFeedback.mediumImpact,
    HapticFeedback.heavyImpact,
  ]);

  /// 思い出を残して、祝う画面を開いたとき
  static Future<void> celebrate() => _pattern(
    const <Pulse>[
      (pause: 0, vibrate: 90, strength: 255),
      (pause: 70, vibrate: 60, strength: 200),
      (pause: 70, vibrate: 180, strength: 255),
    ],
    <Future<void> Function()>[
      HapticFeedback.heavyImpact,
      HapticFeedback.mediumImpact,
      HapticFeedback.heavyImpact,
    ],
  );

  /// 実績を解除したとき。小さく3回たたいてから長く鳴らす
  static Future<void> unlock() => _pattern(
    const <Pulse>[
      (pause: 0, vibrate: 30, strength: 150),
      (pause: 50, vibrate: 30, strength: 200),
      (pause: 50, vibrate: 30, strength: 255),
      (pause: 90, vibrate: 320, strength: 255),
    ],
    <Future<void> Function()>[
      HapticFeedback.mediumImpact,
      HapticFeedback.mediumImpact,
      HapticFeedback.heavyImpact,
    ],
  );
}
