# データの形

## `Place`（サーバーとアプリで共通）

API の応答の `places[]`・`origin`・`alternatives[]` はすべてこの形です。

| 項目 | 型 | 必須 | 意味 |
|---|---|---|---|
| `id` | string | ○ | Places API の place ID。Firestore のドキュメント ID にも使う |
| `name` | string | ○ | 表示名 |
| `lat`, `lng` | number | ○ | 位置 |
| `address` | string | | 住所 |
| `primaryType` | string | | 主な種類（`park` など） |
| `types` | string[] | ○ | 種類の一覧 |
| `userRatingCount` | int | ○ | 口コミ数（未知度の材料）。お気に入りの一覧の場所だけは取得しないので含めず、アプリは口コミ数が分からない場所として扱う（`Place.reviewCountKnown`） |
| `rating` | number | | 評価 |
| `obscurity` | int | | 未知度スコア 0〜100（大きいほど知られていない） |
| `title` | string | | 称号（下の表） |
| `distanceMeters` | int | | 有名スポットからの距離（代替提案）、または Geminiちゃんが探した中心からの距離（おすすめ） |
| `hits`, `misses` | int | | ウラミチの利用者が付けた当たりとハズレの数（0 なら省く。`mock=1` の検索では付けない）。★3 以上を当たりとして数える |
| `stars`, `starCount` | float, int | | ウラミチの利用者が付けた★評価の平均（1〜5、小数第1位まで）と数（★評価がなければ省く） |

コード：`backend/internal/places/place.go`、`app/lib/core/models/place.dart`

> 企画書の `Place` クラスと項目が違う場合は、こちらを企画書に合わせて直してください（A が判断）。

### 称号

口コミ数で決めます（仮。B が D の指摘を受けて調整）。

| 値 | 表示 | 口コミ数 |
|---|---|---|
| `untrodden` | 未踏 | 10 以下 |
| `hidden` | 穴場 | 100 以下 |
| `known` | 定番 | 1000 以下 |
| `famous` | 超有名 | それより多い |

未知度スコア：`(1 − log(1+口コミ数) / log(1+5000)) × 100`（口コミ 5000 件以上で 0）

## Firestore

| パス | 項目 | 書く人 |
|---|---|---|
| `places/{placeId}` | `visitorCount`（int）、`hits`、`misses`（当たりとハズレの数）、`ratingSum`、`ratingCount`（★評価の合計と数） | API サーバー |
| `places/{placeId}/verdicts/{uid}` | `verdict`、`rating`（1 人 1 票にするための、いちばん後に訪問した記録の評価） | API サーバー |
| `places/{placeId}/checkins/{uid}` | `order`（何人目か）、`at`（日時）、`geo`（距離を確かめた地点の区画） | API サーバー（1 人につき 1 回だけ） |
| `users/{uid}/logs/{logId}` | `placeId`、`verdict`（`hit`/`miss`）、`rating`（★1〜5。★評価の前の記録にはない）、`comment`、`order`、`photoPath`、`createdAt`（日時の型）、`public`、`geo` | API サーバー |
| `users/{uid}/favorites/{placeId}` | `createdAt`（お気に入りに入れた日時。place ID のほかは保存しない） | API サーバー |
| `timeline/{id}` | `author`、`placeId`、`verdict`、`rating`、`comment`、`order`、`createdAt`、`geo`、`public`、`reports` | API サーバー |
| `timeline/{id}/reports/{uid}` | `at`（報告した日時） | API サーバー |
| `authors/{AuthorTag}` | `nickname`、`icon`、`updatedAt` | API サーバー |
| `usage/{JST の日付}` | `real`、`simulated`（「種類.機能」ごとの Places API の呼び出し回数） | API サーバー |
| `usage/{JST の日付}/users/{uid}` | `calls`（1 人あたりの検索の呼び出し回数）。Place Details の回数は `{uid}:{種類}` のドキュメントに分ける | API サーバー |

- **place ID と訪問者数のほかに、Places API の内容は保存しない**。Google Maps Platform の利用規約で、Places API のコンテンツの保存が制限されているため（place ID は保存してよい）
- 思い出ログとタイムラインの場所の名前は、一覧を返すときに place ID ごとに Place Details で読む
- `geo` は 5 文字の geohash（約 5 km 四方）である。場所の位置は保存せず、公開した記録を周辺で探すためにチェックインの地点の区画だけを保存する
- 非公開に戻した `timeline` の文書は、報告の数を残すために消さず、`comment` と `placeId` を消す
- Firestore を読み書きするのはサーバーだけである。何人目かは、チェックインと `visitorCount` の更新を同じトランザクションで行って決める
- `firestore.rules` は、クライアントからの読み書きを全て禁止する
- `AuthorTag` は uid の SHA-256 から作る 32 文字の符号で、`timeline/{id}` の `author` と同じ値である。プロフィールを uid ではなくこの符号で保存するので、タイムラインの投稿者の表示に uid を使わずに済む
- `logId` は、アプリが `clientId` を送ったときは `lg_{clientId}` になる

## 端末に保存するデータ（shared_preferences）

| キー | 内容 | 消えるとき |
|---|---|---|
| `pendingCheckins.{uid}` | その利用者の未送信のチェックイン（`placeId`、`placeName`、`lat`、`lng`、`visitedAt`）と思い出ログ | 送信したとき、サーバーが受け取らなかったとき |
| `cachedLogs.{uid}` | その利用者が最後にサーバーから読めた自分の思い出ログ（場所の名前を除く） | 次に読めたときに上書きする |
| `visitRecorder` | 滞在の記録（位置、始まりと終わりの時刻）、提案しない地点、判定の途中の状態 | 回答したとき、滞在の終わりから 14 日後（最大 30 件）、ログアウトしたとき |
| `visitSamples` | バックグラウンドで測定した位置と時刻（最大 1000 件） | アプリを開いて滞在へ変換したとき、記録をやめたとき、ログアウトしたとき |
| `localCheckins` | Firebase の設定がない開発中のビルドのチェックインと思い出ログ | アプリのデータを消したとき |
| `themeMode`、`keyColor`、`haptics`、`sound`、`demoMode`、`lastMapLat`、`lastMapLng` | 設定の画面で選んだテーマ、キーカラー、振動、効果音、デモデータと、最後に見ていた地図の地点 | アプリのデータを消したとき |

利用者を区別していなかった版の `pendingCheckins` と `cachedLogs` は、誰の記録か分からないため、起動したときに送らずに消す。

スポットの名前を端末に保存するのは、送信するまでの未送信のチェックインと思い出ログだけである。圏外で表示する一覧には名前が含まれない。滞在の記録には place ID も名前も保存しない。

## ダミー JSON（`backend/internal/places/mockdata/`）

- `nearby.json`：Nearby Search の応答と同じ形（`{ "places": [ ... ] }`）
- `text_search.json`：Text Search の応答と同じ形。検索語に一致しなければ先頭を返す

各要素は Places API (New) の形です。

```json
{
  "id": "mock_01",
  "displayName": { "text": "坂の上の小さな祠", "languageCode": "ja" },
  "location": { "latitude": 34.697, "longitude": 135.192 },
  "primaryType": "shinto_shrine",
  "types": ["shinto_shrine", "place_of_worship"],
  "userRatingCount": 0,
  "formattedAddress": "（架空の住所）"
}
```

**中身は架空のデータにします。** 形を確かめるために本物の応答を見るのはよいですが、そのままリポジトリに貼らないでください（最終版は公開の提出用リポジトリに送るため）。規約上の問題になり得ます。
