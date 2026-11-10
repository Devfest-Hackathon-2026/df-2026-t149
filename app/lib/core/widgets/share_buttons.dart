import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../share.dart';
import '../strings.dart';

/// シェアのボタンの並び（𝕏・LINE・Instagram・ほかのアプリ・テキストをコピー）。
/// チェックインのお祝いの画面と、記録や口コミの詳細で同じものを使う
class ShareButtons extends StatefulWidget {
  const ShareButtons({
    super.key,
    required this.text,
    required this.captureImage,
    this.openUrl = openExternal,
    this.shareImage = shareImageWithSystem,
    this.shareText = shareTextWithSystem,
  });

  final String text;

  /// Instagram へ送る画像を作る。作れなければ null
  final Future<Uint8List?> Function() captureImage;
  final OpenUrl openUrl;
  final ShareImage shareImage;
  final ShareText shareText;

  @override
  State<ShareButtons> createState() => _ShareButtonsState();
}

class _ShareButtonsState extends State<ShareButtons> {
  bool _sharingImage = false;

  Future<void> _share(ShareTarget target) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    bool opened = false;
    try {
      opened = await widget.openUrl(target.uri(widget.text));
    } catch (error) {
      debugPrint('${target.label}を開けません: $error');
    }
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.shareOpenFailed(target.label))),
      );
    }
  }

  /// 画像を作って、端末の共有の画面を開く。Instagram は投稿に文を入れてくれないため、文はコピーしておく
  Future<void> _shareInstagram() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _sharingImage = true);
    try {
      final Uint8List? png = await widget.captureImage();
      if (png == null) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.shareImageFailed)));
        return;
      }
      await Clipboard.setData(ClipboardData(text: widget.text));
      if (await widget.shareImage(png, widget.text)) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.shareInstagramHint)),
        );
      } else {
        messenger.showSnackBar(SnackBar(content: Text(l10n.shareSheetFailed)));
      }
    } catch (error) {
      debugPrint('画像で共有できません: $error');
      messenger.showSnackBar(SnackBar(content: Text(l10n.shareSheetFailed)));
    } finally {
      if (mounted) {
        setState(() => _sharingImage = false);
      }
    }
  }

  Future<void> _shareOther() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      if (!await widget.shareText(widget.text)) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.shareSheetFailed)));
      }
    } catch (error) {
      debugPrint('共有の画面を開けません: $error');
      messenger.showSnackBar(SnackBar(content: Text(l10n.shareSheetFailed)));
    }
  }

  Future<void> _copy() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: widget.text));
    messenger.showSnackBar(SnackBar(content: Text(l10n.shareTextCopied)));
  }

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      for (final ShareTarget t in ShareTarget.values)
        OutlinedButton.icon(
          onPressed: () => _share(t),
          icon: const Icon(Icons.share_outlined),
          label: Text(t.label),
        ),
      OutlinedButton.icon(
        onPressed: _sharingImage ? null : _shareInstagram,
        icon: const Icon(Icons.photo_camera_outlined),
        label: Text(l10n.shareInstagram),
      ),
      OutlinedButton.icon(
        onPressed: _shareOther,
        icon: const Icon(Icons.ios_share),
        label: Text(l10n.shareOtherApps),
      ),
      OutlinedButton.icon(
        onPressed: _copy,
        icon: const Icon(Icons.copy),
        label: Text(l10n.shareCopyText),
      ),
    ],
  );
}

/// [key] の RepaintBoundary の中身を PNG にする。描かれていなければ null
Future<Uint8List?> captureBoundary(GlobalKey key) async {
  final RenderObject? r = key.currentContext?.findRenderObject();
  if (r is! RenderRepaintBoundary) {
    return null;
  }
  final ui.Image image = await r.toImage(pixelRatio: 3);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}
