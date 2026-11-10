import 'package:flutter/foundation.dart';

import '../../core/api/uramichi_api.dart';
import '../../core/models/assistant_answer.dart';
import '../../core/widgets/state_view.dart';

/// Geminiちゃんとのやり取り。チャットの履歴は画面に並べず、最新の一言と答えだけを持つ。
///
/// 続きの依頼（「もっと近くは？」など）に答えられるよう、直前のやり取りを [maxHistory] 件まで覚えてサーバーに送る。
/// 覚えるのはアプリを開いている間だけで、端末にもサーバーにも保存しない
class AssistantController extends ChangeNotifier {
  AssistantController({required this.api});

  final UramichiApi api;

  /// サーバーに送る直前のやり取りの件数（サーバーの上限と同じ）
  static const int maxHistory = 6;

  /// 話しかける言葉の長さの上限（サーバーの上限と同じ）
  static const int maxMessageLength = 200;

  final List<AssistantTurn> _history = <AssistantTurn>[];
  String? _message;
  AssistantAnswer? _answer;
  String? _error;
  bool _loading = false;
  int _requestId = 0;

  /// 最後に話しかけた一言
  String? get message => _message;

  /// 最後の答え。答えを待っている間も、前の答えを残す
  AssistantAnswer? get answer => _answer;

  /// 最後の依頼が失敗したときの文
  String? get error => _error;
  bool get loading => _loading;

  /// 話しかける。[lat] と [lng] は地図の中心、[context] は利用者の状況（[AssistantSituation.toContextJson]）
  Future<void> ask(
    String text, {
    double? lat,
    double? lng,
    Map<String, Object>? context,
  }) async {
    final String message = text.trim();
    if (message.isEmpty || message.length > maxMessageLength) {
      return;
    }
    final int requestId = ++_requestId;
    final List<AssistantTurn> history = List<AssistantTurn>.of(_history);
    _message = message;
    _error = null;
    _loading = true;
    notifyListeners();
    try {
      final AssistantAnswer answer = await api.askAssistant(
        message,
        lat: lat,
        lng: lng,
        history: history,
        context: context,
      );
      if (requestId != _requestId) {
        return;
      }
      _answer = answer;
      _remember(AssistantTurn.user(message));
      _remember(AssistantTurn.assistant(answer.reply));
    } catch (error) {
      if (requestId != _requestId) {
        return;
      }
      _error = describeError(error);
    }
    _loading = false;
    notifyListeners();
  }

  /// やり取りを忘れて、最初からにする
  void reset() {
    _requestId++;
    _history.clear();
    _message = null;
    _answer = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }

  void _remember(AssistantTurn turn) {
    _history.add(turn);
    if (_history.length > maxHistory) {
      _history.removeRange(0, _history.length - maxHistory);
    }
  }
}
