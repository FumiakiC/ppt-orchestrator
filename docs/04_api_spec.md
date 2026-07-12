# docs/04_api_spec.md — HTTP API 仕様（現状挙動の正本）

対象: `src/server.ps1`（Lobby / Dialog ループ）、`src/com-handler.ps1`（NowPlaying ループ）、`src/auth.ps1`、`src/utils.ps1` @ `c99e6d8`

> **本書の性格**: これは「あるべき仕様」ではなく **現状挙動の characterization（記述）** である。
> ⚠ 印の項目は `docs/03_refactoring_plan.md` で修正対象として確定済みの挙動であり、
> 該当 PR がマージされるまでは **本書の記述が正**。修正 PR は本書の更新を同 PR に含めること。

---

## 1. サーバの基本構造

HTTP は **単一スレッド逐次処理**（`$script:ContextTask` を 1 個だけ保持し `.Wait(100)`）。
実行中のモードによって**ルーティング表そのものが切り替わる**（同じパスでも応答が異なる）。

| モード | ルータ | 状態 |
|---|---|---|
| **Lobby / Dialog** | `src/server.ps1` `Invoke-WebRequestProcessor` | スライドショー非実行中（ファイル選択・次へ・終了） |
| **NowPlaying** | `src/com-handler.ps1` `Watch-RunningPresentation` 内のインラインルータ | スライドショー実行中（遠隔操作 API） |

- Listen prefix: `http://+:<WebPort>/`（既定 `8090`。`src/config.ps1` / `Start-Presenter.bat` の二箇所で定義）
- 平文 HTTP（TLS なし）。専用・保護されたネットワークでの運用が前提（README のセキュリティ節参照）。

## 2. 共通仕様

### 2.1 認証

- 方式: ホスト PC コンソールに表示される **日次 6 桁 PIN** → 成功時に **セッション Cookie** を発行。
- Cookie: `SessionToken=<guid:N>; HttpOnly; Path=/; SameSite=Strict`（`Secure` は HTTP 運用のため付与しない）
- 判定: `Test-IsAuthenticated` が Cookie 値と `$script:SessionToken` を**単純一致比較**（定数時間比較ではない）。
- token は**全端末で共有**され、明示的な失効（logout / lifetime）は**現状なし**。
- **未認証で通過できるパス**: `/status`、`/auth`（両モード共通）。

### 2.2 認証失敗時の throttle（`Invoke-AuthHandler`）

- IP 単位（`$script:AuthFailedTracker`）。**直近失敗から 1 秒以内**の試行は PIN 照合せず拒否。
- **拒否された試行はタイムスタンプを更新しない**（＝固定窓。実効レートは約 1 試行/秒で維持される）。
- 30 秒経過したエントリは掃除される。
- 指数バックオフ・lockout・global rate limit は**なし**（Phase 2 の仕様判断事項）。

### 2.3 レスポンス共通（`Send-HttpResponse`）

- 既定 Content-Type: `text/html; charset=utf-8`、`KeepAlive = $false`。
- 常に付与: `Cache-Control: no-cache, no-store, must-revalidate` / `Pragma: no-cache` / `Expires: 0`。
- セキュリティヘッダ（`X-Content-Type-Options` / `X-Frame-Options` / CSP 等）は**現状なし**（Phase 2 の下地作業）。
- クライアント切断（broken pipe）は握り潰す＝投影を止めない設計。

### 2.4 リクエストボディ（`Read-RequestBody`）

- 上限 **8192 文字**（`MaxChars`）。**超過時は空文字を返す**（=リクエストは無効扱い。413 等は返さない）。
- 抽出は正規表現ベース: `Get-CidFromBody`（`cid=([A-Za-z0-9_\-]+)`）/ `Get-PinFromBody`（`pin=([0-9]{6})`）。
  いずれも UrlDecode 後・**アンカー無し・大小無視**。期待表は `docs/01_characterization_spec.txt` [D] [E] が正。

---

## 3. Lobby / Dialog ループ（`src/server.ps1`）

| Method | Path | 認証 | 挙動 | レスポンス |
|---|---|---|---|---|
| GET | `/status` | 不要 | 状態文字列のみ返す（offline overlay 用の半意図的仕様） | 200 `text/plain` : `waiting` / `changing` / `stopping` |
| POST | `/auth` | 不要 | PIN 照合（throttle 適用） | 成功: **302** `Location: /` + `Set-Cookie`<br>失敗/throttle: **200** Auth 画面 HTML（error 表示） |
| GET | `/auth` | 認証済 | ルートへ戻す | 302 `Location: /` |
| GET | `/auth` | 未認証 | ⚠ **認証ミドルウェアを素通りし、Lobby/Dialog の HTML をそのまま返す**（＝**ファイル一覧が未認証で露出**）。計画書 §5.4・PR-D で修正予定 | 200 HTML（Lobby 本体） |
| POST | `/start` | 必要 | `ResultAction = Start` | 200 Processing HTML |
| POST | `/next` | 必要 | `ResultAction = Next` | 200 Processing HTML |
| POST | `/retry` | 必要 | `ResultAction = Retry` | 200 Processing HTML |
| POST | `/lobby` | 必要 | `ResultAction = Lobby` | 200 Processing HTML |
| POST | `/select` | 必要 | body の `filename=(.*)` を UrlDecode して選択（`ResultFile`）。**不一致なら何もせず Processing を返す** | 200 Processing HTML |
| POST | `/exit` | 必要 | シャットダウン開始（`ShuttingDown=true`, deadline = now+5s）。**PRG リダイレクト**でフォーム再送信による誤終了を防ぐ | 303 `Location: /exit` |
| GET | `/exit` | 必要 | `ShuttingDown` なら Exit 画面。そうでなければルートへ戻す | 200 Exit HTML / 302 `Location: /` |
| GET | 上記以外（`/` 含む） | 必要 | Lobby / Dialog 本体。ただし `ShuttingDown` → Exit HTML、`ResultAction != null` → Processing HTML（他端末操作時のチラつき防止） | 200 HTML |
| — | 未認証の上記以外 | — | **Auth 画面 HTML を 200 で返す**（401 は返さない） | 200 Auth HTML |

## 4. NowPlaying ループ（`src/com-handler.ps1`）

操作権（lock）モデル: クライアントは `cid`（POST body または GET クエリ）で自己識別する。
`lockActive` / `ownerCid` / `ownerSeen` を保持し、**無反応 15 秒（`ownerTtlSec`）で自動解放**。
`/slide/state`（mine のとき）と `/slide/*` 操作成功がハートビートになる。
スライドショー終了時に lock はスコープ破棄され安全リセットされる。

| Method | Path | 認証 | lock 要否 | 挙動 / レスポンス |
|---|---|---|---|---|
| GET | `/status` | 不要 | — | 200 `text/plain` : `running` |
| POST | `/auth` | 不要 | — | Lobby ループと同一（`Invoke-AuthHandler`） |
| GET | `/auth` | 認証有無に関係なく | — | ⚠ **NowPlaying の HTML をそのまま返す**（認証済みでも 302 `/` にはならない。Lobby ループの GET `/auth` と非対称）。PR-D で修正予定 |
| GET | `/elapsed` | 必要 | 不要 | 200 `text/plain` : 経過ミリ秒（整数） |
| GET | `/slide/state` | 必要 | 不要 | 200 JSON `{ms,pos,total,lock,mine,black,white,atEnd}`。`total` は初回のみ COM 取得しキャッシュ。`mine` のとき `ownerSeen` を更新（ハートビート） |
| POST | `/lock/on` | 必要 | — | 未ロック or 自分が owner: `{ok:true,mine:true,busy:false}` / 他端末が保持中: `{ok:false,mine:false,busy:true}` |
| POST | `/lock/steal` | 必要 | — | **無条件に奪取**し owner を自分に。`{ok:true,mine:true}`（誤爆防止は UI の長押しに依存） |
| POST | `/lock/off` | 必要 | owner のみ実効 | owner なら解放。**常に** `{ok:true}` |
| POST | `/slide/<cmd>` | 必要 | **必要** | `cmd ∈ {next, prev, first, last, blackout, whiteout}`。<br>未知コマンド: `{ok:false,error:'unknown'}`<br>lock 非保持 / 他端末保持: `{ok:false,locked:true}`（サーバ側でも拒否＝多層防御）<br>成功時: COM 実行結果を JSON で返す |
| POST | `/stop` | 必要 | ⚠ **不要** | ⚠ **owner チェックが無く、認証済みなら任意の端末が投影を停止できる**（cid も見ない）。`ManualStop` として NowPlaying ループを抜け 302 `Location: /`。権限モデルは計画書 §12 の仕様判断事項、PR-E で決着させる |
| — | 未認証 `/slide/*` `/lock/*` | — | — | **401** JSON `{"ok":false,"auth":false}`（XHR 用。クライアントが再認証へ誘導） |
| — | 未認証のその他 | — | — | 200 Auth HTML |
| — | 上記以外 | 必要 | — | 200 NowPlaying HTML |

---

## 5. 既知の課題（本書の ⚠ に対応）

| # | 挙動 | 影響 | 対応 |
|---|---|---|---|
| 1 | 未認証 `GET /auth` が Lobby / NowPlaying の HTML を返す | ファイル名・デッキ名・進行状態が未認証で露出 | PR-D |
| 2 | `POST /stop` に owner チェックが無い | 認証済みの任意端末が投影を停止できる（緊急停止としての意図の可能性あり＝要仕様判断） | PR-E |
| 3 | セキュリティヘッダ未付与 / token lifetime 無し / 単純一致比較 | 多層防御の欠如 | Phase 2 |
| 4 | `/status` が未認証で最小状態を返す | 半意図的仕様（offline overlay 用）。最小化は reconnect UX に影響 | 仕様判断（計画書 §12） |
