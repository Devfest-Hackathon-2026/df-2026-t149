import 'dart:async';

import '../data/checkin_repository.dart';
import '../location/visit_recorder.dart';
import 'account_controller.dart';

/// ログインしている利用者に合わせて、端末に保存する記録を切り替える
///
/// チェックインと思い出ログは利用者ごとの保存先に切り替える。
/// 滞在の記録は利用者を区別せずに端末の位置を測るため、ログアウトしたときに測定を止めて消す
void bindRecordsToAccount(
  AccountController account, {
  required CheckinRepository checkins,
  required VisitRecorder visits,
}) {
  void apply() {
    checkins.setUser(account.user?.uid);
    if (account.state is AccountSignedOut) {
      unawaited(visits.clear());
    }
  }

  account.addListener(apply);
  apply();
}
