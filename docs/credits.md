# 著作物利用シート（下書き）

使った素材・ライブラリ・データの出典とライセンスを、使ったその日に足していきます。提出前に D が Google ドライブのシートに写します。

## ライブラリ

| 名前 | 用途 | ライセンス | 出典 |
|---|---|---|---|
| Flutter | アプリ | BSD-3-Clause | https://github.com/flutter/flutter |
| http | API の呼び出し | BSD-3-Clause | https://pub.dev/packages/http |
| google_maps_flutter | 地図 | BSD-3-Clause | https://pub.dev/packages/google_maps_flutter |
| firebase_core / firebase_auth | ログイン | BSD-3-Clause | https://github.com/firebase/flutterfire |
| google_sign_in | Android 版の Google アカウントでのログイン | BSD-3-Clause | https://pub.dev/packages/google_sign_in |
| flutter_localizations | Material の部品の文言を日本語で表示する | BSD-3-Clause | https://github.com/flutter/flutter |
| intl | ARB にまとめた画面の文言から生成したクラスが使う | BSD-3-Clause | https://github.com/dart-lang/i18n |
| dorny/paths-filter | CI で変更したファイルを判定する | MIT | https://github.com/dorny/paths-filter |
| Firebase CLI（Firestore エミュレーター） | CI で保存処理を確かめる | MIT | https://github.com/firebase/firebase-tools |
| Go | API サーバー | BSD-3-Clause | https://go.dev |
| Firebase Admin Go SDK | ID トークンの検証 | Apache-2.0 | https://github.com/firebase/firebase-admin-go |
| Cloud Firestore Go クライアント | チェックインと思い出ログの保存 | Apache-2.0 | https://github.com/googleapis/google-cloud-go |
| gRPC-Go | Firestore との通信の状態の判定 | Apache-2.0 | https://github.com/grpc/grpc-go |
| Google Gen AI Go SDK（google.golang.org/genai） | Geminiちゃん（Vertex AI の Gemini の呼び出し） | Apache-2.0 | https://github.com/googleapis/go-genai |
| ulid | 思い出ログの ID | Apache-2.0 | https://github.com/oklog/ulid |
| google_fonts | フォントの読み込み | BSD-3-Clause | https://pub.dev/packages/google_fonts |
| url_launcher | Google マップの道順を開く | BSD-3-Clause | https://pub.dev/packages/url_launcher |
| share_plus | チェックインの画像を端末の共有の画面から送る（Instagram など） | BSD-3-Clause | https://pub.dev/packages/share_plus |
| dynamic_color | 端末の壁紙の色の取得 | Apache-2.0 | https://pub.dev/packages/dynamic_color |
| budoux_dart | 日本語の文節の境界の判定 | Apache-2.0 | https://pub.dev/packages/budoux_dart |
| pointer_interceptor | Web 版で地図の上の部品の操作を地図に渡さない | BSD-3-Clause | https://pub.dev/packages/pointer_interceptor |
| geolocator | 現在地の取得と滞在の記録 | MIT | https://pub.dev/packages/geolocator |
| workmanager | アプリを閉じている間の定期的な測定 | MIT | https://pub.dev/packages/workmanager |
| audioplayers | 効果音の再生 | MIT | https://pub.dev/packages/audioplayers |
| image_picker | 記録に付ける写真を撮る・選ぶ | BSD-3-Clause, Apache-2.0 | https://pub.dev/packages/image_picker |
| flutter_local_notifications | 滞在の知らせ | BSD-3-Clause | https://pub.dev/packages/flutter_local_notifications |
| shared_preferences | テーマとキーカラーの設定、未送信の記録、滞在の記録の保存 | BSD-3-Clause | https://pub.dev/packages/shared_preferences |
| flutter_lints / lints / test | 開発用 | BSD-3-Clause | https://pub.dev |

<!-- 依存を足したら pubspec.yaml とあわせてここにも足す -->

## API・データ

| 名前 | 用途 | 条件 | 出典 |
|---|---|---|---|
| Google Maps Platform（Places API (New) の検索、地点の検索と Place Details、Maps SDK for Android、Maps JavaScript API） | 場所の検索、チェックインの確認、思い出ログの名前、地図 | Google Maps Platform 利用規約。地図と検索結果に Google の帰属表示が必要 | https://cloud.google.com/maps-platform/terms |
| Vertex AI の Gemini API | Geminiちゃんの意図の読み取り | Google Cloud の利用規約と生成 AI の追加規約 | https://cloud.google.com/terms/service-terms |
| ダミー JSON（`backend/internal/places/mockdata/`） | 開発・デモの保険 | チームで作った架空のデータ | このリポジトリ |

## 画像・アイコン・音・フォント

| 名前 | 用途 | ライセンス | 出典 |
|---|---|---|---|
| Material Icons | アプリのアイコン | Apache-2.0 | https://fonts.google.com/icons |
| Zen Kaku Gothic New | アプリの全ての文字（400 と 700 を `app/assets/google_fonts/` に同梱。ライセンスは同じ場所の OFL.txt） | SIL Open Font License 1.1 | https://fonts.google.com/specimen/Zen+Kaku+Gothic+New |
| 効果音（`app/assets/sounds/`） | チェックイン・実績の解除・★などの音 | 自作（`scripts/make_sounds.py` で合成） | このリポジトリ |
| Google Cloud 公式アイコン | 構成図（スライド） | 利用条件に従う | https://cloud.google.com/icons |

<!-- 写真・イラスト・BGM などを使ったらここに足す。自分たちで撮った写真も「自作」と書く -->
