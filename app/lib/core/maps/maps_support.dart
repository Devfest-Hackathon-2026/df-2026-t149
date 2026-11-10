import 'maps_support_io.dart'
    if (dart.library.js_interop) 'maps_support_web.dart'
    as platform;

/// Google マップを使えるか。起動時に [detect] で一度だけ調べる。
///
/// 地図のキーが設定されていれば true になり、地図は Google マップで表示される。
/// キーがなければ false のまま、API キーなしで動く簡易地図で表示する。
abstract final class MapsSupport {
  static bool available = false;

  static Future<void> detect() async {
    try {
      available = await platform.mapsApiKeyConfigured();
    } catch (_) {
      // 調べられない端末（テストやデスクトップ）でも起動を止めず、簡易地図にする
      available = false;
    }
  }
}
