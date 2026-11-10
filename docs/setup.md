# セットアップとデプロイ

上から順にやれば、本物のデータで動く本番環境ができます。**API キーはどれもリポジトリに書かないでください。**

表記：`PROJECT_ID` はチームの Google Cloud プロジェクトの ID に置き換えます。

## 0. 手元の準備（全員）

- Flutter（stable）を入れる：https://docs.flutter.dev/get-started/install
- 確認：`flutter doctor`
- README の「起動方法（ローカル）」でダミーデータのまま動くことを確かめる

## 1. Google Cloud（A）

```bash
gcloud auth login
gcloud config set project PROJECT_ID
gcloud services enable places.googleapis.com run.googleapis.com \
  cloudbuild.googleapis.com artifactregistry.googleapis.com \
  secretmanager.googleapis.com firestore.googleapis.com \
  aiplatform.googleapis.com
```

`aiplatform.googleapis.com` は Geminiちゃん（Vertex AI の Gemini）に使う。API キーはなく、Cloud Run のサービスアカウントで呼ぶ。

**予算アラート**（コンソール > お支払い > 予算とアラート）：予算 $20、しきい値 25%・50%・75%（$5・$10・$15）。
通知が来るだけで自動では止まらないので、通知が来たら使っていないものを止めます。

### Places API のキー（サーバー用）

1. コンソール > API とサービス > 認証情報 > 認証情報を作成 > API キー
2. 「API の制限」で **Places API (New)** だけを許可する
3. Places API (New) の割り当て（クォータ）で、1 日の上限を下げる（計画では 1 日 100 回）
4. キーは Secret Manager に入れる（チャットや `.env` 以外に貼らない）

```bash
printf '%s' 'ここにキー' | gcloud secrets create places-api-key --data-file=-
```

すでに `places-api-key` がある（`already exists` と出る）ときは、作り直さずに新しいバージョンを足す。Cloud Run は `latest` を読むので、次のデプロイから使われる。
中身を確かめるときも、値を画面に出さず、デプロイ後の `/api/health` が `"places":"google"` になるかで見る。

```bash
printf '%s' 'ここにキー' | gcloud secrets versions add places-api-key --data-file=-
gcloud secrets versions list places-api-key   # バージョンが有効か見る（値は出ない）
```

> 取得する項目（`backend/internal/places/google.go` の `fieldMask`）によって料金の区分が変わります。
> `rating` と `userRatingCount` を含むので Enterprise 区分になります。回数と料金の確かめ方は [api-usage.md](api-usage.md) に記述しています。

## 2. API サーバーを Cloud Run にデプロイ（A）

```bash
gcloud iam service-accounts create uramichi-api
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member serviceAccount:uramichi-api@PROJECT_ID.iam.gserviceaccount.com \
  --role roles/datastore.user
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member serviceAccount:uramichi-api@PROJECT_ID.iam.gserviceaccount.com \
  --role roles/secretmanager.secretAccessor
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member serviceAccount:uramichi-api@PROJECT_ID.iam.gserviceaccount.com \
  --role roles/aiplatform.user

gcloud run deploy uramichi-api \
  --source backend \
  --region asia-northeast1 \
  --allow-unauthenticated \
  --max-instances 1 \
  --service-account uramichi-api@PROJECT_ID.iam.gserviceaccount.com \
  --set-secrets PLACES_API_KEY=places-api-key:latest \
  --set-env-vars AUTH_MODE=firebase,STORE_MODE=firestore,GOOGLE_CLOUD_PROJECT=PROJECT_ID,PLACES_DAILY_LIMIT=100,PLACES_USER_DAILY_LIMIT=30,PLACES_DETAILS_DAILY_LIMIT=150,GEMINI_MODE=vertex,GEMINI_DAILY_LIMIT=300,GEMINI_USER_DAILY_LIMIT=30
```

- `--max-instances 1`：Cloud Run の費用の上限にする。1 日の呼び出し回数は Firestore に保存するので、インスタンスが入れ替わっても数え直さない
- 専用のサービスアカウントには、Firestore を読み書きする権限と Secret を読む権限を付ける
- `roles/aiplatform.user`：Vertex AI の Gemini を呼ぶ権限。`GEMINI_MODE=vertex` にしないと、Geminiちゃんはキーワードで答える簡易版だけで動く
- モデルは `GEMINI_MODEL`（既定 `gemini-3.1-flash-lite`）、リージョンは `GEMINI_LOCATION`（既定 `global`）で変えられる。デプロイ前にモデルが提供中かを Vertex AI の「Model versions and lifecycle」で確かめる
- 確認：`curl https://<表示された URL>/api/health` で `"places":"google"`、`"assistant":"gemini"` になっていること

手元で本物の Gemini を試すときは、`gcloud auth application-default login` の後に `GEMINI_MODE=vertex GOOGLE_CLOUD_PROJECT=PROJECT_ID make dev` で起動する。

### 自動デプロイ（GitHub Actions）

`main` に `backend/` の変更が入ると、`.github/workflows/deploy-backend.yml` がテスト、イメージの作成、Cloud Run への反映、動作の確認までを行う。JSON 鍵は使わず、Workload Identity Federation でこのリポジトリからだけ入れるようにする。

**初回の準備（1 回だけ）**

1. Google Cloud 側を整える。API の有効化、Artifact Registry、サービスアカウント 2 つ、WIF を作る。何度流してもよい。

   ```bash
   # bash / zsh
   PROJECT_ID=PROJECT_ID ./scripts/gcp-bootstrap.sh
   # fish（VAR=値 の書き方が使えない）
   set -x PROJECT_ID PROJECT_ID; ./scripts/gcp-bootstrap.sh
   ```

2. 終わりに表示される 3 つの値を、GitHub の Variables に登録する。
   リポジトリの Settings > Secrets and variables > Actions > **Variables** タブ > New repository variable。秘密ではないので Secrets でなくてよい。

   | 名前 | 値 |
   |---|---|
   | `GCP_PROJECT_ID` | プロジェクト ID |
   | `GCP_DEPLOY_SA` | `github-deployer@PROJECT_ID.iam.gserviceaccount.com` |
   | `GCP_WIF_PROVIDER` | `projects/<プロジェクト番号>/locations/global/workloadIdentityPools/github/providers/github` |

   `gh` が使えるなら、`gh variable set GCP_PROJECT_ID --body PROJECT_ID` のようにも登録できる。

3. Secret `places-api-key` に Places API のキーが入っていることを確かめる（上の「Places API のキー」）。無いとデプロイが失敗する。

**デプロイする**

- 自動：`main` に `backend/` の変更をマージする
- 手動：GitHub の Actions > Deploy backend > Run workflow（`workflow_dispatch`）。この workflow が `main` に入っていないと、手動実行の画面に出ない

**確かめる**

```bash
curl "$(gcloud run services describe uramichi-api --region asia-northeast1 --format 'value(status.url)')/api/health"
# {"ok":true,"places":"google","assistant":"gemini"} が返れば、サーバーは本物の Places API と Gemini を使って動いている
```

**うまくいかないとき**

- 認証でエラー：`GCP_WIF_PROVIDER` と `GCP_DEPLOY_SA` の値、リポジトリ名（`scripts/gcp-bootstrap.sh` の `GITHUB_REPO`）を見直す
- `places-api-key` が見つからない：上の手順でシークレットを作る
- 権限が足りない：`scripts/gcp-bootstrap.sh` をもう一度流す

## 3. Firebase（C）

1. Firebase コンソールで、上の Google Cloud プロジェクトに Firebase を追加する
2. Authentication > ログイン方法 > **Google** を有効にし、サポートのメールアドレスを選ぶ。表示された「ウェブ SDK 構成」の「ウェブ クライアント ID」を、`app/.env` の `FIREBASE_WEB_CLIENT_ID` に書く（Android 版のログインで使う）
3. Google Cloud コンソール > Google Auth Platform > 対象で、公開ステータスを「本番環境」にする。「テスト中」のままでは、登録した最大 100 人のテストユーザーしかログインできない。アプリは `openid`、`email`、`profile` だけを使うので、確認の審査は必要ない
4. Firestore を作る（ロケーション：`asia-northeast1`）
5. アプリに設定をつなぐ

```bash
npm install -g firebase-tools
firebase login
cp .firebaserc.example .firebaserc        # PROJECT_ID を書き換える
firebase deploy --only firestore:rules,firestore:indexes
```

Firebase コンソールのプロジェクトの設定にあるウェブアプリの構成の値を、`app/.env` の `FIREBASE_API_KEY`、`FIREBASE_PROJECT_ID`、`FIREBASE_MESSAGING_SENDER_ID`、`FIREBASE_WEB_APP_ID` に書き、`cd app && dart run tool/apply_env.dart` を実行します。`app/lib/firebase_options.dart` はビルドで渡されたこれらの値を読むので、`flutterfire configure` は使いません。
Cloud Storage（写真）を使うかどうかと、プランの要否は C が確認します。

### Android 版のログインに使う SHA-1 と SHA-256

Android 版の Google アカウントでのログインには、アプリに署名した鍵のフィンガープリントを Firebase に登録する必要があります。配布用 APK は、チームで保管する配布用の鍵で署名します。開発時のデバッグビルドは、各端末のデバッグ用の鍵で署名します。

1. Firebase コンソール > プロジェクトの設定 > マイアプリ > アプリを追加 > Android で、パッケージ名 `com.example.uramichi` のアプリを追加する（1 回だけ）
2. 配布用の鍵とパスワードを安全な方法でチームに共有する。鍵を `app/android/uramichi-release.p12` に置き、`app/.env` の `ANDROID_SIGNING_STORE_FILE`、`ANDROID_SIGNING_KEY_ALIAS`、`ANDROID_SIGNING_STORE_PASSWORD`、`ANDROID_SIGNING_KEY_PASSWORD` に共有された設定を書く。鍵と `.env` は Git に含めない
3. 配布用の鍵のフィンガープリントを調べる。パスワードはコマンド実行後の入力欄に入力する

   ```bash
   keytool -list -v -keystore app/android/uramichi-release.p12 -alias uramichi | grep -E "SHA1|SHA256"
   ```

4. 追加した Android アプリの「フィンガープリントを追加」で、SHA-1 と SHA-256 を登録する。地図のキーに Android アプリの制限を設定している場合は、そのキーにもパッケージ名と配布用の鍵の SHA-1 を登録する
5. `app/.env` の `FIREBASE_ANDROID_APP_ID` に Android アプリの「アプリ ID」を、`FIREBASE_WEB_CLIENT_ID` に Google のログイン方法の「ウェブ クライアント ID」を書き、`cd app && dart run tool/apply_env.dart` を実行してからビルドする。アプリは設定を `.env` から受け取るので、`google-services.json` は使わない

デバッグビルドで Google ログインを使う場合は、各端末で `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android` を実行し、その鍵の SHA-1 と SHA-256 も Firebase に登録する。

## 4. 地図のキー（A）

地図用のキーはアプリに入るので、**使える場所を制限**して作ります（サーバー用とは別のキー）。

| 種類 | 「API の制限」 | 「アプリケーションの制限」 |
|---|---|---|
| Android | Maps SDK for Android | Android アプリ（パッケージ名と SHA-1） |
| Web | Maps JavaScript API | ウェブサイト（Hosting のドメインと `localhost`） |

- `app/.env`（コミットされない）に `MAPS_ANDROID_API_KEY` と `MAPS_WEB_API_KEY` を書く
- `cd app && dart run tool/apply_env.dart` を実行してアプリを作り直すと、Google マップに自動で切り替わる
- Firebase の設定も同じ `.env` の `FIREBASE_*` に書く

## 5. Web 版を Firebase Hosting に公開（A）

```bash
cd app
dart run tool/apply_env.dart
flutter build web --release --dart-define-from-file=dart_defines.local.json
cd ..
firebase deploy --only hosting
```

`--dart-define-from-file` を付けずにビルドすると Firebase の設定が入らず、公開した画面は「ログインを準備できませんでした」になります。

`/api/**` は `firebase.json` の設定で Cloud Run（`uramichi-api`）へ転送されます。公開した URL は README の「デプロイ URL」に書きます。
**Regional Day（11/14）まで動かし続ける**ので、クレジットの残額と期限を確認しておきます。

## 6. Android 版を配る（A）

先に `app/assets/config/app_config.json` の `apiBaseUrl` に Cloud Run の URL を書いてコミットします。

```bash
cd app
dart run tool/apply_env.dart
flutter build apk --dart-define-from-file=dart_defines.local.json
firebase appdistribution:distribute build/app/outputs/flutter-apk/app-release.apk \
  --app <Firebase の Android アプリ ID> --groups team
```

先に Firebase コンソールの App Distribution で `team` グループを作り、テスター（D と友人）を入れておきます。グループがないと、アップロードは成功しても配布は 404 で失敗します。
