import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uramichi/core/location/location_service.dart';
import 'package:uramichi/core/location/visit_recorder.dart';

import 'package:uramichi/core/location/background_samples.dart';

import 'fake_location.dart';

const double _lat = 34.697;
const double _lng = 135.192;
final DateTime _base = DateTime(2026, 11, 8, 12);

GeoSample _at(int minutes, {double dLat = 0}) => GeoSample(
  lat: _lat + dLat,
  lng: _lng,
  accuracyMeters: 10,
  at: _base.add(Duration(minutes: minutes)),
);

void main() {
  late FakeLocationService location;
  late SharedPreferences prefs;
  late DateTime now;

  VisitRecorder recorder() =>
      VisitRecorder(location: location, prefs: prefs, now: () => now);

  void stay(VisitRecorder r, int from, {double dLat = 0}) => r
    ..addSample(_at(from, dLat: dLat))
    ..addSample(_at(from + 10, dLat: dLat));

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    location = FakeLocationService();
    now = _base;
  });

  test('滞在を記録し、アプリを開き直しても残る', () {
    stay(recorder(), 0);
    final List<Visit> visits = recorder().visits;
    expect(visits.single.lat, _lat);
    expect(visits.single.startedAt, _base);
  });

  test('保存した内容を読めないときは、記録を空にして起動できる', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'visitRecorder': '{壊れた内容',
    });
    prefs = await SharedPreferences.getInstance();
    expect(recorder().visits, isEmpty);
  });

  test('移動の途中の短い停止は記録しない', () {
    final VisitRecorder r = recorder()
      ..addSample(_at(0))
      ..addSample(_at(5));
    expect(r.visits, isEmpty);
  });

  test('同じ場所を少し離れて戻っても 1 件にまとめる', () {
    final VisitRecorder r = recorder();
    stay(r, 0);
    r
      ..addSample(_at(15, dLat: 0.01))
      ..addSample(_at(17, dLat: 0.01));
    r.addSample(_at(19));
    stay(r, 21);
    expect(r.visits.single.endedAt, _at(31).at);
  });

  test('今回はチェックインしないと答えると消え、そのまま滞在しても提案し直さない', () {
    final VisitRecorder r = recorder();
    stay(r, 0);
    r.skip(r.visits.single);
    expect(r.visits, isEmpty);

    r.addSample(_at(20));
    expect(r.visits, isEmpty);
  });

  test('今回はチェックインしないと答えた場所でも、日を改めて滞在すれば提案する', () {
    final VisitRecorder r = recorder();
    stay(r, 0);
    r.skip(r.visits.single);

    now = _base.add(const Duration(hours: 13));
    stay(r, 60 * 13);
    expect(r.visits, hasLength(1));
  });

  test('今後提案しないと答えた場所は、日を改めても提案しない', () {
    final VisitRecorder r = recorder();
    stay(r, 0);
    r.neverSuggest(r.visits.single);

    now = _base.add(const Duration(days: 3));
    final VisitRecorder reopened = recorder();
    stay(reopened, 60 * 24 * 3);
    expect(reopened.visits, isEmpty);
  });

  test('チェックインすると近くの滞在が消え、提案し直さない', () {
    final VisitRecorder r = recorder();
    stay(r, 0);
    r.markCheckedIn(_lat, _lng);
    expect(r.visits, isEmpty);

    r.addSample(_at(20));
    expect(r.visits, isEmpty);
  });

  test('チェックインした場所から離れた滞在は残す', () {
    final VisitRecorder r = recorder();
    stay(r, 0);
    r.markCheckedIn(_lat + 0.01, _lng);
    expect(r.visits, hasLength(1));
  });

  test('14 日より古い記録は開き直すと消える', () {
    stay(recorder(), 0);
    now = _base.add(const Duration(days: 15));
    expect(recorder().visits, isEmpty);
  });

  test('いまの場所を手動で記録できる', () {
    final VisitRecorder r = recorder()..saveCurrent(_at(0));
    expect(r.visits.single.startedAt, _base);
  });

  test('位置情報を許可されないと記録を始めない', () async {
    location.access = LocationAccess.denied;
    final VisitRecorder r = recorder();
    expect(await r.enable(), LocationAccess.denied);
    expect(r.enabled, isFalse);
  });

  test('有効のまま開き直すと、許可の確認を出さずに続きから記録する', () async {
    await recorder().enable();
    location.backgroundRunning = false;
    final VisitRecorder reopened = recorder();
    await reopened.resume();
    expect(location.lastAsk, isFalse);
    expect(location.backgroundRunning, isTrue);
    expect(reopened.enabled, isTrue);
  });

  test('端末の設定で許可を外されていたら、開き直したときに記録を止める', () async {
    await recorder().enable();
    location.access = LocationAccess.denied;
    final VisitRecorder reopened = recorder();
    await reopened.resume();
    expect(reopened.enabled, isFalse);
  });

  group('バックグラウンドの測定', () {
    test('記録を始めると定期的な測定を始め、やめると止めて未処理の測定値も消す', () async {
      final VisitRecorder r = recorder();
      expect(await r.enable(), LocationAccess.granted);
      expect(location.backgroundRunning, isTrue);
      await appendBackgroundSample(prefs, _at(0));

      await r.disable();

      expect(location.backgroundRunning, isFalse);
      expect(prefs.getString(backgroundSamplesKey), isNull);
    });

    test('常に許可がないときは始めず、そのことを返す', () async {
      location.backgroundAccess = LocationAccess.backgroundNeeded;
      final VisitRecorder r = recorder();

      expect(await r.enable(), LocationAccess.backgroundNeeded);

      expect(r.enabled, isFalse);
      expect(location.backgroundRunning, isFalse);
    });

    test('設定で常に許可にして戻ると、そのまま記録を始める', () async {
      location.backgroundAccess = LocationAccess.backgroundNeeded;
      final VisitRecorder r = recorder();
      await r.enable();

      await r.refresh();
      expect(r.enabled, isFalse, reason: '許可されるまでは始めない');

      location.backgroundAccess = LocationAccess.granted;
      await r.refresh();

      expect(r.enabled, isTrue);
      expect(location.backgroundRunning, isTrue);
    });

    test('記録を頼んでいないときは、許可があっても始めない', () async {
      final VisitRecorder r = recorder();

      await r.refresh();

      expect(r.enabled, isFalse);
    });

    test('バックグラウンドの測定値から滞在を作り、処理した測定値を消す', () async {
      final VisitRecorder r = recorder();
      await r.enable();
      await appendBackgroundSample(prefs, _at(0));
      await appendBackgroundSample(prefs, _at(15));

      await r.refresh();

      expect(r.visits.single.startedAt, _base);
      expect(r.visits.single.endedAt, _base.add(const Duration(minutes: 15)));
      expect(prefs.getString(backgroundSamplesKey), isNull);
    });

    test('起動時に常に許可が外れていたら記録をやめる', () async {
      final VisitRecorder first = recorder();
      await first.enable();
      location.backgroundAccess = LocationAccess.backgroundNeeded;

      final VisitRecorder r = recorder();
      await r.resume();

      expect(r.enabled, isFalse);
      expect(location.backgroundRunning, isFalse);
      expect(location.lastAsk, isFalse, reason: '起動しただけで許可の確認を出さない');
    });

    test('読めない測定値があっても、残りを処理して起動できる', () async {
      await prefs.setString(backgroundSamplesKey, '{壊れた内容');
      final VisitRecorder r = recorder();
      await r.enable();

      await r.refresh();

      expect(r.visits, isEmpty);
      expect(prefs.getString(backgroundSamplesKey), isNull);
    });

    test('測定値は上限を超えると古いものから消す', () async {
      for (int i = 0; i < maxBackgroundSamples + 2; i++) {
        await appendBackgroundSample(prefs, _at(i));
      }

      expect(readBackgroundSamples(prefs).length, maxBackgroundSamples);
      expect(readBackgroundSamples(prefs).first.at, _at(2).at);
    });
  });

  group('ログアウトしたとき', () {
    test('位置情報の記録を止め、滞在と提案しない地点を端末から消す', () async {
      final VisitRecorder r = recorder();
      await r.enable();
      stay(r, 0);
      stay(r, 30, dLat: 0.01);
      r.neverSuggest(r.visits.first);

      await r.clear();

      expect(location.backgroundRunning, isFalse);
      expect(r.enabled, isFalse);
      expect(r.visits, isEmpty);
      final VisitRecorder reopened = recorder();
      expect(reopened.enabled, isFalse);
      expect(reopened.visits, isEmpty);
      // 前の利用者が提案しないと決めた地点も残さない
      stay(reopened, 60, dLat: 0.01);
      expect(reopened.visits, hasLength(1));
    });

    test('バックグラウンドで測った値を、次の利用者の記録に加えない', () async {
      final VisitRecorder r = recorder();
      await r.enable();
      await prefs.setString(backgroundSamplesKey, '[]');

      await r.clear();

      expect(prefs.containsKey(backgroundSamplesKey), isFalse);
    });
  });
}
