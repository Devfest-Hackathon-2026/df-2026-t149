import 'package:flutter/material.dart';

import '../theme.dart';
import '../models/place_photo.dart';
import '../share.dart';
import '../strings.dart';

/// 場所の写真（Google マップの写真）を横にめくって見せる。
///
/// 写真がないとき（ダミーの場所、写真のない場所、読み込めなかったとき）は何も表示せず、場所の詳細の邪魔をしない。
/// Google Maps の規約で、写真ごとに撮影者を表示し、撮影者の Google マップのページへのリンクにする
class PlacePhotoGallery extends StatefulWidget {
  const PlacePhotoGallery({
    super.key,
    required this.photos,
    this.height = 240,
    this.openUrl = openExternal,
  });

  /// 写真の読み込み。null なら何も表示しない
  final Future<List<PlacePhoto>>? photos;
  final double height;
  final OpenUrl openUrl;

  @override
  State<PlacePhotoGallery> createState() => _PlacePhotoGalleryState();
}

class _PlacePhotoGalleryState extends State<PlacePhotoGallery> {
  int _page = 0;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<PlacePhoto>>(
    future: widget.photos,
    builder: (BuildContext context, AsyncSnapshot<List<PlacePhoto>> snap) {
      if (widget.photos == null || snap.hasError) {
        return const SizedBox.shrink();
      }
      if (snap.connectionState != ConnectionState.done) {
        return _Placeholder(height: widget.height);
      }
      final List<PlacePhoto> photos = snap.data!;
      if (photos.isEmpty) {
        return const SizedBox.shrink();
      }
      return Semantics(
        label: l10n.placePhotosLabel(photos.length),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: <Widget>[
                PageView.builder(
                  itemCount: photos.length,
                  onPageChanged: (int i) => setState(() => _page = i),
                  itemBuilder: (BuildContext context, int i) => GestureDetector(
                    onTap: () => _openViewer(context, photos, i),
                    child: _Photo(photo: photos[i]),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _AttributionBar(
                    photo: photos[_page.clamp(0, photos.length - 1)],
                    page: _page,
                    count: photos.length,
                    openUrl: widget.openUrl,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  void _openViewer(BuildContext context, List<PlacePhoto> photos, int index) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (BuildContext _) => _PhotoViewer(
            photos: photos,
            initial: index,
            openUrl: widget.openUrl,
          ),
        ),
      );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
    ),
    alignment: Alignment.center,
    child: Icon(
      Icons.photo_outlined,
      size: 40,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _Photo extends StatelessWidget {
  const _Photo({required this.photo, this.fit = BoxFit.cover});

  final PlacePhoto photo;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Image.network(
      photo.url,
      fit: fit,
      width: double.infinity,
      loadingBuilder:
          (BuildContext context, Widget child, ImageChunkEvent? p) => p == null
          ? child
          : ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: const Center(child: CircularProgressIndicator()),
            ),
      errorBuilder: (BuildContext context, Object _, StackTrace? _) =>
          ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
    );
  }
}

/// 撮影者と、何枚目かの表示。写真の上に文字を直接置かず、地の色の帯の上に置く
class _AttributionBar extends StatelessWidget {
  const _AttributionBar({
    required this.photo,
    required this.page,
    required this.count,
    required this.openUrl,
  });

  final PlacePhoto photo;
  final int page;
  final int count;
  final OpenUrl openUrl;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final PhotoAttribution? author = photo.attributions.isEmpty
        ? null
        : photo.attributions.first;
    final String? uri = author?.uri;
    return Material(
      color: scheme.surfaceContainer.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: author == null
                  ? Text(
                      l10n.photoCreditGoogle,
                      style: theme.textTheme.labelSmall,
                    )
                  : InkWell(
                      onTap: uri == null ? null : () => openUrl(Uri.parse(uri)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          l10n.photoCreditAuthor(author.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurface,
                            decoration: uri == null
                                ? null
                                : TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
            ),
            if (count > 1)
              Text(
                '${page + 1} / $count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 写真を画面いっぱいに見せ、拡大できるようにする
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({
    required this.photos,
    required this.initial,
    required this.openUrl,
  });

  final List<PlacePhoto> photos;
  final int initial;
  final OpenUrl openUrl;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late int _page = widget.initial;
  late final PageController _controller = PageController(
    initialPage: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${_page + 1} / ${widget.photos.length}')),
    body: Column(
      children: <Widget>[
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.photos.length,
            onPageChanged: (int i) => setState(() => _page = i),
            itemBuilder: (BuildContext context, int i) => InteractiveViewer(
              child: _Photo(photo: widget.photos[i], fit: BoxFit.contain),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: _AttributionBar(
            photo: widget.photos[_page],
            page: _page,
            count: widget.photos.length,
            openUrl: widget.openUrl,
          ),
        ),
      ],
    ),
  );
}
