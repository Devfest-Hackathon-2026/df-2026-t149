import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

export '../l10n/app_localizations.dart' show AppLocalizations;

/// 画面に表示する文言。文言は lib/l10n/app_ja.arb にまとめ、`flutter gen-l10n` で生成したクラスから読む。
// AppLocalizations.of(context) を使わないのは、列挙型の項目名やコントローラーの文言など、
// BuildContext のない場所からも同じ文言を読むため。アプリは日本語だけで、MaterialApp の locale も固定している
final AppLocalizations l10n = lookupAppLocalizations(const Locale('ja'));
