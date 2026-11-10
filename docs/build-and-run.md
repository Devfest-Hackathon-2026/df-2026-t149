# アプリの起動とビルド

開発用のビルドは、API サーバーや Firebase、地図のキーがなくても起動し、ダミーデータで全ての画面を確認できる。それぞれが使えるようになると、設定を変えなくても本物のデータと機能に自動で切り替わる。

## 自動で切り替わるもの

| 対象 | 使えるとき | 使えないとき |
|---|---|---|
| API サーバー | 応答したデータを表示する。API キーのない開発用のサーバーがダミー JSON を返したときは、ダミーデータの帯を出す | 接続先（`apiBaseUrl`）があれば、接続できなくてもダミーデータに切り替えず、理由と「もう一度試す」を表示する。接続先のない開発用のビルドだけ、同梱したダミーデータ（`app/assets/mock/`）を表示する |
| Firebase | `app/.env` の `FIREBASE_*` をビルドに渡すと、Google アカウントでログインし、チェックインと思い出ログを API サーバーに保存する。通信できないときは端末に保存し、通信できるようになってからサーバーへ送る | 開発中のビルドは、ボタンを押すだけで済む開発用のログインで動き、端末に保存する。配布用のビルドは開発用のログインに切り替えず、「ログインを準備できませんでした」と「もう一度試す」を表示する |
| 地図 | 地図のキーがあれば Google マップを表示する | レビュー数のピンを置いた簡易地図を表示する |

架空の場所を本物のように見せないため、利用者がダミーデータに切り替える操作はない。

同梱したダミーデータはダミーデータで起動した API サーバーの応答から作る。サーバーのダミー JSON（`backend/internal/places/mockdata/`）を変えたら、サーバーを起動してから `app/` で次を実行する。

```bash
dart run tool/update_mock_assets.dart
```

## 設定のファイル

アプリの設定はアプリに同梱する `app/assets/config/app_config.json` に書く。Firebase の設定と地図のキーは `app/.env` に書き、「地図のキー」の手順でビルドに渡す。

| 項目 | 意味 |
|---|---|
| `apiBaseUrl` | 公開した API サーバー（Cloud Run）の URL。空のあいだは、ビルドはダミーデータで動く（開発用。配布するビルドでは必ず設定する） |
| `initialLat`、`initialLng` | 最初に地図を表示する地点 |

API サーバーの接続先は起動したときに次のように決まる。

| ビルド | 接続先 |
|---|---|
| 開発中（`flutter run`） | PC で動かした API サーバー（エミュレータからは `http://10.0.2.2:8080`、実機からは `http://localhost:8080`）が応答すればそれを使い、応答しなければ `apiBaseUrl` を使う |
| 配布用（`flutter build apk`） | `apiBaseUrl` を使う |
| Web の公開版（`flutter build web`） | 同じサイトの `/api` を使う（Firebase Hosting が Cloud Run へ転送する） |

使っている接続先はアプリの設定の画面の「接続先」で確かめられる。

## API サーバーを動かす

```bash
cd backend && make dev
```

Go（1.26 以上）が必要である。`make dev` は `PLACES_API_KEY` を渡さず、ダミー JSON を返す。ID トークンを検証せず、チェックインと思い出ログをサーバーのメモリに保存する。`/api/health` 以外の API は ID トークンが必須なので、Firebase を設定していない開発中のアプリは固定の文字列を送る。この文字列を受け取るのは `AUTH_MODE=fake` のサーバーだけである。

本物の Places API を試すときは、`backend/.env` に `PLACES_API_KEY` を書いて `make real` で起動する。Firebase は必要ない。呼び出し回数と費用の確かめ方は [api-usage.md](api-usage.md) に記述する。

## Android エミュレータ

```bash
flutter emulators --launch Pixel_10_Pro_API_36
```

```bash
cd app && flutter run
```

実行中に `r` を押すと画面の変更が反映され、`R` を押すとアプリを最初から起動し直す。

## Android の実機

端末の設定の「開発者向けオプション」で「USB デバッグ」をオンにし、USB でつなぐ。Xiaomi などの一部の機種では「USB 経由でインストール」もオンにし、インストールのときに端末に出る確認で許可する。`flutter devices` に端末が表示されれば準備できている。

```bash
cd app && flutter run
```

PC で動かした API サーバーを実機から使うときは、起動する前に端末の 8080 番ポートを PC へ転送する。転送しなければ、`apiBaseUrl` のサーバーかダミーデータを使う。

```bash
adb reverse tcp:8080 tcp:8080
```

Wi-Fi でつなぐときは、端末の「ワイヤレス デバッグ」でペア設定コードを表示し、表示された IP アドレスとポートで `adb pair`、続けて `adb connect` を実行する。

## 配布用のビルド

配布用のビルドには Firebase の設定（`app/.env` の `FIREBASE_*`）が必要である。Android は、Gradle がビルドのたびに `app/.env` から `app/assets/config/firebase.local.json`（Git に含めない）を作ってアプリに同梱するので、そのままビルドする。

```bash
cd app && flutter build apk --release
```

APK は `app/build/app/outputs/flutter-apk/` に、全部入りの `app-release.apk`（約 65 MB）と、CPU の種類（ABI）ごとの APK（約 25 MB）が同時にできる。ABI ごとの APK は端末に合うライブラリだけを含むので、配るときはこちらを使う。いまの Android 端末のほとんどは `app-arm64-v8a-release.apk`、古い 32 ビットの端末は `app-armeabi-v7a-release.apk`、PC のエミュレータは `app-x86_64-release.apk` で、どれか分からない端末には `app-release.apk` を入れる。ABI ごとに分ける設定は `app/android/app/build.gradle.kts` にあり、`--split-per-abi` を付けなくても分かれる。

Web は、`app/.env` から設定のファイルを作ってからビルドする。

```bash
cd app && dart run tool/apply_env.dart
```

```bash
cd app && flutter build web --release
```

## 地図のキー

アプリの鍵と設定は `app/.env`（`app/.env.example` をコピーする。Git に含めない）に書く。地図のキーは `MAPS_WEB_API_KEY` と `MAPS_ANDROID_API_KEY` である。Android 版のビルドは `.env` を直接読む。Web 版と Firebase の設定は、次のコマンドでアプリ用のファイルを作ってからビルドする。

```bash
cd app && dart run tool/apply_env.dart
```

```bash
cd app && flutter run -d chrome --dart-define-from-file=dart_defines.local.json
```

`flutter build` にも同じ `--dart-define-from-file` を付ける。CI では環境変数 `MAPS_ANDROID_API_KEY` でも Android 版のキーを渡せる。

## 見た目の設定

アプリの右上のパレットのボタンから設定の画面を開き、テーマ（自動、ライト、ダーク）とキーカラーを選ぶ。キーカラーはウラミチの色、端末の壁紙の色（Android 12 以降）、用意した8色、カラーピッカーで選んだ色から選べる。選んだ値は端末に保存される。ウラミチの色は `app/lib/core/theme.dart` の `AppTheme.keyColor` で決める。

エミュレータの表示をダークモードに切り替えるには、次を実行する（`no` でライトに戻る）。

```bash
adb shell cmd uimode night yes
```

## ビルドで出る表示

`flutter build apk` で次の表示が出ても、APK は正しく作られる。どれもアプリのコードからは消せないので、そのままにする。

| 表示 | 意味 |
|---|---|
| `WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): firebase_auth, firebase_core` | Flutter は、プラグインの `build.gradle` に古い Kotlin の組み込み方の記述があるかを文字列で調べて、この警告を出す。Firebase のプラグインは、アプリが新しい組み込み方（`android/gradle.properties` の `android.builtInKotlin=true`）を使う場合は古い方式を使わないが、その分岐の記述が残っているため警告が出る。Firebase がこの記述を消した版を出せば警告は消える |
| `Font asset "MaterialIcons-Regular.otf" was tree-shaken …` | 使っていないアイコンを削り、フォントを小さくしたという案内 |
| `Caught exception: Already watching path: …` | Flutter のツールがフォルダの監視を二重に始めようとしたときの表示 |

## 表示がおかしいとき

AndroidManifest.xml、`build.gradle.kts`、依存関係を変えたあとに表示や動作がおかしいときは、作り直す。

```bash
cd app && flutter clean && flutter pub get
```
