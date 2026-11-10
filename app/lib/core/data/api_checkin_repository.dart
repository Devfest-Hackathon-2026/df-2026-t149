import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/uramichi_api.dart';
import '../models/memory_log.dart';
import '../models/place.dart';
import '../models/timeline_entry.dart';
import 'checkin_repository.dart';
import '../strings.dart';

/// 通信できるようになってから送る記録 1 件
class _Pending {
  const _Pending.checkin({
    required String this.placeId,
    required String this.placeName,
    required double this.lat,
    required double this.lng,
    required DateTime this.visitedAt,
  }) : log = null;

  const _Pending.log(MemoryLog this.log)
    : placeId = null,
      placeName = null,
      lat = null,
      lng = null,
      visitedAt = null;

  factory _Pending.fromJson(Map<String, dynamic> j) => switch (j['log']) {
    final Map<String, dynamic> log => _Pending.log(
      MemoryLog.fromJson(log['id'] as String, log),
    ),
    _ => _Pending.checkin(
      placeId: j['placeId'] as String,
      placeName: j['placeName'] as String,
      lat: (j['lat'] as num).toDouble(),
      lng: (j['lng'] as num).toDouble(),
      visitedAt: DateTime.parse(j['visitedAt'] as String),
    ),
  };

  final String? placeId;
  final String? placeName;
  final double? lat;
  final double? lng;
  final DateTime? visitedAt;
  final MemoryLog? log;

  Map<String, dynamic> toJson() => log == null
      ? <String, dynamic>{
          'placeId': placeId,
          'placeName': placeName,
          'lat': lat,
          'lng': lng,
          'visitedAt': visitedAt!.toUtc().toIso8601String(),
        }
      : <String, dynamic>{
          'log': <String, dynamic>{...log!.toJson(), 'id': log!.id},
        };
}

/// API サーバーに保存する版。Firestore を読み書きするのはサーバーだけで、アプリは API だけを呼ぶ
///
/// 通信できないときは、チェックインと思い出ログを端末に保存し、[sync] で記録した順に送る。
/// 端末に保存する記録と最後に読めた一覧はログインした利用者ごとに分け、[setUser] で切り替える。
/// 送信するときは記録した利用者の ID トークンだけを使い、別の利用者がログインしていれば送らない。
/// ダミーデータを使う設定のときと、ダミーの場所の記録は、サーバーを呼ばずに端末のメモリだけで扱う
class ApiCheckinRepository implements CheckinRepository {
  ApiCheckinRepository({
    required UramichiApi api,
    required Future<String> Function(String uid) idTokenFor,
    SharedPreferences? prefs,
    String? uid,
  }) : _api = api,
       _idTokenFor = idTokenFor,
       _prefs = prefs {
    // 利用者ごとに分ける前の版が保存した記録は、誰の記録か分からず送れないため消す
    _prefs?.remove(_pendingKey);
    _prefs?.remove(_logsKey);
    _switchTo(uid);
  }

  static const String _pendingKey = 'pendingCheckins';
  static const String _logsKey = 'cachedLogs';

  static String _pendingKeyOf(String uid) => '$_pendingKey.$uid';
  static String _logsKeyOf(String uid) => '$_logsKey.$uid';

  final UramichiApi _api;

  /// 指定した利用者の Firebase の ID トークンを返す。別の利用者がログインしていれば例外を投げる
  // ID トークンは期限が切れるため、起動時に受け取った値を保持せず、呼び出しのたびに取得する
  final Future<String> Function(String uid) _idTokenFor;
  final SharedPreferences? _prefs;
  LocalCheckinRepository _demo = LocalCheckinRepository();

  /// 記録を読み書きしている利用者。ログインしていなければ null
  String? _uid;
  final List<_Pending> _pending = <_Pending>[];
  final ValueNotifier<int> _pendingCount = ValueNotifier<int>(0);
  final StreamController<void> _changes = StreamController<void>.broadcast();
  Future<SyncReport>? _syncing;

  @override
  void setUser(String? uid) {
    if (uid == _uid) {
      return;
    }
    _switchTo(uid);
    _changes.add(null);
  }

  void _switchTo(String? uid) {
    _uid = uid;
    _pending.clear();
    _syncing = null;
    _demo = LocalCheckinRepository();
    if (uid != null) {
      try {
        _load(uid);
      } catch (error) {
        // 読めない記録のために起動できなくなるよりは、記録を空にして動かす
        debugPrint('未送信の記録を読めませんでした: $error');
      }
    }
    _pendingCount.value = _pending.length;
  }

  String _requireUid() => _uid ?? (throw ApiException.signedOut);

  void _load(String uid) {
    final String? raw = _prefs?.getString(_pendingKeyOf(uid));
    if (raw == null) {
      return;
    }
    _pending.addAll(<_Pending>[
      for (final Object? e in jsonDecode(raw) as List<Object?>)
        _Pending.fromJson((e! as Map).cast<String, dynamic>()),
    ]);
  }

  Future<void> _writePending(String uid) async {
    final bool? saved = await _prefs?.setString(
      _pendingKeyOf(uid),
      jsonEncode(_pending.map((_Pending p) => p.toJson()).toList()),
    );
    if (saved == false) {
      throw const LocalSaveException();
    }
  }

  /// 記録を [uid] の未送信の一覧に加え、端末への保存が終わってから返す
  ///
  /// 保存できなかった記録を一覧に残すと、アプリを閉じたときに消える記録を保留中と表示してしまうため取り除く
  Future<void> _enqueue(String uid, _Pending record) async {
    // 待っている間に別の利用者へ切り替わったときは、その利用者の一覧に加えない
    if (_uid != uid) {
      throw ApiException.signedOut;
    }
    _pending.add(record);
    try {
      await _writePending(uid);
    } catch (error) {
      _pending.remove(record);
      debugPrint('未送信の記録を保存できませんでした: $error');
      throw const LocalSaveException();
    }
    _pendingCount.value = _pending.length;
  }

  /// 送信中なら終わるまで待つ。送信中の記録を書き換えると、送った後に一覧から取り除かれ、直した内容が届かないため
  Future<void> _waitForSending() async {
    final Future<SyncReport>? running = _syncing;
    if (running != null) {
      try {
        await running;
      } catch (_) {
        // 送れなくても、未送信の一覧に残った記録を直せばよい
      }
    }
  }

  /// 送り終えた未送信の記録の、サーバーでの ID。サーバーは clientId から ID を決める（backend の newLogID）
  static String _sentLogId(MemoryLog log) {
    final String? clientId = log.clientId;
    if (clientId == null) {
      throw StateError(l10n.errorLogIdUnknown);
    }
    return 'lg_$clientId';
  }

  /// 送信を終えた記録を未送信の一覧から取り除く
  // チェックインは同じ順番を返し、思い出ログは clientId で重複を防ぐので、書き込みに失敗して次回に送り直しても二重に保存されない
  Future<void> _removeSent(String uid) async {
    _pending.removeAt(0);
    _pendingCount.value = _pending.length;
    try {
      await _writePending(uid);
    } catch (error) {
      debugPrint('送信済みの記録を端末から消せませんでした: $error');
    }
  }

  @override
  Future<CheckinResult> checkIn(
    Place place, {
    required double lat,
    required double lng,
    DateTime? visitedAt,
  }) async {
    if (_api.usesMockOnly || place.isMock) {
      return _demo.checkIn(place, lat: lat, lng: lng);
    }
    final String uid = _requireUid();
    final DateTime at = visitedAt ?? DateTime.now();
    await sync();
    // 送れていない記録が残っているときは通信できない状態なので、もう一度待たせずに端末へ保存する
    if (_pending.isEmpty) {
      try {
        return await _api.postCheckin(
          place.id,
          lat: lat,
          lng: lng,
          visitedAt: at,
          idToken: await _idTokenFor(uid),
        );
      } catch (error) {
        if (!UramichiApi.isUnavailable(error)) {
          rethrow;
        }
      }
    }
    final bool queued = _pending.any((_Pending p) => p.placeId == place.id);
    if (!queued) {
      await _enqueue(
        uid,
        _Pending.checkin(
          placeId: place.id,
          placeName: place.name,
          lat: lat,
          lng: lng,
          visitedAt: at,
        ),
      );
    }
    return const CheckinResult.pending();
  }

  @override
  Future<int> visitorCount(String placeId) async =>
      _api.usesMockOnly || Place.isMockId(placeId)
      ? _demo.visitorCount(placeId)
      : _api.fetchVisitorCount(
          placeId,
          idToken: await _idTokenFor(_requireUid()),
        );

  @override
  Future<void> addLog(MemoryLog log) async {
    if (_api.usesMockOnly || Place.isMockId(log.placeId)) {
      await _demo.addLog(log);
      _changes.add(null);
      return;
    }
    final String uid = _requireUid();
    // 応答を受け取れなかった送信を端末に残して送り直すとき、サーバーが同じ記録と分かるよう、送る前に決める
    final String clientId = _newClientId();
    final MemoryLog withId = log.copyWith(
      id: '${MemoryLog.pendingPrefix}$clientId',
      clientId: clientId,
    );
    // 送信していないチェックインが残っていると、サーバーが not_checked_in で断るため先に送る
    await sync();
    if (_pending.isEmpty) {
      try {
        await _api.postLog(withId, idToken: await _idTokenFor(uid));
        _changes.add(null);
        return;
      } catch (error) {
        if (!UramichiApi.isUnavailable(error)) {
          rethrow;
        }
      }
    }
    await _enqueue(uid, _Pending.log(withId));
    _changes.add(null);
  }

  @override
  Future<void> setLogPublic(MemoryLog log, {required bool isPublic}) async {
    if (_api.usesMockOnly || Place.isMockId(log.placeId)) {
      return _demo.setLogPublic(log, isPublic: isPublic);
    }
    final String uid = _requireUid();
    String serverId = log.id;
    if (log.isPending) {
      await _waitForSending();
      final int i = _pending.indexWhere((_Pending p) => p.log?.id == log.id);
      if (i >= 0) {
        // 画面が持つ記録は読み込んだ時点のものなので、端末に残した今の中身の公開状態だけを変える
        _pending[i] = _Pending.log(
          _pending[i].log!.copyWith(isPublic: isPublic),
        );
        await _writePending(uid);
        return;
      }
      serverId = _sentLogId(log);
    }
    await _api.patchLogPublic(
      serverId,
      isPublic: isPublic,
      idToken: await _idTokenFor(uid),
    );
  }

  @override
  Future<MemoryLog> editLog(
    MemoryLog log, {
    required int rating,
    required String comment,
  }) async {
    if (_api.usesMockOnly || Place.isMockId(log.placeId)) {
      return _demo.editLog(log, rating: rating, comment: comment);
    }
    final String uid = _requireUid();
    final MemoryLog edited = log.copyWith(rating: rating, comment: comment);
    String serverId = log.id;
    // まだ送っていない記録は、送る前の中身を直す
    if (log.isPending) {
      await _waitForSending();
      final int i = _pending.indexWhere((_Pending p) => p.log?.id == log.id);
      if (i >= 0) {
        // 画面が持つ記録は読み込んだ時点のものなので、端末に残した今の中身の★評価とひとことだけを変える。
        // 渡された記録で置き換えると、後から変えた公開状態が元に戻る
        final MemoryLog current = _pending[i].log!.copyWith(
          rating: rating,
          comment: comment,
        );
        _pending[i] = _Pending.log(current);
        await _writePending(uid);
        return current;
      }
      // 直している間に送り終えていたら、サーバーの記録を直す
      serverId = _sentLogId(log);
    }
    await _api.patchLog(
      serverId,
      rating: rating,
      comment: comment,
      idToken: await _idTokenFor(uid),
    );
    return edited.copyWith(id: serverId);
  }

  @override
  Future<List<TimelineEntry>> nearbyTimeline({
    required double lat,
    required double lng,
    bool nationwide = false,
  }) async {
    if (_api.usesMockOnly) {
      return _demo.nearbyTimeline(lat: lat, lng: lng, nationwide: nationwide);
    }
    return _api.fetchTimeline(
      lat: lat,
      lng: lng,
      nationwide: nationwide,
      idToken: await _idTokenFor(_requireUid()),
    );
  }

  @override
  Future<void> reportEntry(
    String entryId, {
    required ReportReason reason,
    String note = '',
  }) async {
    if (_api.usesMockOnly) {
      return _demo.reportEntry(entryId, reason: reason, note: note);
    }
    await _api.reportEntry(
      entryId,
      reason: reason,
      note: note,
      idToken: await _idTokenFor(_requireUid()),
    );
  }

  @override
  Future<TimelineEntry> react(
    TimelineEntry entry,
    ReactionKind kind, {
    required bool on,
  }) async {
    if (_api.usesMockOnly || entry.isMock) {
      return _demo.react(entry, kind, on: on);
    }
    return _api.react(
      entry,
      kind,
      on: on,
      idToken: await _idTokenFor(_requireUid()),
    );
  }

  @override
  Future<String> uploadPhoto(
    Uint8List bytes, {
    required String contentType,
  }) async {
    if (_api.usesMockOnly) {
      return _demo.uploadPhoto(bytes, contentType: contentType);
    }
    return _api.uploadPhoto(
      bytes,
      contentType: contentType,
      idToken: await _idTokenFor(_requireUid()),
    );
  }

  @override
  Future<Uint8List> photo(String photoId) async {
    if (_api.usesMockOnly || photoId.startsWith('local_photo_')) {
      return _demo.photo(photoId);
    }
    return _api.fetchPhoto(photoId, idToken: await _idTokenFor(_requireUid()));
  }

  static final Random _random = Random();

  static String _newClientId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(0x7fffffff)}';

  @override
  ValueListenable<int> get pendingCount => _pendingCount;

  // 再開のたびの送信と、画面の操作からの送信が重なっても二重に送らないよう、実行中の処理を共有する
  @override
  Future<SyncReport> sync() {
    final String? uid = _uid;
    if (uid == null || _pending.isEmpty || _api.usesMockOnly) {
      return Future<SyncReport>.value(const SyncReport());
    }
    final Future<SyncReport>? running = _syncing;
    if (running != null) {
      return running;
    }
    late final Future<SyncReport> started;
    // 利用者を切り替えた後に前の利用者の送信が終わっても、切り替えた後の送信の共有を解かない
    started = _send(uid).whenComplete(() {
      if (identical(_syncing, started)) {
        _syncing = null;
      }
    });
    return _syncing = started;
  }

  Future<SyncReport> _send(String uid) async {
    final List<SentCheckin> sent = <SentCheckin>[];
    int rejected = 0;
    // 送信の途中で利用者が切り替わったら、切り替えた後の一覧に手を付けずにやめる
    while (_uid == uid && _pending.isNotEmpty) {
      final _Pending next = _pending.first;
      try {
        final String token = await _idTokenFor(uid);
        if (next.log case final MemoryLog log) {
          await _api.postLog(log, idToken: token);
        } else {
          final CheckinResult result = await _api.postCheckin(
            next.placeId!,
            lat: next.lat!,
            lng: next.lng!,
            visitedAt: next.visitedAt!,
            idToken: token,
          );
          sent.add(
            SentCheckin(placeName: next.placeName!, order: result.order!),
          );
        }
      } on ApiException catch (error) {
        if (UramichiApi.isUnavailable(error) || !_isRejection(error)) {
          break;
        }
        // 送り直しても受け取られない記録を残すと、後ろの記録まで送れなくなる
        debugPrint('送信をやめた記録があります: ${error.code}');
        rejected++;
      } catch (error) {
        if (UramichiApi.isUnavailable(error)) {
          break;
        }
        rethrow;
      }
      if (_uid != uid) {
        break;
      }
      await _removeSent(uid);
    }
    if (sent.isNotEmpty || rejected > 0) {
      _changes.add(null);
    }
    return SyncReport(checkins: sent, rejected: rejected);
  }

  // 401 と 403 はログインをやり直せば通り、429 と 5xx は時間を置けば通る
  static bool _isRejection(ApiException error) =>
      error.status >= 400 &&
      error.status < 500 &&
      error.status != 401 &&
      error.status != 403 &&
      error.status != 429;

  // API には変更の通知がないため、このアプリから追加したときと、利用者を切り替えたときに読み直す
  // async* で書くと最初の読み込みの間は通知を購読しておらず、その間の追加を読み落とすため、購読してから読み込む
  @override
  Stream<List<MemoryLog>> watchLogs({bool withNames = true}) =>
      RelistenableStream<List<MemoryLog>>(() => _watchLogs(withNames));

  Stream<List<MemoryLog>> _watchLogs(bool withNames) {
    late final StreamController<List<MemoryLog>> controller;
    StreamSubscription<void>? changes;

    Future<void> read() async {
      final String? uid = _uid;
      try {
        final List<MemoryLog> logs = await _readLogs(uid, withNames);
        // 読んでいる間に利用者が切り替わったときは、前の利用者の一覧を表示しない
        if (_uid == uid) {
          controller.add(logs);
        }
      } catch (error, stackTrace) {
        if (_uid == uid) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller = StreamController<List<MemoryLog>>(
      onListen: () {
        changes = _changes.stream.listen((void _) => read());
        read();
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  Future<List<MemoryLog>> _readLogs(String? uid, bool withNames) async {
    if (_api.usesMockOnly) {
      return _demo.watchLogs().first;
    }
    if (uid == null) {
      return const <MemoryLog>[];
    }
    final List<MemoryLog> pending = <MemoryLog>[
      for (final _Pending p in _pending.reversed) ?p.log,
      ...await _demo.watchLogs().first,
    ];
    try {
      final List<MemoryLog> logs = await _api.fetchLogs(
        idToken: await _idTokenFor(uid),
        withNames: withNames,
      );
      _prefs?.setString(
        _logsKeyOf(uid),
        jsonEncode(<Map<String, dynamic>>[
          for (final MemoryLog l in logs)
            <String, dynamic>{...l.toJson(), 'id': l.id}..remove('placeName'),
        ]),
      );
      return <MemoryLog>[...pending, ...logs];
    } catch (error) {
      if (!UramichiApi.isUnavailable(error)) {
        rethrow;
      }
      return <MemoryLog>[...pending, ..._cachedLogs(uid)];
    }
  }

  // 自分の記録を圏外でも見られるよう、最後に読めた一覧を返す
  // 場所の名前は Places API の内容で端末にも保存できないため、この一覧には名前がない
  List<MemoryLog> _cachedLogs(String uid) {
    final String? raw = _prefs?.getString(_logsKeyOf(uid));
    if (raw == null) {
      return const <MemoryLog>[];
    }
    return <MemoryLog>[
      for (final Object? e in jsonDecode(raw) as List<Object?>)
        MemoryLog.fromJson(
          (e! as Map)['id'] as String,
          (e as Map).cast<String, dynamic>(),
        ),
    ];
  }
}
