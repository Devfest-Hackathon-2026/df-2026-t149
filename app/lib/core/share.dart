import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/memory_log.dart';
import 'strings.dart';

/// チェックインをシェアする文。場所の名前、何人目か、★評価（★4以上のとき）、ひとことを入れる
String checkinShareText({
  required String placeName,
  int? order,
  int? stars,
  String comment = '',
}) {
  final StringBuffer b = StringBuffer(l10n.shareTextPlace(placeName));
  b.write(
    order == null
        ? l10n.shareTextCheckedIn
        : l10n.shareTextCheckedInOrder(order),
  );
  if (order == 1) {
    b.write(l10n.shareTextFirst);
  }
  // 低い★をシェアすると、場所の悪い評判を広めているように見えるため、★4以上だけ入れる
  if (stars != null && stars >= 4) {
    b.write('\n${'★' * stars}${'☆' * (5 - stars)} ${starsLabel(stars)}');
  }
  final String c = comment.trim();
  if (c.isNotEmpty) {
    b.write(l10n.shareTextComment(c));
  }
  b.write(l10n.shareTextFooter);
  return b.toString();
}

/// シェアする先
enum ShareTarget {
  x(),
  line();

  const ShareTarget();
  String get label => switch (this) {
    x => l10n.shareTargetX,
    line => l10n.shareTargetLine,
  };

  /// 投稿の画面を開く URL。アプリが入っていれば、端末がアプリで開く
  Uri uri(String text) => switch (this) {
    ShareTarget.x => Uri.https('x.com', '/intent/post', <String, String>{
      'text': text,
    }),
    // LINE の「テキストを送る」URL。social-plugins.line.me/lineit/share は URL を送るためのもので、文だけでは送れない。
    // 空白を「+」にすると LINE がそのまま「+」と表示するため、%20 で書く
    ShareTarget.line => Uri.parse(
      'https://line.me/R/share?text=${Uri.encodeComponent(text)}',
    ),
  };
}

/// 文だけを、端末の共有の画面から送る（LINE や X のアプリがないとき、ほかのアプリで送るとき）
typedef ShareText = Future<bool> Function(String text);

Future<bool> shareTextWithSystem(String text) async {
  await SharePlus.instance.share(ShareParams(text: text));
  return true;
}

/// 記録や口コミをシェアする文。自分の記録は「行きました」、ほかの人の口コミは「見つけた口コミ」として書く。
/// ほかの人のニックネームは入れない（本人の知らないところで名前を広めないため）
String entryShareText({
  required String placeName,
  required bool mine,
  int? stars,
  String comment = '',
}) {
  final StringBuffer b = StringBuffer(
    mine ? l10n.shareEntryMine(placeName) : l10n.shareEntryOthers(placeName),
  );
  // チェックインのシェアと同じく、場所の悪い評判を広めないよう★4以上だけ入れる
  if (stars != null && stars >= 4) {
    b.write('\n${'★' * stars}${'☆' * (5 - stars)} ${starsLabel(stars)}');
  }
  final String c = comment.trim();
  if (c.isNotEmpty) {
    b.write(l10n.shareTextComment(c));
  }
  b.write(l10n.shareTextFooter);
  return b.toString();
}

/// 画像と文を、端末の共有の画面から送る。Instagram は文だけの共有を受け付けないため、画像を付ける。
/// 共有の画面を開けなければ false。テストでは差し替える
typedef ShareImage = Future<bool> Function(Uint8List png, String text);

Future<bool> shareImageWithSystem(Uint8List png, String text) async {
  // unavailable は「結果がわからない」という意味で、共有の画面は開いている（Android でも返ることがある）。
  // 開けなかったときは例外になるので、例外にならなければ開けたとみなす
  await SharePlus.instance.share(
    ShareParams(
      files: <XFile>[
        XFile.fromData(png, mimeType: 'image/png', name: 'uramichi.png'),
      ],
      fileNameOverrides: const <String>['uramichi.png'],
      text: text,
    ),
  );
  return true;
}

/// URL を外部のアプリかブラウザで開く。テストでは差し替える
typedef OpenUrl = Future<bool> Function(Uri url);

Future<bool> openExternal(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);
