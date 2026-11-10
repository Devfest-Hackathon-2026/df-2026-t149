import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/core/models/place.dart';
import 'package:uramichi/features/map/map_search_controller.dart';

Place _place({
  int count = 5,
  double? rating,
  int obscurity = 80,
  int hits = 0,
  int misses = 0,
  double? stars,
  int starCount = 0,
}) => Place(
  id: 'p',
  name: '場所',
  lat: 0,
  lng: 0,
  userRatingCount: count,
  rating: rating,
  obscurity: obscurity,
  hits: hits,
  misses: misses,
  stars: stars,
  starCount: starCount,
);

void main() {
  group('おすすめ順の評判', () {
    test('同じくらい知られていなければ、Google の★が高いほうを上にする', () {
      expect(
        recommendScore(_place(rating: 4.6), nearness: 0.5),
        greaterThan(recommendScore(_place(rating: 3.9), nearness: 0.5)),
      );
    });

    test('口コミが1件だけの★5は、たくさんの口コミの★4.5より大きく上げない', () {
      expect(
        placeQuality(_place(count: 1, rating: 5)),
        lessThan(placeQuality(_place(count: 40, rating: 4.5))),
      );
    });

    test('★が低い場所は、より知られていなくても評判のよい場所の下にする', () {
      final Place poor = _place(rating: 2.8, obscurity: 95);
      final Place good = _place(rating: 4.4, obscurity: 80);
      expect(hasPoorReputation(poor), isTrue);
      expect(
        recommendScore(good, nearness: 0.5),
        greaterThan(recommendScore(poor, nearness: 0.5)),
      );
    });

    test('ウラミチでハズレが多い場所を下げる', () {
      final Place missed = _place(rating: 4.2, hits: 1, misses: 3);
      expect(hasPoorReputation(missed), isTrue);
      expect(
        recommendScore(_place(rating: 4.2), nearness: 0.5),
        greaterThan(recommendScore(missed, nearness: 0.5)),
      );
    });

    test('評価のない場所は中くらいとして扱い、下げない', () {
      final Place unknown = _place(count: 0);
      expect(hasPoorReputation(unknown), isFalse);
      expect(placeQuality(unknown), inInclusiveRange(0.3, 0.7));
    });

    test('ウラミチの★と当たりも評判に入れる', () {
      expect(
        placeQuality(_place(rating: 4, hits: 4, stars: 4.8, starCount: 4)),
        greaterThan(placeQuality(_place(rating: 4))),
      );
    });
  });
}
