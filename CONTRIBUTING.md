# 開発のルール

5 日間・4 人で、夜だけ集まって作るためのルールです。迷ったら A が決めます。

## 1. 役割とフォルダの持ち主

機能ごとに縦割りで担当します。自分のフォルダは自由に変えてかまいません。

| 担当 | 機能 | 持つフォルダ |
|---|---|---|
| A | 未踏サーチ、地図、Places API、範囲の最終判断 | `app/lib/core/widgets/places_map.dart`、`backend/internal/api/places.go`、`backend/internal/places/` |
| B | 代わりに行くならここ、未知度スコア | `app/lib/features/alternatives/`、`backend/internal/places/typemap.go`、`backend/internal/places/score.go` |
| C | チェックイン、思い出ログ、バッジ、Firebase 全般 | `app/lib/features/checkin/`、`app/lib/core/data/`、`backend/internal/api/checkins.go`、`backend/internal/store/`、`firestore.rules`、`firebase.json` |
| D | テスト、フィードバック、ダミー JSON、スライド・動画 | `backend/internal/places/mockdata/`、`docs/`、Issues |

**共通部分**（`app/lib/core/` のモデル・API・テーマ、`backend/internal/places/place.go`、API の応答の形）を変えるときは、**先にチャットで一言**伝えてから変えます。`Place` の項目を増やすときは、次の 3 つを同じプルリクエストで直します。

- `backend/internal/places/place.go`
- `app/lib/core/models/place.dart`
- `docs/data-model.md`

## 2. ブランチとマージ

- `main` は**毎晩デモできる状態**にする。直接 push しない
- ブランチ名：`feat/<担当>-<内容>`、`fix/<担当>-<内容>`（例：`feat/a-area-search`、`fix/c-checkin-order`）
- 1 つのプルリクエストは小さく（半日以内の作業）。夜の定例までにマージする
- マージの前に `main` を取り込み、テストが通ることを手元で確かめる

```bash
git switch main && git pull
git switch -c feat/b-multi-point-search
# …作業…
git push -u origin feat/b-multi-point-search   # GitHub でプルリクエストを作る
```

プルリクエストを作ると、GitHub Actions の CI（`.github/workflows/ci.yml`）が、変更したフォルダに関係する次のジョブを自動で実行します。ドキュメントだけの変更では秘密情報のチェックだけが動きます。**CI が赤いうちはマージしない**でください。

- backend：`gofmt`、`go vet`、`go test -race`（`internal/store/` などを変えたときは Firestore エミュレーターでも確かめる）
- app：`flutter analyze`、`flutter test`、`flutter build web`

手元でも同じコマンドで確かめられます。

## 3. レビュー

- **A のプルリクエストは B が、B のものは C が、C のものは A が見る**（A→B→C→A）
- 見る観点は 3 つだけ：**動くか**、**秘密情報が入っていないか**、**共通部分を勝手に変えていないか**
- 30 分以内に見られないときはチャットで伝え、次の人に回す

## 4. コミットメッセージ

`<種類>(<担当>): <何をしたか>` の形で、日本語で書きます。

| 種類 | 使うとき |
|---|---|
| `feat` | 機能を足す |
| `fix` | バグを直す |
| `docs` | ドキュメントだけ |
| `chore` | 設定・依存関係など |

例：`feat(b): 有名スポットの周辺を 3 点で検索する`、`fix(c): 2 回目のチェックインで順番が増えるのを直す`

AI のコーディング支援を使ったコミットは、提出ドキュメントの「AI をどう使ったか」に書けるよう、プルリクエストの説明に一言残します。

## 5. コードの書き方

- 整形：`gofmt -w .`（backend）、`dart format .`（app）
- 警告ゼロ：`go vet ./...`（backend）、`flutter analyze`（app）
- コメントと画面の文言は日本語でよい
- やり残しは `// TODO(A): 〜` のように担当を付けて書く（検索で拾えるように）
- 画面から `http` を直接呼ばない。`UramichiApi`（app/lib/core/api/）を通す
- チェックインと思い出ログは `CheckinRepository`（app/lib/core/data/）を通す。アプリから Firestore を呼ばない
- 色は `AppTheme`（app/lib/core/theme.dart）から使い、直書きしない

## 6. 秘密情報

このリポジトリは非公開ですが、最終版は公開の提出用リポジトリに送ります。秘密情報は一度でもコミットに入れないでください。

- API キー・サービスアカウントの鍵・パスワードは**絶対にコミットしない**
- サーバーの鍵は `backend/.env`、アプリの地図のキーと Firebase の設定は `app/.env` に書く（それぞれ `.env.example` をコピー）。本番のサーバーは Cloud Run の環境変数（Secret Manager）で渡す（docs/build-and-run.md）
- 誤って push したら、**すぐにキーを無効にして作り直し**、チャットと運営に連絡する（履歴から消すだけでは不十分）

## 7. Issues（D の指摘）

テンプレート（バグ・使いにくい・新しい案）から作ります。ラベルは「種類」と「担当」を 1 つずつ付けます。

| 種類のラベル | 例 | いつ直すか |
|---|---|---|
| `bug:stop` | 画面が落ちる、検索が返らない | その日のうち（チャットでも即連絡） |
| `bug` | 称号の表示がずれる | 次のビルド |
| `ux` | ボタンが分かりにくい | 3 日目の夜までなら受ける |
| `idea` | こういう機能が欲しい | Plan B の一覧へ。今回は原則やらない |

担当のラベル：`A`・`B`・`C`

## 8. 締切

| いつ | 何をする |
|---|---|
| 毎晩の定例 | main へのマージ、ビルドの配布、指摘の仕分け |
| 3 日目の夜 | **機能の凍結**。以降はバグ修正だけ |
| 5 日目の正午 | **コードの凍結**。以降は発表の準備だけ |
| 11/10（火）17:00 | 提出締切。最終版を運営の提出用リポジトリへ送る（最終版のファイルだけを 1 コミットにまとめる）。以降は読み取り専用になる |

## 9. 技術を選んだら記録する（Own the Why）

テーマが「Own the Why, Build with Intent.」なので、AI の提案をそのまま採らず、選んだ理由を自分の言葉で残します。
ライブラリや API を新しく使う・やめるときは、[docs/decisions.md](docs/decisions.md) に 1 項目足してください。使った素材やライブラリは [docs/credits.md](docs/credits.md) にも足します。
