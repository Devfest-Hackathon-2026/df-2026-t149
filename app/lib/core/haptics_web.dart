import 'dart:js_interop';

@JS('navigator.vibrate')
external JSBoolean? _vibrate(JSArray<JSNumber> pattern);

/// ブラウザの Vibration API で振動させる。[pattern] は「振動する・止める」を交互に並べた長さ（ms）。
/// 対応しないブラウザ（iPhone の Safari など）では false
bool webVibrate(List<int> pattern) {
  try {
    return _vibrate(
          <JSNumber>[for (final int v in pattern) v.toJS].toJS,
        )?.toDart ??
        false;
  } catch (_) {
    return false;
  }
}
