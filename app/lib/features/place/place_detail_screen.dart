import '../../core/widgets/google_maps_notice.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/checkin_repository.dart';
import '../../core/geo.dart';
import '../../core/location/location_service.dart';
import '../../core/models/place.dart';
import '../../core/models/place_photo.dart';
import '../../core/services.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/favorite_button.dart';
import '../../core/widgets/mock_banner.dart';
import '../../core/widgets/place_photos.dart';
import '../../core/widgets/place_labels.dart';
import '../../core/widgets/places_map.dart';
import '../../core/widgets/stamp_press.dart';
import '../../core/widgets/title_badge.dart';
import '../checkin/checkin_screen.dart';
import '../../core/strings.dart';

/// 場所の詳細。ここからチェックインの画面へ進む
class PlaceDetailScreen extends StatefulWidget {
  const PlaceDetailScreen({
    super.key,
    required this.place,
    this.origin,
    this.distanceMeters,
    this.isMock = false,
  });

  final Place place;

  /// 「代わりに行くならここ」から開いたときの有名スポット。距離の基準として名前を表示する
  final Place? origin;

  /// 表示する距離。null なら [Place.distanceMeters] を使う
  final int? distanceMeters;

  final bool isMock;

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  Future<int>? _visitors;
  Future<List<PlacePhoto>>? _photos;
  bool _locating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Services services = Services.of(context);
    final CheckinRepository checkins = services.checkins;
    _visitors ??= checkins.visitorCount(widget.place.id);
    // ダミーの場所には写真がないので、読みに行かない
    if (!widget.isMock && !widget.place.isMock) {
      _photos ??= services.api.fetchPlacePhotos(widget.place.id);
    }
  }

  Future<void> _openDirections() async {
    final Place place = widget.place;
    final Uri url = Uri.https('www.google.com', '/maps/dir/', <String, String>{
      'api': '1',
      'destination': '${place.lat},${place.lng}',
    });
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool opened = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.openMapsFailed)));
    }
  }

  /// Google マップでこの場所のページを開く（口コミや営業時間は Google マップで見てもらう）
  Future<void> _openInMaps() async {
    final Place place = widget.place;
    final Uri url = Uri.https(
      'www.google.com',
      '/maps/search/',
      <String, String>{
        'api': '1',
        'query': place.name,
        if (!place.isMock) 'query_place_id': place.id,
      },
    );
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool opened = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.openMapsFailed)));
    }
  }

  void _openCheckin({required double lat, required double lng}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) =>
            CheckinScreen(place: widget.place, lat: lat, lng: lng),
      ),
    );
  }

  // 詳細を開くだけで位置情報の許可を求めないよう、ボタンを押してから現在地を読む
  Future<void> _checkIn() async {
    final Services services = Services.of(context);
    final Place place = widget.place;
    // ダミーの場所は検索した地点の周りへ動かして返すので、現在地と比べない
    if (services.api.usesMockOnly || place.isMock) {
      _openCheckin(lat: place.lat, lng: place.lng);
      return;
    }
    setState(() => _locating = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final LocationService location = services.location;
    try {
      final LocationAccess access = await location.requestAccess();
      if (access != LocationAccess.granted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              access == LocationAccess.serviceOff
                  ? l10n.locationServiceOff
                  : l10n.locationDenied,
            ),
            action: SnackBarAction(
              label: l10n.openSettings,
              onPressed: () => location.openSettings(access),
            ),
          ),
        );
        return;
      }
      final GeoSample position = await location.current();
      final int distance = distanceMeters(
        position.lat,
        position.lng,
        place.lat,
        place.lng,
      );
      if (distance > checkinRangeMeters) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.distanceToPlace(
                formatDistance(distance),
                formatDistance(checkinRangeMeters),
              ),
            ),
          ),
        );
        return;
      }
      if (mounted) {
        _openCheckin(lat: position.lat, lng: position.lng);
      }
    } catch (error) {
      debugPrint('現在地を測定できません: $error');
      messenger.showSnackBar(SnackBar(content: Text(l10n.locationFailed)));
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Place place = widget.place;
    final Place? origin = widget.origin;
    final int? distance = widget.distanceMeters ?? place.distanceMeters;
    final String? type = placeTypeLabel(place.primaryType);
    final String? address = place.address;
    final TextStyle? subtle = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    // チェックインのタブと同じく、まだ押していないスタンプを押してチェックインする
    final Widget checkIn = StampPressTile(
      key: const ValueKey<String>('detail-stamp'),
      design: stampDesignOfPlace(place),
      title: l10n.detailStampTitle,
      subtitle: l10n.detailStampHelp(formatDistance(checkinRangeMeters)),
      busy: _locating,
      onPressed: _checkIn,
    );
    final List<Widget> info = <Widget>[
      if (widget.isMock) ...<Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          child: const MockBanner(),
        ),
        const SizedBox(height: 12),
      ],
      PlacePhotoGallery(photos: _photos),
      if (_photos != null) const SizedBox(height: 16),
      const SizedBox(height: 20),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: Text(place.name, style: AppTheme.placeName(24))),
          if (place.reviewCountKnown) ...<Widget>[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TitleBadge.of(place),
            ),
          ],
        ],
      ),
      if (type != null || address != null) ...<Widget>[
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: <Widget>[
            if (type != null)
              _IconText(
                icon: placeTypeIcon(place.primaryType),
                text: type,
                style: subtle,
              ),
            if (address != null)
              _IconText(
                icon: Icons.place_outlined,
                text: address,
                style: subtle,
              ),
          ],
        ),
      ],
      const SizedBox(height: 16),
      // Material 3：場所の名前のすぐ下に、主な操作を並べる
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          FilledButton.tonalIcon(
            onPressed: _openDirections,
            icon: const Icon(Icons.directions_outlined),
            label: Text(l10n.directions),
          ),
          OutlinedButton.icon(
            onPressed: _openInMaps,
            icon: const Icon(Icons.map_outlined),
            label: Text(l10n.openInGoogleMaps),
          ),
        ],
      ),
      const SizedBox(height: 12),
      checkIn,
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: <Widget>[
            if (place.reviewCountKnown) ...<Widget>[
              _Stat(
                icon: Icons.rate_review_outlined,
                label: l10n.reviews,
                value: formatCount(place.userRatingCount),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
            ],
            FutureBuilder<int>(
              future: _visitors,
              builder: (BuildContext context, AsyncSnapshot<int> snap) => _Stat(
                icon: Icons.flag_outlined,
                label: l10n.uramichiVisitors,
                value: switch (snap) {
                  AsyncSnapshot<int>(hasData: true, :final int data) =>
                    formatCount(data),
                  AsyncSnapshot<int>(hasError: true) => '—',
                  _ => '…',
                },
              ),
            ),
            if (distance != null) ...<Widget>[
              const Divider(height: 1, indent: 16, endIndent: 16),
              _Stat(
                icon: Icons.directions_walk,
                label: origin == null
                    ? l10n.distance
                    : l10n.distanceFrom(origin.name),
                value: formatDistance(distance),
              ),
            ],
          ],
        ),
      ),
      if (!widget.isMock) const GoogleMapsAttribution(),
    ];
    final Widget map = PlacesMap(
      places: <Place>[place],
      center: LatLng(place.lat, place.lng),
      selectedPlaceId: place.id,
      onCenterChanged: (LatLng _) {},
      onTapPlace: (Place _) {},
    );
    final AppBar appBar = AppBar(
      actions: <Widget>[FavoriteButton(place: widget.place)],
    );

    // 広い画面では、スマートフォンの1列を引き伸ばさず、左に情報、右に大きな地図を並べる
    if (!WindowSize.of(context).isCompact) {
      return Scaffold(
        appBar: appBar,
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: (box.maxWidth * 0.45).clamp(340, 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        children: info,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SafeArea(
                  left: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 24, 24),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      child: map,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
          ...info,
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            child: SizedBox(height: 180, child: map),
          ),
        ],
      ),
    );
  }
}

class _IconText extends StatelessWidget {
  const _IconText({required this.icon, required this.text, this.style});

  final IconData icon;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Icon(icon, size: 16, color: style?.color),
      const SizedBox(width: 4),
      Flexible(child: Text(text, style: style)),
    ],
  );
}

/// アイコン、項目名、値を1行に並べる
class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          const SizedBox(width: 12),
          Text(value, style: AppTheme.number(18)),
        ],
      ),
    );
  }
}
