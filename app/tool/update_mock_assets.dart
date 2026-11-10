// アプリに同梱するダミーデータ（assets/mock/）を、ダミーデータで起動した API サーバーの応答から作り直す。
//
// 使い方: backend/ で `make dev` を起動してから、app/ で次を実行する。
//   dart run tool/update_mock_assets.dart [API サーバーの URL]
import 'dart:convert';
import 'dart:io';

/// ダミーの場所を探す中心。アプリはこの中心からの相対位置を保って、地図の中心の周りに場所を置き直す
const double _lat = 34.6930;
const double _lng = 135.1900;

Future<void> main(List<String> args) async {
  final String base = args.isEmpty ? 'http://localhost:8080' : args.first;
  final HttpClient client = HttpClient();
  const JsonEncoder encoder = JsonEncoder.withIndent('  ');

  Future<Map<String, dynamic>> get(
    String path,
    Map<String, String> query,
  ) async {
    final Uri uri = Uri.parse(
      '$base$path',
    ).replace(queryParameters: <String, String>{...query, 'mock': '1'});
    final HttpClientResponse res = await (await client.getUrl(uri)).close();
    final String body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw HttpException('${res.statusCode} $uri: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  final Map<String, dynamic> explore = await get(
    '/api/explore',
    <String, String>{'lat': '$_lat', 'lng': '$_lng', 'radius': '5000'},
  );
  explore['center'] = <String, double>{'lat': _lat, 'lng': _lng};
  final Map<String, dynamic> alternatives = await get(
    '/api/alternatives',
    <String, String>{'q': 'ダミー', 'radius': '10000'},
  );

  await File(
    'assets/mock/explore.json',
  ).writeAsString('${encoder.convert(explore)}\n');
  await File(
    'assets/mock/alternatives.json',
  ).writeAsString('${encoder.convert(alternatives)}\n');
  client.close();
  stdout.writeln('assets/mock/ を更新しました');
}
