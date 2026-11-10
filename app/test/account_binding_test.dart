import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uramichi/core/auth/account_binding.dart';
import 'package:uramichi/core/auth/account_controller.dart';
import 'package:uramichi/core/auth/auth_gateway.dart';
import 'package:uramichi/core/data/checkin_repository.dart';
import 'package:uramichi/core/location/location_service.dart';
import 'package:uramichi/core/location/visit_recorder.dart';

import 'fake_account.dart';
import 'fake_location.dart';

/// 切り替えた利用者を順に記録する保存先
class _RecordingRepository extends LocalCheckinRepository {
  final List<String?> users = <String?>[];

  @override
  void setUser(String? uid) => users.add(uid);
}

void main() {
  late FakeAuthGateway auth;
  late _RecordingRepository checkins;
  late FakeLocationService location;
  late VisitRecorder visits;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    auth = FakeAuthGateway(current: testUser);
    checkins = _RecordingRepository();
    location = FakeLocationService();
    visits = VisitRecorder(
      location: location,
      prefs: await SharedPreferences.getInstance(),
    );
  });

  AccountController bound() {
    final AccountController account = AccountController(
      auth: auth,
      profiles: FakeProfileRepository(testProfile),
    );
    bindRecordsToAccount(account, checkins: checkins, visits: visits);
    return account;
  }

  test('ログインした利用者の記録に切り替え、ログアウトすると誰の記録も読み書きしない', () async {
    final AccountController account = bound();
    await account.start();
    expect(checkins.users.last, testUser.uid);

    await account.signOut();
    expect(checkins.users.last, isNull);

    auth.nextUser = const AuthUser(uid: 'u2');
    await account.signIn();
    expect(checkins.users.last, 'u2');
  });

  test('ログアウトすると、位置情報の記録を止めて滞在の記録を消す', () async {
    final AccountController account = bound();
    await account.start();
    await visits.enable();
    visits.saveCurrent(
      GeoSample(
        lat: 34.697,
        lng: 135.192,
        accuracyMeters: 10,
        at: DateTime(2026, 11, 8, 12),
      ),
    );

    await account.signOut();
    await pumpEventQueue();

    expect(location.backgroundRunning, isFalse);
    expect(visits.enabled, isFalse);
    expect(visits.visits, isEmpty);
  });
}
