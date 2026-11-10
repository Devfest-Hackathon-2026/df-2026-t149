import 'dart:async';

import 'package:uramichi/core/theme.dart';
import 'package:uramichi/core/widgets/stamp_celebration.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppTheme.useGoogleFonts = false;
  // 押された後も動き続ける印は、テストでは止める（pumpAndSettle が終わらなくなるため）
  StampCelebration.loop = false;
  await testMain();
}
