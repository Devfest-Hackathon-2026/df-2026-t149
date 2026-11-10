import 'memory_log.dart';

/// 周辺のタイムラインの1件。サーバー（GET /api/timeline）と同じ JSON 形式
class TimelineEntry {
  const TimelineEntry({
    required this.id,
    required this.author,
    this.authorName = '',
    this.authorIcon = '',
    required this.mine,
    required this.placeId,
    required this.placeName,
    required this.verdict,
    required this.createdAt,
    this.comment = '',
    this.order,
    this.rating,
    this.isMock = false,
    this.genre,
    this.photoId,
    this.wantCount = 0,
    this.helpfulCount = 0,
    this.myWant = false,
    this.myHelpful = false,
  });

  factory TimelineEntry.fromJson(Map<String, dynamic> j) => TimelineEntry(
    id: j['id'] as String,
    author: j['author'] as String? ?? '',
    authorName: j['authorName'] as String? ?? '',
    authorIcon: j['authorIcon'] as String? ?? '',
    mine: j['mine'] as bool? ?? false,
    placeId: j['placeId'] as String,
    placeName: j['placeName'] as String? ?? '',
    verdict: Verdict.of(j['verdict'] as String?),
    comment: j['comment'] as String? ?? '',
    order: (j['order'] as num?)?.toInt(),
    rating: Verdict.validRating((j['rating'] as num?)?.toInt()),
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    genre: _nonEmpty(j['genre']),
    photoId: _nonEmpty(j['photoId']),
    wantCount: (j['wantCount'] as num?)?.toInt() ?? 0,
    helpfulCount: (j['helpfulCount'] as num?)?.toInt() ?? 0,
    myWant: j['myWant'] as bool? ?? false,
    myHelpful: j['myHelpful'] as bool? ?? false,
  );

  static String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

  final String id;

  /// 投稿者を区別する符号
  final String author;

  /// 投稿者のニックネーム。プロフィールを保存していない投稿者は空の文字列
  final String authorName;

  /// 投稿者のアイコンの ID（[ProfileIcon.id]）。プロフィールを保存していない投稿者は空の文字列
  final String authorIcon;

  /// 自分の投稿か
  final bool mine;
  final String placeId;
  final String placeName;
  final Verdict verdict;
  final String comment;
  final int? order;

  /// ★評価（1〜5）。★評価を入れる前の記録は null
  final int? rating;

  /// 表示に使う★の数（[MemoryLog.stars] と同じ決め方）
  int get stars => rating ?? Verdict.defaultStars(verdict);
  final DateTime createdAt;

  /// 端末だけで動くときに見せる架空の投稿か
  final bool isMock;

  /// スタンプの種類（[PlaceGenre.id]）。ジャンルを残す前の記録は null
  final String? genre;

  /// 記録に付けた写真の ID。写真のない記録は null
  final String? photoId;

  /// 「行ってみたい」の数
  final int wantCount;

  /// 「参考になった」の数
  final int helpfulCount;

  /// 自分が「行ってみたい」を付けたか
  final bool myWant;

  /// 自分が「参考になった」を付けたか
  final bool myHelpful;

  /// [kind] の反応を [on] にした後の記録。数は手元で増減し、サーバーの応答で置き換える
  TimelineEntry withReaction(
    ReactionKind kind, {
    required bool on,
    int? wantCount,
    int? helpfulCount,
    bool? myWant,
    bool? myHelpful,
  }) {
    final bool want = kind == ReactionKind.want;
    int bump(int count, bool was) => !was && on
        ? count + 1
        : was && !on
        ? (count - 1).clamp(0, count)
        : count;
    return TimelineEntry(
      id: id,
      author: author,
      authorName: authorName,
      authorIcon: authorIcon,
      mine: mine,
      placeId: placeId,
      placeName: placeName,
      verdict: verdict,
      createdAt: createdAt,
      comment: comment,
      order: order,
      rating: rating,
      isMock: isMock,
      genre: genre,
      photoId: photoId,
      wantCount:
          wantCount ??
          (want ? bump(this.wantCount, this.myWant) : this.wantCount),
      helpfulCount:
          helpfulCount ??
          (want ? this.helpfulCount : bump(this.helpfulCount, this.myHelpful)),
      myWant: myWant ?? (want ? on : this.myWant),
      myHelpful: myHelpful ?? (want ? this.myHelpful : on),
    );
  }
}

/// 口コミへの反応。値はサーバーの経路（/api/timeline/{id}/reactions/{value}）と同じ
enum ReactionKind {
  /// 行ってみたい
  want('want'),

  /// 参考になった
  helpful('helpful');

  const ReactionKind(this.value);
  final String value;
}

/// 口コミを報告する理由。値はサーバー（store.ReportReason）と同じ
enum ReportReason {
  inappropriate('inappropriate'),
  unrelated('unrelated'),
  personal('personal'),
  spam('spam'),
  other('other');

  const ReportReason(this.value);
  final String value;
}
