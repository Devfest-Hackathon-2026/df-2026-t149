# ウラミチ API サーバー（Go / Cloud Run）

アプリ（`app/`）から呼ぶ API サーバー。Places API を呼んで未知度スコアと称号を付けるほか、チェックインと思い出ログを Firestore に保存する。

- **パスとデータの形は、アプリが今受け取れる形に合わせている**（アプリを変えずに受け取れる）。仕様はチームの「ウラミチ API仕様」を参照
- アプリからは必ずこのサーバーを経由する。Firestore を読み書きするのはこのサーバーだけ（セキュリティルールでクライアントからの読み書きはすべて禁止する）

## すぐ動かす

API キーや Firebase がなくても、ダミーデータとメモリへの保存で動く。

```sh
cd backend
make dev      # AUTH_MODE=fake STORE_MODE=memory、PLACES_API_KEY なし（ダミーデータ）
make test
make real     # .env の PLACES_API_KEY で本物の Places API を呼ぶ
make usage    # Places API の呼び出し回数と料金の目安を表示する（docs/api-usage.md）
```

`internal/store/` のテストは、`FIRESTORE_EMULATOR_HOST` を設定するとエミュレーターの Firestore でも動く。

```sh
npx -y firebase-tools@14 emulators:exec --only firestore --project uramichi-test "cd backend && go test -race ./internal/store/"
```

アプリは開発中、`http://localhost:8080`（Android エミュレータからは `http://10.0.2.2:8080`）の `/api/health` が応答すれば、このサーバーを使う。

```sh
curl localhost:8080/api/health
# AUTH_MODE=fake では Bearer の後ろの文字列がそのまま uid になる
curl -H 'Authorization: Bearer alice' 'localhost:8080/api/explore?lat=34.693&lng=135.19&radius=1500'
curl -G -H 'Authorization: Bearer alice' localhost:8080/api/alternatives --data-urlencode 'q=清水寺' -d radius=3000

# チェックインと思い出ログ
curl -X POST -H 'Authorization: Bearer alice' localhost:8080/api/checkins -d '{"placeId":"mock_01","lat":34.69,"lng":135.19}'
curl -H 'Authorization: Bearer alice' localhost:8080/api/places/mock_01/visitors
curl -X POST -H 'Authorization: Bearer alice' localhost:8080/api/logs \
  -d '{"placeId":"mock_01","verdict":"miss","comment":"閉まってた"}'
curl -H 'Authorization: Bearer alice' localhost:8080/api/logs

# Geminiちゃん（GEMINI_MODE=fake ではキーワードで答える）
curl -X POST -H 'Authorization: Bearer alice' localhost:8080/api/assistant \
  -d '{"message":"近くの静かなカフェを教えて","lat":34.693,"lng":135.19}'
```

Geminiちゃんの品質を数字で比べる（モデルやプロンプトを変えたとき用）。発言の一覧は `cmd/evalassistant/cases.json`。

```sh
go run ./cmd/evalassistant -mode fake -v                        # 簡易版の基準値
go run ./cmd/evalassistant -mode vertex -project <ID> -v        # gcloud auth application-default login が必要
go run ./cmd/evalassistant -mode vertex -project <ID> -model gemini-3.1-flash
```

## API

| メソッド | パス | 機能 | 認証 |
|---|---|---|---|
| GET | `/api/health` | 死活確認 | なし |
| GET | `/api/usage` | Places API の呼び出し回数と料金の目安（`AUTH_MODE=fake` のときだけ） | なし |
| GET | `/api/explore?lat&lng[&radius][&purpose=checkin][&mock=1]` | 未踏サーチ、チェックインの候補 | IDトークン |
| GET | `/api/alternatives?q[&radius][&mock=1]` | 代わりに行くならここ | IDトークン |
| GET | `/api/locate?q[&mock=1]` | 地図を移動する先を探す | IDトークン |
| GET | `/api/places/{placeId}/visitors` | 訪問者数 | IDトークン |
| POST | `/api/checkins` | 古参チェックイン | IDトークン |
| POST | `/api/logs` | 思い出ログを残す | IDトークン |
| GET | `/api/logs` | 自分の思い出ログの一覧 | IDトークン |
| PATCH | `/api/logs/{logId}` | 自分の記録の公開状態を変える | IDトークン |
| GET | `/api/timeline?lat&lng` | 周辺で公開された記録 | IDトークン |
| POST | `/api/timeline/{entryId}/report` | 公開された記録を報告する | IDトークン |
| GET | `/api/me` | 自分のプロフィール（ニックネームとアイコン） | IDトークン |
| PUT | `/api/me` | 自分のプロフィールを保存する | IDトークン |
| POST | `/api/assistant` | Geminiちゃん（穴場のおすすめと理由、検索の条件） | IDトークン |
| GET | `/api/gacha` | 逆張りガチャ（Plan B） | 501 を返す |

- `/api/health` と `/api/usage` 以外は IDトークンが必須。認証なしで Firestore の読み取りやサーバーの処理を繰り返し消費されないよう、`mock=1` の検索と訪問者数も含める
- 応答の `source` は、本物のデータなら `google`、ダミーなら `mock`。`mock=1` を付けるとダミーを返し、ダミーの場所には当たりとハズレの数を付けない
- 本物の Places API が失敗したとき・1日の上限に達したときもダミーを返し、`source: "mock"` にする（デモの保険）。`purpose=checkin` のときだけは、ダミーのスポットにチェックインさせないよう 503 を返す
- IDトークンが必要な API は、匿名ログインのトークンを 403 の `login_required` で拒否する。`AUTH_MODE=fake` では `anon:` で始まるトークンが匿名ログインの扱いになる
- エラーは `{"error":{"code":"bad_request","message":"…"}}`。`message` は利用者に見せてよい日本語の文
- チェックインと思い出ログの API は、アプリの `CheckinRepository` の4つのメソッドに1つずつ対応する。思い出ログの `order` はアプリから送られても読まず、チェックインの記録から決める（本人が値を偽れないようにするため）。日時はアプリの `visitedAt` を使い、`clientId` が同じ送信は二重に保存しない（圏外で保存した記録を後から送るため）

## 環境変数

`.env.example` を参照。

| 変数 | 既定 | 説明 |
|---|---|---|
| `PORT` | `8080` | Cloud Run が設定する |
| `PLACES_API_KEY` | なし | 空なら Places API を呼ばずにダミーだけで動く。本番は Secret Manager から渡す |
| `PLACES_DAILY_LIMIT` | `100` | サーバー全体で Places API を呼ぶ1日の上限（JST の日付で区切る） |
| `PLACES_USER_DAILY_LIMIT` | `30` | 1人が Places API を呼べる1日の回数。代替提案の検索は1回で4回分になる |
| `PLACES_DETAILS_DAILY_LIMIT` | `150` | サーバー全体で Place Details と地点の検索を種類ごと（位置の確認、名前の取得、地点の検索）に呼ぶ1日の上限 |
| `ALLOWED_ORIGINS` | なし | CORS で許すオリジン（カンマ区切り）。localhost は常に許す。本番の Web 版は Hosting 経由で同じオリジンなので不要 |
| `AUTH_MODE` | `firebase` | `firebase`（IDトークンを検証）/ `fake`（ローカル専用。Cloud Run 上では起動時にエラー） |
| `STORE_MODE` | `firestore` | `firestore` / `memory`（ローカル専用） |
| `GEMINI_MODE` | `fake` | `vertex`（Vertex AI の Gemini を呼ぶ。ADC で認証する）/ `fake`（キーワードで答える簡易版だけ） |
| `GEMINI_MODEL` | `gemini-3.1-flash-lite` | Vertex AI のモデル ID |
| `GEMINI_LOCATION` | `global` | Vertex AI のリージョン |
| `GEMINI_DAILY_LIMIT` | `300` | サーバー全体で Gemini を呼ぶ1日の上限。1回の相談で最大2回呼ぶ。上限に達すると簡易版で答える |
| `GEMINI_USER_DAILY_LIMIT` | `30` | 1人が Gemini を呼べる1日の回数 |
| `GOOGLE_CLOUD_PROJECT` | なし | `AUTH_MODE=firebase`、`STORE_MODE=firestore`、`GEMINI_MODE=vertex` のとき必要 |
| `FIRESTORE_EMULATOR_HOST` | なし | 設定すると Firestore エミュレーターにつながる |

## 構成

```
cmd/server/          main。設定を読み、依存を組み立てて起動する
internal/config/     環境変数
internal/api/        ルーティング、CORS、認証、ハンドラー
internal/auth/       Firebase IDトークンの検証（と fake）
internal/assistant/  Geminiちゃん。Vertex AI の Gemini（gemini.go）と、キーワードで答える簡易版（fake.go）、回数の上限と切り替え
internal/places/     Places API (New) クライアント、ダミー（mockdata/）、本物とダミーの切り替え、未知度スコアと称号、種類の対応表
internal/store/      チェックイン、思い出ログ、呼び出し回数の保存（Firestore / メモリ）
internal/usage/      呼び出し回数の型と料金の目安の計算
internal/apierr/     エラーコード
```

### Dart のサーバーとの関係

このサーバーは、以前の Dart のサーバー（`server/`、削除済み）の代わりで、アプリから見た動きは同じにしている。

- `internal/places/mockdata/` は、Dart のサーバーの `server/mock/` と同じ内容
- `internal/api/api_test.go` の `TestMatchesAppBundledMock` は、アプリに同梱したダミー（`app/assets/mock/`）と同じ JSON を返すことを確かめる。このダミーは Dart のサーバーを `mock=1` で呼んで作ったもの
- 未知度スコアの式と称号の区切りは Dart のサーバーと同じ（どれも仕様で【未決】。変えてもアプリの変更はいらない）。代替提案の選び方は [docs/architecture.md](../docs/architecture.md) に記述している

## デプロイ（例）

Firestore を読み書きするので、専用のサービスアカウントに `roles/datastore.user`、`roles/secretmanager.secretAccessor`、`roles/aiplatform.user`（Geminiちゃん）を付ける。呼び出し回数は Firestore に保存する。インスタンスを1つにするのは Cloud Run の費用の上限にするためである。

```sh
gcloud run deploy uramichi-api --source backend --region asia-northeast1 \
  --allow-unauthenticated --max-instances 1 \
  --service-account uramichi-api@PROJECT_ID.iam.gserviceaccount.com \
  --set-secrets PLACES_API_KEY=places-api-key:latest \
  --set-env-vars AUTH_MODE=firebase,STORE_MODE=firestore,GOOGLE_CLOUD_PROJECT=PROJECT_ID,PLACES_DAILY_LIMIT=100,PLACES_USER_DAILY_LIMIT=30,PLACES_DETAILS_DAILY_LIMIT=150,GEMINI_MODE=vertex
```

サービス名（`uramichi-api`）とリージョンは、`firebase.json` の転送先と同じにする。
