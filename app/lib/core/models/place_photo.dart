/// 場所の写真1枚（Google マップの写真）。サーバー（GET /api/places/{placeId}/photos）と同じ JSON 形式。
///
/// [url] は短い時間だけ使える画像の URL なので、端末に保存しない。
/// Google Maps の規約で、写真と一緒に撮影者（[attributions]）を表示する
class PlacePhoto {
  const PlacePhoto({
    required this.url,
    required this.width,
    required this.height,
    this.attributions = const <PhotoAttribution>[],
  });

  factory PlacePhoto.fromJson(Map<String, dynamic> j) => PlacePhoto(
    url: j['url'] as String,
    width: (j['width'] as num?)?.toInt() ?? 0,
    height: (j['height'] as num?)?.toInt() ?? 0,
    attributions: <PhotoAttribution>[
      for (final Object? a
          in (j['attributions'] as List<Object?>?) ?? const <Object?>[])
        PhotoAttribution(
          name: (a! as Map)['name'] as String? ?? '',
          uri: (a as Map)['uri'] as String?,
        ),
    ],
  );

  final String url;
  final int width;
  final int height;
  final List<PhotoAttribution> attributions;
}

/// 写真の撮影者。[uri] は撮影者の Google マップのページ
class PhotoAttribution {
  const PhotoAttribution({required this.name, this.uri});

  final String name;
  final String? uri;
}
