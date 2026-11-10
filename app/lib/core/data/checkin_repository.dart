import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/memory_log.dart';
import '../models/place.dart';
import '../models/timeline_entry.dart';
import '../strings.dart';

/// 購読するたびに [create] で新しいストリームを作るストリーム。
///
/// 画面を作り直して同じストリームを購読し直すと、1回しか購読できないストリームは
/// 「Stream has already been listened to」で失敗する（タイムラインの「自分」と「周辺」を行き来したときに起きた）。
/// 購読ごとに作り直せば、何度購読しても、それぞれが最初の値から受け取れる
class RelistenableStream<T> extends Stream<T> {
  RelistenableStream(this.create);

  final Stream<T> Function() create;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => create().listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

/// 端末に保存していた記録を送信した結果
@immutable
class SyncReport {
  const SyncReport({this.checkins = const <SentCheckin>[], this.rejected = 0});

  /// 送信できたチェックイン
  final List<SentCheckin> checkins;

  /// サーバーが受け取らず、送るのをやめた記録の数
  final int rejected;
}

/// 送信できたチェックインと、そのときに決まった順番
@immutable
class SentCheckin {
  const SentCheckin({required this.placeName, required this.order});

  final String placeName;
  final int order;
}

/// 通信できないときの記録を端末に保存できなかったことを表す
class LocalSaveException implements Exception {
  const LocalSaveException();

  @override
  String toString() => l10n.errorSaveLocal;
}

/// チェックインと思い出ログの保存先（担当：C）。
///
/// 画面はこのインターフェースだけを使う。Firebase の設定前は
/// [LocalCheckinRepository] で動き、設定後は API サーバーに保存する版に差し替わる
abstract class CheckinRepository {
  /// その場所の何人目の訪問者かを決めて記録する。
  /// 同じ人が 2 回目にチェックインしても、順番は 1 回目のまま返す。
  /// 通信できないときは端末に保存し、[CheckinResult.pending] の結果を返す。
  /// [lat] と [lng] は現在地、または後からチェックインするときの滞在の位置で、サーバーが場所との距離を確かめる。
  /// [visitedAt] は訪問した日時で、省略すると現在の日時になる
  Future<CheckinResult> checkIn(
    Place place, {
    required double lat,
    required double lng,
    DateTime? visitedAt,
  });

  /// その場所の訪問者数（まだ誰も来ていなければ 0）
  Future<int> visitorCount(String placeId);

  /// 思い出ログを残す。通信できないときは端末に保存する
  Future<void> addLog(MemoryLog log);

  /// 自分の思い出ログ（新しい順）。
  ///
  /// 場所の名前はサーバーが一覧を読むたびに Places API から読み、1人あたりの1日の上限がある。
  /// 名前を表示しない画面（実績、残す前の記録の確認）は [withNames] を false にして、上限を使わない
  Stream<List<MemoryLog>> watchLogs({bool withNames = true});

  /// 自分の記録の公開状態を変える。場所の名前を読み直さないよう、一覧の読み直しは通知しない
  Future<void> setLogPublic(MemoryLog log, {required bool isPublic});

  /// 自分の記録の★評価とひとことを直し、直した後の記録を返す。
  /// 場所の名前を読み直さないよう、一覧の読み直しは通知しない（画面が手元で置き換える）
  Future<MemoryLog> editLog(
    MemoryLog log, {
    required int rating,
    required String comment,
  });

  /// 指定した地点の周辺で公開された記録（新しい順）。[nationwide] なら場所を問わず全国の新着
  Future<List<TimelineEntry>> nearbyTimeline({
    required double lat,
    required double lng,
    bool nationwide = false,
  });

  /// 公開された記録を理由つきで報告する
  Future<void> reportEntry(
    String entryId, {
    required ReportReason reason,
    String note = '',
  });

  /// 公開された記録に反応（行ってみたい・参考になった）を付け外しし、反応した後の記録を返す
  Future<TimelineEntry> react(
    TimelineEntry entry,
    ReactionKind kind, {
    required bool on,
  });

  /// 記録に付ける写真を上げ、写真の ID を返す。通信できないときは例外を投げる（写真なしで残してもらう）
  Future<String> uploadPhoto(Uint8List bytes, {required String contentType});

  /// 写真の中身
  Future<Uint8List> photo(String photoId);

  /// 端末に保存してあり、まだ送信していない記録の数
  ValueListenable<int> get pendingCount;

  /// 端末に保存した記録を送信する
  Future<SyncReport> sync();

  /// 記録を読み書きする利用者を [uid] に切り替える。ログインしていないときは null を渡す
  void setUser(String? uid);
}

/// 端末だけに保存する版。[prefs] を渡さないときは、アプリを閉じると消える。
class LocalCheckinRepository implements CheckinRepository {
  LocalCheckinRepository({SharedPreferences? prefs}) : _prefs = prefs {
    try {
      _load();
    } catch (error) {
      // 読めない記録のために起動できなくなるよりは、記録を空にして動かす
      debugPrint('端末の記録を読めませんでした: $error');
    }
  }

  int _nextId = 0;

  void _load() {
    final String? raw = _prefs?.getString(_key);
    if (raw == null) {
      return;
    }
    final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;
    _mine.addAll((j['mine'] as Map).cast<String, int>());
    _logs.addAll(<MemoryLog>[
      for (final Object? e in j['logs'] as List<Object?>)
        MemoryLog.fromJson(
          (e! as Map)['id'] as String,
          (e as Map).cast<String, dynamic>(),
        ),
    ]);
    for (final String placeId in _mine.keys) {
      _visitors[placeId] = _mine[placeId]!;
    }
  }

  static const String _key = 'localCheckins';

  final SharedPreferences? _prefs;
  final Map<String, int> _visitors = <String, int>{};
  final Map<String, int> _mine = <String, int>{};
  final List<MemoryLog> _logs = <MemoryLog>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final ValueNotifier<int> _pendingCount = ValueNotifier<int>(0);

  void _save() => _prefs?.setString(
    _key,
    jsonEncode(<String, dynamic>{
      'mine': _mine,
      'logs': <Map<String, dynamic>>[
        for (final MemoryLog l in _logs)
          <String, dynamic>{...l.toJson(), 'id': l.id},
      ],
    }),
  );

  @override
  Future<CheckinResult> checkIn(
    Place place, {
    required double lat,
    required double lng,
    DateTime? visitedAt,
  }) async {
    final int? existing = _mine[place.id];
    if (existing != null) {
      return CheckinResult(order: existing, isNew: false);
    }
    final int order = (_visitors[place.id] ?? 0) + 1;
    _visitors[place.id] = order;
    _mine[place.id] = order;
    _save();
    return CheckinResult(order: order, isNew: true);
  }

  @override
  Future<int> visitorCount(String placeId) async => _visitors[placeId] ?? 0;

  @override
  Future<void> addLog(MemoryLog log) async {
    _logs.insert(
      0,
      log.id.isEmpty ? log.copyWith(id: 'local_${_nextId++}') : log,
    );
    _save();
    _changes.add(null);
  }

  @override
  Stream<List<MemoryLog>> watchLogs({bool withNames = true}) =>
      RelistenableStream<List<MemoryLog>>(_watchLogs);

  Stream<List<MemoryLog>> _watchLogs() async* {
    yield List<MemoryLog>.of(_logs);
    await for (final void _ in _changes.stream) {
      yield List<MemoryLog>.of(_logs);
    }
  }

  @override
  Future<void> setLogPublic(MemoryLog log, {required bool isPublic}) async {
    final int i = _logs.indexWhere((MemoryLog l) => l.id == log.id);
    if (i >= 0) {
      _logs[i] = _logs[i].copyWith(isPublic: isPublic);
      _save();
    }
  }

  @override
  Future<MemoryLog> editLog(
    MemoryLog log, {
    required int rating,
    required String comment,
  }) async {
    final int i = _logs.indexWhere((MemoryLog l) => l.id == log.id);
    if (i < 0) {
      return log.copyWith(rating: rating, comment: comment);
    }
    // 保存してある今の中身を直し、公開状態などは渡された古い記録で戻さない
    _logs[i] = _logs[i].copyWith(rating: rating, comment: comment);
    _save();
    return _logs[i];
  }

  /// 端末だけで動くときは、自分が公開した記録と架空の投稿を見せる
  @override
  Future<List<TimelineEntry>> nearbyTimeline({
    required double lat,
    required double lng,
    bool nationwide = false,
  }) async => <TimelineEntry>[
    for (final MemoryLog l in _logs)
      if (l.isPublic)
        TimelineEntry(
          id: l.id,
          author: '',
          mine: true,
          placeId: l.placeId,
          placeName: l.placeName,
          verdict: l.verdict,
          rating: l.rating,
          comment: l.comment,
          order: l.order,
          createdAt: l.createdAt,
          genre: l.genre,
          photoId: l.photoId,
        ),
    for (final TimelineEntry e in _sampleEntries)
      if (!_reported.contains(e.id)) _reacted[e.id] ?? e,
  ];

  final Set<String> _reported = <String>{};

  @override
  Future<void> reportEntry(
    String entryId, {
    required ReportReason reason,
    String note = '',
  }) async => _reported.add(entryId);

  /// 架空の投稿への反応。アプリを閉じると消える
  final Map<String, TimelineEntry> _reacted = <String, TimelineEntry>{};

  @override
  Future<TimelineEntry> react(
    TimelineEntry entry,
    ReactionKind kind, {
    required bool on,
  }) async => _reacted[entry.id] = (_reacted[entry.id] ?? entry).withReaction(
    kind,
    on: on,
  );

  /// 端末だけで動くときの写真。アプリを閉じると消える
  final Map<String, Uint8List> _photos = <String, Uint8List>{};

  @override
  Future<String> uploadPhoto(
    Uint8List bytes, {
    required String contentType,
  }) async {
    final String id = 'local_photo_${_photos.length}';
    _photos[id] = bytes;
    return id;
  }

  @override
  Future<Uint8List> photo(String photoId) async =>
      _photos[photoId] ?? (throw StateError(l10n.photoUnavailable));

  static final List<TimelineEntry> _sampleEntries = <TimelineEntry>[
    TimelineEntry(
      id: 'sample_1',
      author: 'A1B2C3',
      authorName: '古書めぐり',
      authorIcon: 'local_cafe',
      mine: false,
      placeId: 'mock_02',
      placeName: '路地裏の古書喫茶',
      verdict: Verdict.hit,
      rating: 5,
      comment: 'おすすめの本を教えてもらえた',
      order: 3,
      createdAt: DateTime(2026, 11, 7),
      isMock: true,
    ),
    TimelineEntry(
      id: 'sample_2',
      author: 'D4E5F6',
      authorName: 'さんぽ部',
      authorIcon: 'hiking',
      mine: false,
      placeId: 'mock_01',
      placeName: '坂の上の小さな祠',
      verdict: Verdict.miss,
      rating: 2,
      comment: '閉まってた',
      order: 5,
      createdAt: DateTime(2026, 11, 6),
      isMock: true,
    ),
  ];

  @override
  ValueListenable<int> get pendingCount => _pendingCount;

  @override
  Future<SyncReport> sync() async => const SyncReport();

  // 開発用のログインだけで使い、利用者は常に同じ1人なので切り替えない
  @override
  void setUser(String? uid) {}
}
