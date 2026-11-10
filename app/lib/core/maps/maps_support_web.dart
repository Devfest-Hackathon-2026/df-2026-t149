import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Web では index.html が Maps JavaScript API を読み込み終えたかを待つ。
/// maps_config.js がないときと読み込みに失敗したときは、Promise が失敗して false になる
Future<bool> mapsApiKeyConfigured() async {
  final JSPromise<JSAny?>? ready = globalContext
      .getProperty<JSPromise<JSAny?>?>('uramichiMapsReady'.toJS);
  if (ready == null) {
    return false;
  }
  await ready.toDart;
  return true;
}
