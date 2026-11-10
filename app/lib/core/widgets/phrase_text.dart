import 'package:budoux_dart/budoux.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 短い説明文を文節の境界で折り返す
class PhraseText extends StatelessWidget {
  const PhraseText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  static Future<BudouX>? _model;

  static Future<BudouX> _loadModel() => _model ??= rootBundle
      .loadString('packages/budoux_dart/models/ja.json')
      .then(BudouX.new);

  @override
  Widget build(BuildContext context) {
    Widget original() => Text(text, style: style, textAlign: textAlign);
    // モデルは UTF-16 単位で分割するため、絵文字や改行を含む文は Flutter に任せる
    if (text.runes.any((int rune) => rune > 0xffff) || text.contains('\n')) {
      return original();
    }
    return FutureBuilder<BudouX>(
      future: _loadModel(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return original();
        }
        final parts = snapshot.data!.parse(text);
        return Semantics(
          label: text,
          excludeSemantics: true,
          child: Wrap(
            alignment: textAlign == TextAlign.center
                ? WrapAlignment.center
                : WrapAlignment.start,
            children: <Widget>[
              for (final part in parts) Text(part, style: style),
            ],
          ),
        );
      },
    );
  }
}
