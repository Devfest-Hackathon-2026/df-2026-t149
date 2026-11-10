import '../../core/models/assistant_answer.dart';
import '../../core/models/place_genre.dart';

/// Geminiちゃんを開いたときの利用者の状況。例文を選ぶのと、Gemini に参考として渡すのに使う。
///
/// サーバーにも端末にも保存しない
class AssistantSituation {
  const AssistantSituation({
    required this.now,
    this.onSite = false,
    this.searchedPlace,
    this.area,
    this.genres = const <PlaceGenre>{},
    this.favoriteCount = 0,
    this.famousNearby,
  });

  final DateTime now;

  /// 利用者が地図の中心の近くにいるか。false なら遠くから下調べしている
  final bool onSite;

  /// 検索欄で移動した地点の名前（「清水寺」など）。代わりを探す例文に使う
  final String? searchedPlace;

  /// 遠くを調べるで選んだ地域の名前（「長野県・松本・安曇野」など）
  final String? area;

  /// 地図で選んでいるジャンル
  final Set<PlaceGenre> genres;

  /// お気に入りの数
  final int favoriteCount;

  /// 地図で探した結果の中で、いちばん有名な場所の名前。代わりを探す例文に使う。
  /// 決まった地名（清水寺など）を例に出すと、遠くにいる人には関係がないため
  final String? famousNearby;

  bool get weekend =>
      now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

  /// 時間帯。サーバーの UserContext と同じ言葉を使う
  String get timeOfDay => switch (now.hour) {
    >= 5 && < 10 => '朝',
    >= 10 && < 15 => '昼',
    >= 15 && < 18 => '夕方',
    >= 18 && < 23 => '夜',
    _ => '深夜',
  };

  /// サーバーに送る状況（POST /api/assistant の context）
  Map<String, Object> toContextJson() => <String, Object>{
    'timeOfDay': timeOfDay,
    'weekend': weekend,
    'onSite': onSite,
    if (area case final String a) 'area': a,
  };
}

/// ジャンルごとの例文
const Map<PlaceGenre, String> _genreExamples = <PlaceGenre, String>{
  PlaceGenre.food: '落ち着ける小さな喫茶店はある？',
  PlaceGenre.nature: 'のんびりできる公園や庭園',
  PlaceGenre.worship: '静かにお参りできる寺社',
  PlaceGenre.culture: '小さな美術館や資料館',
  PlaceGenre.view: '景色のいい穴場',
  PlaceGenre.shopping: '地元の人が通う市場や商店',
  PlaceGenre.other: 'ちょっと変わった場所',
};

/// 状況に合った例文を、合う順に最大 [count] 件返す
List<String> assistantExamples(AssistantSituation s, {int count = 4}) {
  final String place = s.area ?? s.searchedPlace ?? '';
  final List<String> out = <String>[
    // 地名で移動した直後は、その場所の代わりを探すのがウラミチのいちばんの使い方
    if (s.searchedPlace case final String q when s.area == null) '$qの代わりはどこ？',
    for (final PlaceGenre g in s.genres) ?_genreExamples[g],
    switch (s.timeOfDay) {
      '朝' => '朝の散歩にいい静かな場所',
      '昼' => s.onSite ? 'ランチに寄れる隠れた店' : 'お昼を食べるならどこ？',
      '夕方' => '夕日がきれいに見える所',
      '夜' => '夜でも楽しめる穴場',
      _ => '明日の朝に行きたい穴場',
    },
    if (s.onSite)
      'ここから歩いて行ける穴場'
    else if (place.isNotEmpty)
      '$placeで一日過ごすなら？'
    else
      'このあたりで一日過ごすなら？',
    if (s.weekend)
      '休日にゆっくり過ごせる場所'
    else if (s.timeOfDay == '夜' || s.timeOfDay == '夕方')
      '仕事帰りに寄れる所',
    '近くの静かな穴場を教えて',
    if (s.famousNearby case final String f when f != s.searchedPlace)
      '$fの代わりはどこ？',
  ];
  return _unique(out).take(count).toList();
}

/// 答えに続けて話しかける例文。答えの種類に合わせる
List<String> assistantFollowUps(AssistantAnswer answer, AssistantSituation s) {
  final String? center = answer.center?.name;
  return _unique(switch (answer.intent) {
    AssistantIntent.recommend => <String>[
      if (s.onSite) 'もっと近くで' else 'ほかのジャンルだと？',
      'もっと知られていない所',
      if (s.timeOfDay == '夜' || s.timeOfDay == '深夜')
        '夜でも行ける所'
      else
        '公園でのんびりしたい',
      'ほかのジャンルだと？',
    ],
    AssistantIntent.alternatives => <String>[
      'もっと知られていない所',
      '歩いて行ける距離で',
      '寺社に絞って',
    ],
    AssistantIntent.locate => <String>[
      'このあたりの穴場は？',
      if (center != null) '$centerで静かに過ごせる所',
      '景色のいい場所',
    ],
    AssistantIntent.chat => assistantExamples(s),
  }).take(3).toList();
}

List<String> _unique(List<String> list) {
  final Set<String> seen = <String>{};
  return <String>[
    for (final String v in list)
      if (seen.add(v)) v,
  ];
}
