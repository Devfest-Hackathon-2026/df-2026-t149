import '../strings.dart';

/// 思い出ログ 1 件。サーバー（backend/internal/api/checkins.go の logView）と同じ JSON 形式
class MemoryLog {
  const MemoryLog({
    required this.id,
    required this.placeId,
    required this.placeName,
    required this.verdict,
    required this.createdAt,
    this.comment = '',
    this.order,
    this.photoPath,
    this.clientId,
    this.isPublic = false,
    this.rating,
    this.genre,
    this.photoId,
    this.wantCount = 0,
    this.helpfulCount = 0,
  });

  final String id;
  final String placeId;

  /// 場所の名前。サーバーが place ID から読んで返す。読めなかったときと圏外の一覧では空になる
  final String placeName;
  final Verdict verdict;
  final String comment;

  /// 何人目の訪問者だったか（チェックインの結果）
  final int? order;

  /// Cloud Storage 上の写真のパス（TODO(C): 写真の保存）
  final String? photoPath;

  /// 訪問した日時。後からチェックインしたときは滞在した日時になる
  final DateTime createdAt;

  /// アプリが記録ごとに決める値。応答を受け取れずに送り直しても、サーバーは二重に保存しない
  final String? clientId;

  /// 周辺のタイムラインに公開するか
  final bool isPublic;

  /// ★評価（1〜5）。★評価を入れる前の記録は null で、[stars] が当たりかハズレから決める
  final int? rating;

  /// 表示に使う★の数。★評価のない古い記録は、当たりを★4、ハズレを★2として扱う
  int get stars => rating ?? Verdict.defaultStars(verdict);

  /// スタンプの種類（[PlaceGenre.id]）。チェックインした場所のジャンルで決め、スタンプ帳で同じ形のスタンプを見せる。
  /// ジャンルを残す前の記録は null
  final String? genre;

  /// 記録に付けた写真の ID（POST /api/photos の応答）。写真のない記録は null
  final String? photoId;

  /// タイムラインでほかの人が付けた「行ってみたい」の数
  final int wantCount;

  /// タイムラインでほかの人が付けた「参考になった」の数
  final int helpfulCount;

  MemoryLog copyWith({
    String? id,
    String? clientId,
    bool? isPublic,
    int? rating,
    String? comment,
  }) => MemoryLog(
    id: id ?? this.id,
    placeId: placeId,
    placeName: placeName,
    // ★評価を変えたら、当たり・ハズレも★評価から決め直す（サーバーと同じ）
    verdict: rating == null ? verdict : Verdict.fromStars(rating),
    createdAt: createdAt,
    comment: comment ?? this.comment,
    order: order,
    photoPath: photoPath,
    clientId: clientId ?? this.clientId,
    isPublic: isPublic ?? this.isPublic,
    rating: rating ?? this.rating,
    genre: genre,
    photoId: photoId,
    wantCount: wantCount,
    helpfulCount: helpfulCount,
  );

  /// まだサーバーに送れていない記録の [id] の接頭辞
  static const String pendingPrefix = 'pending:';

  /// 端末に保存してあり、まだサーバーに送れていないか
  bool get isPending => id.startsWith(pendingPrefix);

  Map<String, dynamic> toJson() => {
    'placeId': placeId,
    'placeName': placeName,
    'verdict': verdict.value,
    'comment': comment,
    if (order != null) 'order': order,
    if (photoPath != null) 'photoPath': photoPath,
    'createdAt': createdAt.toIso8601String(),
    'visitedAt': createdAt.toUtc().toIso8601String(),
    if (clientId != null) 'clientId': clientId,
    'public': isPublic,
    if (rating != null) 'rating': rating,
    if (genre != null) 'genre': genre,
    if (photoId != null) 'photoId': photoId,
  };

  factory MemoryLog.fromJson(String id, Map<String, dynamic> j) => MemoryLog(
    id: id,
    placeId: j['placeId'] as String,
    placeName: j['placeName'] as String? ?? '',
    verdict: Verdict.of(j['verdict'] as String?),
    comment: j['comment'] as String? ?? '',
    order: (j['order'] as num?)?.toInt(),
    photoPath: j['photoPath'] as String?,
    clientId: j['clientId'] as String?,
    isPublic: j['public'] as bool? ?? false,
    rating: Verdict.validRating((j['rating'] as num?)?.toInt()),
    genre: _nonEmpty(j['genre']),
    photoId: _nonEmpty(j['photoId']),
    wantCount: (j['wantCount'] as num?)?.toInt() ?? 0,
    helpfulCount: (j['helpfulCount'] as num?)?.toInt() ?? 0,
    // サーバーは UTC で返すので、月日が日本時間とずれないよう端末の時刻に直す
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

/// 空の文字列と文字列以外を null にする（サーバーは値のない項目を空の文字列で返すことがある）
String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

/// 行ってみた結果。★評価（[MemoryLog.rating]）から決め、サーバーの集計と古い記録のために残す。
enum Verdict {
  hit('hit'),
  miss('miss');

  const Verdict(this.value);
  final String value;
  String get label => switch (this) {
    hit => l10n.verdictHit,
    miss => l10n.verdictMiss,
  };

  static Verdict of(String? v) => v == miss.value ? miss : hit;

  /// ★評価から当たりかハズレを決める。★3以上を当たりとして数える（サーバーと同じ）
  static Verdict fromStars(int stars) => stars >= 3 ? hit : miss;

  /// ★評価のない記録の★の数
  static int defaultStars(Verdict v) => v == hit ? 4 : 2;

  /// 1〜5 の★評価なら返し、それ以外は null
  static int? validRating(int? r) => r != null && r >= 1 && r <= 5 ? r : null;
}

/// ★評価の言葉。★の数に添えて見せる。
/// タイムラインでほかの人（お店や神社の人も含む）に見えるため、場所を悪く言う言葉は使わず、自分の感じ方として書く
String starsLabel(int stars) => switch (stars) {
  5 => l10n.stars5,
  4 => l10n.stars4,
  3 => l10n.stars3,
  2 => l10n.stars2,
  _ => l10n.stars1,
};

/// チェックインの結果
class CheckinResult {
  const CheckinResult({required this.order, required this.isNew});

  /// 通信できず、端末に保存したときの結果
  const CheckinResult.pending() : order = null, isNew = true;

  /// 何人目の訪問者か。順番はサーバーが決めるため、送信するまでは null
  final int? order;

  /// 今回はじめてチェックインしたか（2 回目以降は前回の順番を返す）
  final bool isNew;

  bool get isPending => order == null;
}
