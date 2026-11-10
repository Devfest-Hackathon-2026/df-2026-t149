import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uramichi/core/api/uramichi_api.dart';
import 'package:uramichi/core/models/memory_log.dart';
import 'package:uramichi/core/models/timeline_entry.dart';

http.Response _json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

void main() {
  test('覚えておく名前は新しい順に上限まで。ダミーの場所は覚えない', () {
    final PlaceNames names = PlaceNames(capacity: 2)
      ..remember('a', '祠')
      ..remember('b', '茶屋')
      ..remember('a', '祠')
      ..remember('c', '公園')
      ..remember('mock_01', 'ダミー');
    expect(names['b'], isNull);
    expect(names['a'], '祠');
    expect(names.knownQuery()['known'], 'a,c');
  });

  test('検索で受け取った名前は、記録とタイムラインで読み直さずに埋める', () async {
    final List<Uri> calls = <Uri>[];
    final UramichiApi api = UramichiApi(
      baseUrl: 'http://test',
      client: MockClient((http.Request r) async {
        calls.add(r.url);
        return switch (r.url.path) {
          '/api/explore' => _json(<String, Object>{
            'source': 'google',
            'places': <Object>[
              <String, Object>{
                'id': 'ChIJa',
                'name': '坂の上の祠',
                'lat': 35,
                'lng': 135,
                'types': <String>[],
              },
            ],
          }),
          '/api/logs' => _json(<String, Object>{
            'logs': <Object>[
              <String, Object>{
                'id': 'l1',
                'placeId': 'ChIJa',
                'verdict': 'hit',
                'rating': 5,
                'createdAt': '2026-11-08T03:00:00Z',
              },
              <String, Object>{
                'id': 'l2',
                'placeId': 'ChIJb',
                'placeName': '川沿いの茶屋',
                'verdict': 'hit',
                'createdAt': '2026-11-08T02:00:00Z',
              },
            ],
          }),
          _ => _json(<String, Object>{
            'entries': <Object>[
              <String, Object>{
                'id': 'e1',
                'placeId': 'ChIJb',
                'verdict': 'hit',
                'createdAt': '2026-11-08T02:00:00Z',
              },
            ],
          }),
        };
      }),
      idToken: () async => 'token',
    );
    await api.explore(lat: 35, lng: 135);
    final List<MemoryLog> logs = await api.fetchLogs(idToken: 'token');
    expect(calls.last.queryParameters['known'], 'ChIJa');
    expect(logs.first.placeName, '坂の上の祠');

    final List<TimelineEntry> entries = await api.fetchTimeline(
      lat: 35,
      lng: 135,
      idToken: 'token',
    );
    expect(calls.last.queryParameters['known'], contains('ChIJb'));
    expect(entries.single.placeName, '川沿いの茶屋');
  });
}
