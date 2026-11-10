import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'haptics.dart';
import 'notifications.dart';
import 'sounds.dart';
import 'theme.dart';

/// キーカラーの選び方
sealed class KeyColorChoice {
  const KeyColorChoice();

  /// 保存された色を戻す。未設定なら壁紙の色、不正な値ならアプリの色にする
  static KeyColorChoice decode(String? value) {
    if (value == null || value == WallpaperKeyColor.code) {
      return const WallpaperKeyColor();
    }
    if (value.startsWith('#') && value.length == 7) {
      final int? rgb = int.tryParse(value.substring(1), radix: 16);
      if (rgb != null) {
        return CustomKeyColor(Color(0xFF000000 | rgb));
      }
    }
    return const AppKeyColor();
  }

  String encode();
}

/// アプリの標準の色（[AppTheme.keyColor]）
final class AppKeyColor extends KeyColorChoice {
  const AppKeyColor();

  static const String code = 'app';

  @override
  String encode() => code;
}

/// 端末の壁紙から作られる色（Android 12 以降の Material You）
final class WallpaperKeyColor extends KeyColorChoice {
  const WallpaperKeyColor();

  static const String code = 'wallpaper';

  @override
  String encode() => code;
}

/// 利用者が選んだ色
final class CustomKeyColor extends KeyColorChoice {
  const CustomKeyColor(this.color);

  final Color color;

  @override
  String encode() =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  bool operator ==(Object other) =>
      other is CustomKeyColor && other.color.toARGB32() == color.toARGB32();

  @override
  int get hashCode => color.toARGB32();
}

/// テーマとキーカラーの設定。変更すると端末に保存する
class AppSettings extends ChangeNotifier {
  AppSettings({
    SharedPreferences? prefs,
    ThemeMode themeMode = ThemeMode.system,
    KeyColorChoice keyColor = const WallpaperKeyColor(),
    bool hapticsEnabled = true,
    bool soundEnabled = true,
    bool demoMode = false,
    bool notificationsEnabled = true,
  }) : _prefs = prefs,
       _notificationsEnabled = notificationsEnabled,
       _demoMode = demoMode,
       _themeMode = themeMode,
       _keyColor = keyColor,
       _hapticsEnabled = hapticsEnabled,
       _soundEnabled = soundEnabled {
    Haptics.enabled = hapticsEnabled;
    Sounds.enabled = soundEnabled;
  }

  factory AppSettings.load(SharedPreferences prefs) => AppSettings(
    prefs: prefs,
    themeMode:
        ThemeMode.values.asNameMap()[prefs.getString(_themeModeKey)] ??
        ThemeMode.system,
    keyColor: KeyColorChoice.decode(prefs.getString(_keyColorKey)),
    hapticsEnabled: prefs.getBool(_hapticsKey) ?? true,
    soundEnabled: prefs.getBool(_soundKey) ?? true,
    demoMode: prefs.getBool(_demoModeKey) ?? false,
    notificationsEnabled: AppNotifications.enabled(prefs),
  );

  static const String _themeModeKey = 'themeMode';
  static const String _keyColorKey = 'keyColor';
  static const String _hapticsKey = 'haptics';
  static const String _soundKey = 'sound';
  static const String _demoModeKey = 'demoMode';
  static const String _lastLatKey = 'lastMapLat';
  static const String _lastLngKey = 'lastMapLng';

  /// 用意したキーカラー
  static const List<Color> presets = <Color>[
    Color(0xFF3F51B5),
    Color(0xFF1E88E5),
    Color(0xFF00897B),
    Color(0xFF43A047),
    Color(0xFFF4511E),
    Color(0xFFD81B60),
    Color(0xFF8E24AA),
    Color(0xFF6D4C41),
  ];

  /// 保存しない場合（テスト）は null
  final SharedPreferences? _prefs;
  ThemeMode _themeMode;
  KeyColorChoice _keyColor;
  bool _hapticsEnabled;
  bool _soundEnabled;
  bool _demoMode;
  bool _notificationsEnabled;

  /// 通知を出すか（[AppNotifications]）。滞在の知らせと、自分の口コミへの反応の知らせ
  bool get notificationsEnabled => _notificationsEnabled;

  set notificationsEnabled(bool value) {
    _notificationsEnabled = value;
    _prefs?.setBool(AppNotifications.enabledKey, value);
    notifyListeners();
  }

  /// デモデータだけで動かすか。オンのあいだは、サーバーにも Google にも問い合わせず、
  /// アプリに入っている架空の場所と、端末の中の記録だけを使う。オフのときはデモデータを使わない
  bool get demoMode => _demoMode;

  set demoMode(bool value) {
    if (value == _demoMode) {
      return;
    }
    _demoMode = value;
    _prefs?.setBool(_demoModeKey, value);
    notifyListeners();
  }

  /// 端末の壁紙から作られた色。Android 12 より前の端末と Web では null
  Color? wallpaperColor;

  ThemeMode get themeMode => _themeMode;
  KeyColorChoice get keyColor => _keyColor;

  /// 操作に合わせて端末を振動させるか（[Haptics]）
  bool get hapticsEnabled => _hapticsEnabled;

  set hapticsEnabled(bool value) {
    _hapticsEnabled = value;
    Haptics.enabled = value;
    _prefs?.setBool(_hapticsKey, value);
    notifyListeners();
  }

  /// チェックインや★のときに効果音を鳴らすか（[Sounds]）
  bool get soundEnabled => _soundEnabled;

  set soundEnabled(bool value) {
    _soundEnabled = value;
    Sounds.enabled = value;
    _prefs?.setBool(_soundKey, value);
    notifyListeners();
  }

  /// 前回見ていた地図の地点。なければ null
  (double, double)? get lastMapCenter {
    final double? lat = _prefs?.getDouble(_lastLatKey);
    final double? lng = _prefs?.getDouble(_lastLngKey);
    return lat == null || lng == null ? null : (lat, lng);
  }

  void saveMapCenter(double lat, double lng) {
    _prefs?.setDouble(_lastLatKey, lat);
    _prefs?.setDouble(_lastLngKey, lng);
  }

  set themeMode(ThemeMode value) {
    _themeMode = value;
    _prefs?.setString(_themeModeKey, value.name);
    notifyListeners();
  }

  set keyColor(KeyColorChoice value) {
    _keyColor = value;
    _prefs?.setString(_keyColorKey, value.encode());
    notifyListeners();
  }

  /// テーマを作るのに使うキーカラー。壁紙の色を選んでいても、端末が対応していなければアプリの色にする
  Color resolveKeyColor() => switch (_keyColor) {
    AppKeyColor() => AppTheme.keyColor,
    WallpaperKeyColor() => wallpaperColor ?? AppTheme.keyColor,
    CustomKeyColor(:final Color color) => color,
  };
}
