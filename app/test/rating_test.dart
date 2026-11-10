import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/core/models/memory_log.dart';
import 'package:uramichi/core/models/place.dart';
import 'package:uramichi/core/models/timeline_entry.dart';
import 'package:uramichi/core/widgets/star_rating.dart';

void main() {
  test('★3以上を当たり、★2以下をハズレにする', () {
    expect(
      <Verdict>[for (int i = 1; i <= 5; i++) Verdict.fromStars(i)],
      <Verdict>[
        Verdict.miss,
        Verdict.miss,
        Verdict.hit,
        Verdict.hit,
        Verdict.hit,
      ],
    );
  });

  test('★評価を JSON で送り、読み直せる', () {
    final MemoryLog log = MemoryLog(
      id: 'a',
      placeId: 'p',
      placeName: '祠',
      verdict: Verdict.fromStars(5),
      rating: 5,
      createdAt: DateTime(2026, 11, 8),
    );
    final Map<String, dynamic> j = log.toJson();
    expect(j['rating'], 5);
    final MemoryLog back = MemoryLog.fromJson('a', j);
    expect(back.rating, 5);
    expect(back.stars, 5);
    expect(back.copyWith(isPublic: true).rating, 5);
  });

  test('★評価のない古い記録は、当たりを★4、ハズレを★2として見せる', () {
    final MemoryLog hit = MemoryLog.fromJson('a', <String, dynamic>{
      'placeId': 'p',
      'verdict': 'hit',
    });
    final MemoryLog miss = MemoryLog.fromJson('b', <String, dynamic>{
      'placeId': 'p',
      'verdict': 'miss',
      'rating': 0, // 範囲の外の値は無視する
    });
    expect(hit.rating, isNull);
    expect(hit.stars, 4);
    expect(miss.rating, isNull);
    expect(miss.stars, 2);
    final TimelineEntry e = TimelineEntry.fromJson(<String, dynamic>{
      'id': 'e',
      'placeId': 'p',
      'verdict': 'hit',
      'rating': 3,
    });
    expect(e.stars, 3);
  });

  test('場所の★評価の平均を読む', () {
    final Place p = Place.fromJson(<String, dynamic>{
      'id': 'p',
      'name': '祠',
      'lat': 34,
      'lng': 135,
      'stars': 3.5,
      'starCount': 2,
    });
    expect(p.stars, 3.5);
    expect(p.starCount, 2);
    expect(Place.fromJson(p.toJson()).stars, 3.5);
  });

  testWidgets('★を選ぶと、その★までを点けて言葉を見せる', (WidgetTester tester) async {
    int? value;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) =>
                StarRatingInput(
                  value: value,
                  onChanged: (int v) => setState(() => value = v),
                ),
          ),
        ),
      ),
    );
    expect(find.text('★で評価してください'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('★3、ふつう'));
    await tester.pumpAndSettle();
    expect(value, 3);
    expect(find.text('ふつう'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(3));
  });

  testWidgets('★の平均は半分の★で表す', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: StarRating(value: 3.5)));
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(3));
    expect(find.byIcon(Icons.star_half_rounded), findsOneWidget);
    expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
  });
}
