import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/core/strings.dart';

/// 画面の文言ではない日本語を含むファイル
const Set<String> _dataFiles = <String>{
  // 地域の名前のデータ
  'lib/features/regions/regions.dart',
  // Gemini に渡す利用者の状況
  'lib/features/assistant/assistant_situation.dart',
  // 端末だけで動くときのダミーの場所と投稿
  'lib/core/api/mock_data.dart',
  'lib/core/data/checkin_repository.dart',
  // flutterfire が生成する設定
  'lib/firebase_options.dart',
};

/// 画面の文言ではない日本語の文字列。サーバーの値との比較、開発者向けのエラー、区切りの記号
const Set<String> _allowedLiterals = <String>{
  '地図の中心',
  'ログインしていないときはプロフィールを保存できない',
  'Services が見つかりません（main.dart で包んでいるか確認）',
  '・',
  ' ・ ',
};

const String _japanese = r'[\u3040-\u30ff\u3400-\u9fff]';
final RegExp _japaneseLiteral = RegExp(
  "'([^'\\n]*$_japanese[^'\\n]*)'"
  '|"([^"\\n]*$_japanese[^"\\n]*)"',
);

void main() {
  test('画面の文言は lib/l10n/app_ja.arb から読み、Dart のコードに直接書かない', () {
    final List<String> found = <String>[];
    final Iterable<File> files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .where((File f) => !f.path.startsWith('lib/l10n/'))
        .where((File f) => !_dataFiles.contains(f.path));
    for (final File file in files) {
      final List<String> lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i].trim();
        final String previous = i == 0 ? '' : lines[i - 1].trim();
        if (line.startsWith('//') ||
            line.contains('debugPrint(') ||
            previous.endsWith('debugPrint(')) {
          continue;
        }
        for (final RegExpMatch m in _japaneseLiteral.allMatches(line)) {
          final String text = m.group(1) ?? m.group(2)!;
          if (!_allowedLiterals.contains(text)) {
            found.add('${file.path}:${i + 1}: $text');
          }
        }
      }
    }
    expect(found, isEmpty);
  });

  test('達成条件の「{n}」は置き換えるための印として、そのまま文言に残る', () {
    expect(l10n.achPioneerDescription, contains('{n}'));
  });
}
