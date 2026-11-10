import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/core/models/assistant_answer.dart';
import 'package:uramichi/core/models/place_genre.dart';
import 'package:uramichi/features/assistant/assistant_situation.dart';

AssistantAnswer _answer(AssistantIntent intent, {String? center}) =>
    AssistantAnswer.fromJson(<String, dynamic>{
      'source': 'gemini',
      'intent': intent.name,
      'reply': 'はい',
      if (center != null)
        'center': <String, Object>{'name': center, 'lat': 35.0, 'lng': 135.0},
      'suggestions': <Object>[],
    });

void main() {
  test('時間帯を、サーバーと同じ言葉で決める', () {
    String t(int hour) =>
        AssistantSituation(now: DateTime(2026, 11, 9, hour)).timeOfDay;
    expect(
      <String>[t(6), t(12), t(16), t(20), t(2)],
      <String>['朝', '昼', '夕方', '夜', '深夜'],
    );
  });

  test('検索した地点があれば、その代わりを探す例文を先頭にする', () {
    final List<String> ex = assistantExamples(
      AssistantSituation(now: DateTime(2026, 11, 9, 12), searchedPlace: '清水寺'),
    );
    expect(ex.first, '清水寺の代わりはどこ？');
    expect(ex, hasLength(4));
    expect(ex.toSet(), hasLength(4));
  });

  test('ジャンル・時間帯・現地かどうかで例文を変える', () {
    final List<String> nightOnSite = assistantExamples(
      AssistantSituation(
        now: DateTime(2026, 11, 10, 20), // 火曜の夜
        onSite: true,
        genres: <PlaceGenre>{PlaceGenre.food},
      ),
    );
    expect(nightOnSite, contains('落ち着ける小さな喫茶店はある？'));
    expect(nightOnSite, contains('夜でも楽しめる穴場'));
    expect(nightOnSite, contains('ここから歩いて行ける穴場'));
    expect(nightOnSite, contains('仕事帰りに寄れる所'));

    final List<String> remote = assistantExamples(
      AssistantSituation(
        now: DateTime(2026, 11, 8, 7), // 日曜の朝
        area: '長野県・松本・安曇野',
      ),
    );
    expect(remote, contains('長野県・松本・安曇野で一日過ごすなら？'));
    expect(remote, contains('朝の散歩にいい静かな場所'));
    expect(remote, contains('休日にゆっくり過ごせる場所'));
  });

  test('サーバーに送る状況', () {
    final Map<String, Object> j = AssistantSituation(
      now: DateTime(2026, 11, 8, 20),
      onSite: true,
      area: '佐渡',
    ).toContextJson();
    expect(j, <String, Object>{
      'timeOfDay': '夜',
      'weekend': true,
      'onSite': true,
      'area': '佐渡',
    });
  });

  test('答えの後の例文は、答えの種類に合わせる', () {
    final AssistantSituation s = AssistantSituation(
      now: DateTime(2026, 11, 9, 12),
    );
    expect(
      assistantFollowUps(_answer(AssistantIntent.locate, center: '嵐山'), s),
      contains('嵐山で静かに過ごせる所'),
    );
    expect(
      assistantFollowUps(_answer(AssistantIntent.alternatives), s),
      contains('歩いて行ける距離で'),
    );
    expect(
      assistantFollowUps(_answer(AssistantIntent.recommend), s),
      hasLength(3),
    );
  });

  test('決まった地名は例に出さず、探した結果の有名な場所を使う', () {
    final List<String> none = assistantExamples(
      AssistantSituation(now: DateTime(2026, 11, 9, 12)),
      count: 10,
    );
    expect(none.where((String e) => e.contains('清水寺')), isEmpty);

    final List<String> withFamous = assistantExamples(
      AssistantSituation(now: DateTime(2026, 11, 9, 12), famousNearby: '松本城'),
      count: 10,
    );
    expect(withFamous, contains('松本城の代わりはどこ？'));
  });
}
