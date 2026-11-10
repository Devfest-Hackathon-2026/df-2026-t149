import 'dart:io';

import 'package:flutter/services.dart';

/// Android では AndroidManifest.xml に地図のキーが入っているかを MainActivity に尋ねる
Future<bool> mapsApiKeyConfigured() async {
  if (!Platform.isAndroid) {
    return false;
  }
  const MethodChannel channel = MethodChannel('uramichi/config');
  return await channel.invokeMethod<bool>('mapsApiKeyConfigured') ?? false;
}
