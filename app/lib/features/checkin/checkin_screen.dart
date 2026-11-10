import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/api/uramichi_api.dart';
import '../../core/data/checkin_repository.dart';
import '../../core/haptics.dart';
import '../../core/location/visit_recorder.dart';
import '../../core/models/place_genre.dart';
import '../../core/models/memory_log.dart';
import '../../core/models/place.dart';
import '../../core/services.dart';
import '../../core/widgets/log_photo.dart';
import '../../core/widgets/stamp_celebration.dart';
import '../../core/widgets/star_rating.dart';
import '../../core/widgets/state_view.dart';
import '../achievements/achievements.dart';
import 'badges.dart';
import 'checkin_celebration.dart';
import '../../core/strings.dart';

String _errorMessage(Object error) => switch (error) {
  ApiException(:final message) => message,
  LocalSaveException() => l10n.errorSaveLocal,
  TimeoutException() => l10n.errorServerTimeout,
  http.ClientException() => l10n.errorServerUnreachable,
  _ => l10n.errorGeneric,
};

/// チェックイン：何人目かを見せ、★評価と公開範囲を選んで残す
class CheckinScreen extends StatefulWidget {
  const CheckinScreen({
    super.key,
    required this.place,
    required this.lat,
    required this.lng,
    this.visit,
  });

  final Place place;
  final double lat;
  final double lng;
  final Visit? visit;

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  Future<CheckinResult>? _checkin;

  /// 場所のジャンルで決めた、チェックインスタンプの種類
  StampDesign get _design => StampDesign.of(PlaceGenre.of(widget.place));

  /// 残す前の記録。新しく解除した実績を見つけるために、チェックインと並行して読む。
  /// 読み終わる前に残したときは、残すのを待たせず、実績の演出だけを省く
  bool _readingLogs = false;
  List<MemoryLog>? _logsBefore;
  final TextEditingController _comment = TextEditingController();
  int? _rating;
  bool _isPublic = false;
  bool _saving = false;
  PickedPhoto? _photo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkin ??= _run();
    if (!_readingLogs) {
      _readingLogs = true;
      _readLogs();
    }
  }

  Future<void> _readLogs() async {
    try {
      _logsBefore = await Services.of(
        context,
      ).checkins.watchLogs(withNames: false).first;
    } catch (_) {
      // 読めなくても記録は残せる。実績の演出だけを諦める
    }
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<CheckinResult> _run() async {
    final Services services = Services.of(context);
    final CheckinResult result = await services.checkins.checkIn(
      widget.place,
      lat: widget.lat,
      lng: widget.lng,
      visitedAt: widget.visit?.startedAt,
    );
    services.visits.markCheckedIn(widget.place.lat, widget.place.lng);
    if (widget.visit case final Visit visit) {
      services.visits.markCheckedIn(visit.lat, visit.lng);
    }
    return result;
  }

  Future<void> _save(CheckinResult result, int rating) async {
    setState(() => _saving = true);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final CheckinRepository checkins = Services.of(context).checkins;
    // 写真は記録より先に上げる。上げられないときは写真なしで残し、記録が残らないことは避ける
    String? photoId;
    if (_photo case final PickedPhoto photo) {
      try {
        photoId = await checkins.uploadPhoto(
          photo.bytes,
          contentType: photo.contentType,
        );
      } catch (_) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.photoUploadFailed)));
      }
    }
    if (!mounted) {
      return;
    }
    final MemoryLog log = MemoryLog(
      id: '',
      placeId: widget.place.id,
      placeName: widget.place.name,
      verdict: Verdict.fromStars(rating),
      rating: rating,
      comment: _comment.text.trim(),
      order: result.order,
      createdAt: widget.visit?.startedAt ?? DateTime.now(),
      isPublic: _isPublic,
      genre: (PlaceGenre.of(widget.place) ?? PlaceGenre.other).id,
      photoId: photoId,
    );
    final List<MemoryLog>? before = _logsBefore;
    try {
      await checkins.addLog(log);
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(_errorMessage(error))));
        setState(() => _saving = false);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final List<AchievementProgress> unlocked = before == null
        ? const <AchievementProgress>[]
        : newlyUnlocked(before, <MemoryLog>[...before, log]);
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => CheckinCelebrationScreen(
          log: log,
          unlocked: unlocked,
          level: levelOf(result),
          design: _design,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.place.name)),
      body: FutureBuilder<CheckinResult>(
        future: _checkin,
        builder: (BuildContext context, AsyncSnapshot<CheckinResult> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return StateView(
              icon: Icons.cloud_off_outlined,
              title: _errorMessage(snap.error!),
              primary: StateViewAction(
                l10n.retry,
                () => setState(() {
                  _checkin = _run();
                }),
                icon: Icons.refresh,
              ),
            );
          }
          final CheckinResult result = snap.data!;
          final int? rating = _rating;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  16 + MediaQuery.paddingOf(context).bottom,
                ),
                children: <Widget>[
                  _OrderView(result: result, design: _design),
                  const SizedBox(height: 16),
                  Text(
                    l10n.howWasIt,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  StarRatingInput(
                    value: rating,
                    onChanged: (int r) => setState(() => _rating = r),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _comment,
                    maxLength: 140,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(hintText: l10n.comment),
                  ),
                  PhotoField(
                    photo: _photo,
                    onChanged: (PickedPhoto? p) => setState(() => _photo = p),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: <ButtonSegment<bool>>[
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.lock_outline),
                        label: Text(l10n.visibilityPrivate),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        icon: Icon(Icons.public),
                        label: Text(l10n.visibilityPublic),
                      ),
                    ],
                    selected: <bool>{_isPublic},
                    onSelectionChanged: (Set<bool> s) =>
                        setState(() => _isPublic = s.first),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: rating == null || _saving
                        ? null
                        : () => _save(result, rating),
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(l10n.record),
                  ),
                  SizedBox(height: theme.textTheme.bodySmall?.fontSize ?? 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// チェックインの結果から、祝い方の強さを決める
CelebrationLevel levelOf(CheckinResult result) => switch (result) {
  CheckinResult(order: 1) => CelebrationLevel.pioneer,
  CheckinResult(isNew: true) => CelebrationLevel.newPlace,
  _ => CelebrationLevel.revisit,
};

/// 何人目かを、押される「チェックインスタンプ」で見せる。圏外で順番が決まっていないときは送信待ちのアイコンを見せる
class _OrderView extends StatelessWidget {
  const _OrderView({required this.result, required this.design});

  final CheckinResult result;
  final StampDesign design;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int? order = result.order;
    // 通信できず順番が決まっていなくても、チェックインしたら必ずスタンプを押す
    if (order == null) {
      return Column(
        children: <Widget>[
          Center(
            child: StampCelebration(
              level: CelebrationLevel.newPlace,
              label: l10n.stampRecorded,
              caption: l10n.stampPending,
              size: 260,
              design: design,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.checkinPendingOrder,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    final String? badge = badgeForOrder(order);
    return Column(
      children: <Widget>[
        Center(
          child: StampCelebration(
            level: levelOf(result),
            label: l10n.orderLabel(order),
            caption: result.isNew ? l10n.stampFirstVisit : l10n.stampRevisit,
            size: 260,
            design: design,
          ),
        ),
        if (badge != null) ...<Widget>[
          const SizedBox(height: 4),
          Chip(avatar: const Icon(Icons.military_tech), label: Text(badge)),
        ],
      ],
    );
  }
}
