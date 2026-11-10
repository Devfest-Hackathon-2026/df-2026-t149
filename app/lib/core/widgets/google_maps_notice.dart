import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../share.dart';
import '../strings.dart';

/// Google Maps の追加利用規約
final Uri googleMapsTermsUrl = Uri.parse(
  'https://maps.google.com/help/terms_maps/',
);

/// Google のプライバシーポリシー
final Uri googlePrivacyUrl = Uri.parse('https://policies.google.com/privacy');

/// 地図の外に Places API の内容（場所の名前など）を出すときの出典。
/// 地図の上の出典は Google の地図が自動で出すので、一覧や詳細などの地図の外に置く。
/// 文字の出典は「Google Maps」を訳さずに書く
class GoogleMapsAttribution extends StatelessWidget {
  const GoogleMapsAttribution({
    super.key,
    this.alignment = Alignment.centerRight,
  });

  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Semantics(
          label: l10n.googleMapsAttributionLabel,
          excludeSemantics: true,
          child: Text(
            'Google Maps',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'Roboto',
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

/// アプリが Google マップの機能と内容を使っていることと、従う規約を知らせる文（規約 3.2.2(a)）。
/// ログインの画面と設定の画面に置き、規約とプライバシーポリシーはリンクで開ける
class GoogleMapsTermsNotice extends StatefulWidget {
  const GoogleMapsTermsNotice({
    super.key,
    this.textAlign = TextAlign.start,
    this.openUrl = openExternal,
  });

  final TextAlign textAlign;
  final OpenUrl openUrl;

  @override
  State<GoogleMapsTermsNotice> createState() => _GoogleMapsTermsNoticeState();
}

class _GoogleMapsTermsNoticeState extends State<GoogleMapsTermsNotice> {
  late final TapGestureRecognizer _terms = TapGestureRecognizer()
    ..onTap = () => widget.openUrl(googleMapsTermsUrl);
  late final TapGestureRecognizer _privacy = TapGestureRecognizer()
    ..onTap = () => widget.openUrl(googlePrivacyUrl);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? base = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final TextStyle? link = base?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: <InlineSpan>[
          TextSpan(text: l10n.googleMapsNoticeLead),
          TextSpan(
            text: l10n.googleMapsTermsLink,
            style: link,
            recognizer: _terms,
          ),
          TextSpan(text: l10n.googleMapsNoticeAnd),
          TextSpan(
            text: l10n.googlePrivacyLink,
            style: link,
            recognizer: _privacy,
          ),
          TextSpan(text: l10n.googleMapsNoticeTail),
        ],
      ),
      textAlign: widget.textAlign,
    );
  }
}
