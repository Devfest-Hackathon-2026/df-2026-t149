import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/features/regions/regions.dart';

void main() {
  test('地域の id は重ならない', () {
    final Set<String> ids = <String>{for (final Region r in regions) r.id};
    expect(ids, hasLength(regions.length));
  });

  test('定番の地域の代わりは、どれも一覧にある穴場の地域', () {
    for (final RegionPair p in regionPairs) {
      expect(regionById(p.famous).famous, isTrue, reason: p.famous);
      expect(p.instead, isNotEmpty);
      for (final String id in p.instead) {
        expect(regionById(id).famous, isFalse, reason: id);
      }
    }
  });

  test('東京に行ったことがある人に、長野と新潟を勧める', () {
    final RegionPair tokyo = regionPairs.firstWhere(
      (RegionPair p) => p.famous == 'tokyo',
    );
    final Set<String> prefectures = <String>{
      for (final String id in tokyo.instead) regionById(id).prefecture,
    };
    expect(prefectures, containsAll(<String>['長野県', '新潟県']));
  });

  test('位置は日本の中にあり、探す半径は API の上限以内', () {
    for (final Region r in regions) {
      expect(r.lat, inInclusiveRange(24, 46), reason: r.id);
      expect(r.lng, inInclusiveRange(122, 154), reason: r.id);
      expect(r.radiusMeters, inInclusiveRange(5001, 50000), reason: r.id);
      expect(r.reason, isNotEmpty, reason: r.id);
    }
  });

  test('地域の紹介は、ほかの地域と比べたり下げたりしない', () {
    for (final Region r in regions) {
      for (final String ng in <String>[
        'より',
        '混む',
        '人が多い',
        'あふれ',
        '喧騒',
        'いっぱい',
        '違う',
      ]) {
        expect(r.reason, isNot(contains(ng)), reason: '${r.id}: ${r.reason}');
      }
    }
  });

  test('穴場の地域は、地方ごとにまとめても数が変わらない', () {
    final int hidden = regions.where((Region r) => !r.famous).length;
    expect(
      hiddenRegionsByArea().values.fold<int>(
        0,
        (int n, List<Region> v) => n + v.length,
      ),
      hidden,
    );
  });
}
