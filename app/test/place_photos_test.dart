import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/core/models/place_photo.dart';
import 'package:uramichi/core/widgets/place_photos.dart';

const List<PlacePhoto> _photos = <PlacePhoto>[
  PlacePhoto(
    url: 'https://example.invalid/a.jpg',
    width: 800,
    height: 600,
    attributions: <PhotoAttribution>[
      PhotoAttribution(
        name: '山田',
        uri: 'https://maps.google.com/maps/contrib/1',
      ),
    ],
  ),
  PlacePhoto(url: 'https://example.invalid/b.jpg', width: 800, height: 600),
];

Future<void> _pump(
  WidgetTester tester,
  Future<List<PlacePhoto>>? photos, {
  List<Uri>? opened,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: ListView(
        children: <Widget>[
          PlacePhotoGallery(
            photos: photos,
            openUrl: (Uri u) async {
              opened?.add(u);
              return true;
            },
          ),
          const Text('場所の名前'),
        ],
      ),
    ),
  ),
);

void main() {
  test('写真と撮影者を JSON から読む', () {
    final PlacePhoto p = PlacePhoto.fromJson(<String, dynamic>{
      'url': 'https://lh3.googleusercontent.com/x',
      'width': 960,
      'height': 720,
      'attributions': <Object>[
        <String, Object>{
          'name': '山田',
          'uri': 'https://maps.google.com/contrib/1',
        },
      ],
    });
    expect(p.width, 960);
    expect(p.attributions.single.name, '山田');
  });

  testWidgets('写真ごとに撮影者を出し、押すと撮影者のページを開く', (WidgetTester tester) async {
    final List<Uri> opened = <Uri>[];
    await _pump(
      tester,
      Future<List<PlacePhoto>>.value(_photos),
      opened: opened,
    );
    await tester.pumpAndSettle();
    expect(find.text('写真：山田（Google マップ）'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.tap(find.text('写真：山田（Google マップ）'));
    expect(opened.single.host, 'maps.google.com');

    // めくると、その写真の撮影者に変わる
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('写真：Google マップ'), findsOneWidget);

    // 押すと画面いっぱいに開く
    await tester.tap(find.byType(PageView));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsWidgets);
  });

  testWidgets('写真がない・読めないときは何も出さない', (WidgetTester tester) async {
    await _pump(tester, Future<List<PlacePhoto>>.value(const <PlacePhoto>[]));
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing);
    expect(find.text('場所の名前'), findsOneWidget);

    await _pump(
      tester,
      Future<List<PlacePhoto>>.error(Exception('x'))..ignore(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing);

    await _pump(tester, null);
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing);
  });
}
