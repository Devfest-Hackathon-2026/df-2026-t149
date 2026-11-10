import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services.dart';
import '../strings.dart';

/// 記録に付けた写真。ログインした人だけが読めるため、アプリが ID トークンを付けて読み、手元で表示する
class LogPhoto extends StatefulWidget {
  const LogPhoto({
    super.key,
    required this.photoId,
    this.height = 180,
    this.borderRadius = 12,
  });

  final String photoId;
  final double height;
  final double borderRadius;

  @override
  State<LogPhoto> createState() => _LogPhotoState();
}

class _LogPhotoState extends State<LogPhoto> {
  Future<Uint8List>? _bytes;
  String? _readingId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _read();
  }

  @override
  void didUpdateWidget(LogPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    _read();
  }

  void _read() {
    if (_readingId == widget.photoId) {
      return;
    }
    _readingId = widget.photoId;
    _bytes = Services.of(context).checkins.photo(widget.photoId);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: FutureBuilder<Uint8List>(
          future: _bytes,
          builder: (BuildContext context, AsyncSnapshot<Uint8List> snap) {
            if (snap.data case final Uint8List bytes) {
              return Semantics(
                image: true,
                label: l10n.photoLabel,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => _Placeholder(scheme: scheme),
                ),
              );
            }
            return _Placeholder(scheme: scheme, loading: !snap.hasError);
          },
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.scheme, this.loading = false});

  final ColorScheme scheme;
  final bool loading;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: scheme.surfaceContainerHighest,
    child: Center(
      child: loading
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              Icons.image_not_supported_outlined,
              color: scheme.onSurfaceVariant,
              semanticLabel: l10n.photoUnavailable,
            ),
    ),
  );
}

/// 選んだ写真。上げる前の中身と種類
@immutable
class PickedPhoto {
  const PickedPhoto(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;

  /// サーバーが受け付ける大きさの上限（backend の maxPhotoBytes と同じ）
  static const int maxBytes = 900 * 1024;

  bool get tooLarge => bytes.length > maxBytes;

  /// 中身の先頭のバイトから種類を決める（サーバーと同じ決め方）。受け付けない種類なら null
  static String? typeOf(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return 'image/png';
    }
    if (b.length >= 12 &&
        String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }
}

/// 写真を選ぶ。長い辺を 1280px に縮め、JPEG の画質を落として、サーバーの上限に収める。
/// 選ばなかったときは null、受け付けない写真のときは [FormatException] を投げる
Future<PickedPhoto?> pickPhoto(ImageSource source) async {
  final XFile? file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1280,
    maxHeight: 1280,
    imageQuality: 80,
  );
  if (file == null) {
    return null;
  }
  final Uint8List bytes = await file.readAsBytes();
  final String? type = PickedPhoto.typeOf(bytes);
  if (type == null) {
    throw FormatException(l10n.photoUnsupported);
  }
  final PickedPhoto photo = PickedPhoto(bytes, type);
  if (photo.tooLarge) {
    throw FormatException(l10n.photoTooLarge);
  }
  return photo;
}

/// チェックインの画面の写真の欄。選ぶ前は「写真を添える」ボタン、選んだ後は写真と外すボタンを見せる
class PhotoField extends StatelessWidget {
  const PhotoField({super.key, required this.photo, required this.onChanged});

  final PickedPhoto? photo;
  final ValueChanged<PickedPhoto?> onChanged;

  Future<void> _pick(BuildContext context, ImageSource source) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final PickedPhoto? picked = await pickPhoto(source);
      if (picked != null) {
        onChanged(picked);
      }
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.photoPickFailed)));
    }
  }

  Future<void> _choose(BuildContext context) async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.photoTake),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.photoChoose),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null && context.mounted) {
      await _pick(context, source);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PickedPhoto? photo = this.photo;
    if (photo == null) {
      return OutlinedButton.icon(
        onPressed: () => _choose(context),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: Text(l10n.photoAdd),
      );
    }
    return Stack(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            photo.bytes,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
            semanticLabel: l10n.photoLabel,
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton.filledTonal(
            tooltip: l10n.photoRemove,
            onPressed: () => onChanged(null),
            icon: const Icon(Icons.close),
          ),
        ),
      ],
    );
  }
}
