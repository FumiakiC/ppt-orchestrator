# docs/06_log_analysis_context.md — ログ解析コンテキスト（AI 解析用）

対象: PR-G で導入する追記専用ログ / **スキーマ `v1`** / 基底 `ef4a6e5`

> **本書の性格**: これは実装仕様書ではなく、**ログファイルと一緒に AI に渡すための前提資料**である。
> AI が「このイベントは何を意味するのか」「この値は異常なのか」を推測せずに済むことを目的とする。
> ログのスキーマ（フィールド・`ev` の語彙）を変更する PR は、**本書の更新を同 PR に含めること**。

---

## 0. 使い方

1. 解析したい日の `events-yyyyMMdd.jsonl` と、必要なら `access-yyyyMMdd.jsonl` を用意する。
2. **`sid`（セッション ID）で絞る**。1 回の起動 = 1 `sid`。日付跨ぎや複数回起動が混ざらない。
3. 本書と一緒に AI に渡す。質問テンプレートは §10。

---

## 1. システムの 90 秒要約

ppt-orchestrator は、**外部ソフトを導入できない Windows 環境で、PowerPoint をスマホ・タブレットのブラウザから遠隔操作する Web リモコン**。PowerShell 5.1 標準機能のみで動く。想定は会場・会議室でのライブイベントであり、**投影を止めないことが最優先**。

解析にあたって前提として持っておくべき性質:

| 性質 | 内容 | 解析上の含意 |
|---|---|---|
| **HTTP は単一スレッド逐次処理** | `HttpListener` のコンテキストを 1 個ずつ処理する | 1 つの処理が詰まると**全端末が同時に遅くなる**。特定端末だけ遅い場合はサーバ側ではなくネットワーク側を疑う |
| **モードが 2 つある** | 非再生中（Lobby / Dialog）と再生中（NowPlaying）でルーティング表そのものが切り替わる | 同じパスでも応答が違う。`show.start` / `show.end` を境界として読む |
| **認証は日次 6 桁 PIN → Cookie** | PIN はホスト PC の Console に表示。当日中は全端末で同一 token を共有 | 端末の識別は `cid`（クライアント ID）で行う。token では端末を区別できない |
| **throttle は IP 単位 1 秒の固定窓のみ** | lockout や指数バックオフは無い | `auth.fail` が毎秒 1 件のペースで続く = 総当たり攻撃の形。単発の失敗は打ち間違い |
| **操作権（lock）は後付けの「運転席」** | 1 端末だけがスライドを送れる。**無反応 15 秒で自動解放**。`steal`（奪取）は無条件で成功する | `lock.expire` は離席・画面ロックで日常的に出る。`lock.steal` の連続は端末の取り合いを示す |
| **`/stop` は緊急停止（意図的仕様）** | 認証済みなら**どの端末でも**投影を停止できる。lock owner でなくてよい | `show.stop` は「権限違反」ではない。誰が押したかを `cid` / `ip` で追う |
| **COM 例外は 2 種類に分類済み** | HResult で transient（投影継続）と fatal（投影終了とみなす）を判定 | §4 の `com.*` 参照。**transient は正常動作の一部** |
| **平文 HTTP** | TLS は Zero-Dependency と衝突するため採用していない。保護されたネットワーク運用が前提 | 想定外 IP からのアクセスは `access` ログで見る |

---

## 2. ファイル構成

| ファイル | 内容 | 想定行数（3 時間・3 端末） |
|---|---|---|
| `events-yyyyMMdd.jsonl` | **意味イベント**。解析の主対象 | 数百行 |
| `access-yyyyMMdd.jsonl` | HTTP アクセス。非ポーリングは全件、ポーリングは 60 秒集約 | 約 300 行 |

- 配置: 既定は `%ProgramData%\ppt-orchestrator\logs\`。`-StatePath` をカスタム指定した場合はその親フォルダに追随する。
- ACL: 既定パスでは親フォルダが Administrators + SYSTEM に限定（継承遮断）されており、`logs\` はそれを継承する。
- ローテーション: **日次**。自動削除は行わない（事後解析が目的のため、消えている方が困る）。
- 形式: **NDJSON**（1 行 1 JSON オブジェクト）。UTF-8 no-BOM。

---

## 3. 共通スキーマ

```json
{"ts":"2026-07-26T14:03:22.145+09:00","t":193145,"sid":"20260726-140009","seq":412,"lvl":"warn","ev":"com.transient","cid":"a1b2c3","ip":"192.168.1.24","d":{"hr":"0x80010001","op":"slide.next"}}
```

| フィールド | 型 | 意味 | 解析上の注意 |
|---|---|---|---|
| `ts` | string | ISO 8601 + オフセット付きのローカル時刻 | オフセットを含むので TZ を推測しなくてよい |
| `t` | number | **セッション開始からの経過ミリ秒** | 「起動何分後に落ちたか」を引き算せずに読める。時刻計算より先にこちらを使う |
| `sid` | string | セッション ID（起動時刻ベース）。1 起動 = 1 値 | **最初のフィルタは常にこれ** |
| `seq` | number | セッション内の通番（1 から単調増加） | **番号が飛んでいたらログの欠落**。書き込み失敗か強制終了を疑う |
| `lvl` | string | `info` / `warn` / `error` | `warn` は「想定内の異常」を含む（§8 参照）。`warn` の存在自体は障害を意味しない |
| `ev` | string | **固定語彙のイベント名**（`<domain>.<action>`）。§4 が全件 | 自然文ではない。語彙外の値が出たら本書が古い |
| `cid` | string \| null | 操作元クライアント ID。端末単位の識別子 | 端末の同一性判定はこれで行う。IP は NAT・DHCP で変わりうる。**`cid` があるイベントは端末起因、無いイベントはサーバ起因**（例: `lock.release` は端末が離した／`lock.expire` は TTL 超過でサーバが解放した） |
| `ip` | string \| null | 要求元 IP | LAN 内プライベート IP。匿名化していない |
| `d` | object | イベント固有の詳細。§4 に記載 | 数値は数値型で入る（文字列に単位を埋め込まない） |

**状態が変わるイベントは前後の値を持つ**（`{"from":"none","to":"a1b2c3"}`）。差分だけでなく前後があるため、**任意の 1 行だけを見ても文脈が復元できる**。全行を積算する必要はない。

---

## 4. イベント辞書

### 4.1 アプリケーション / ネットワーク

| `ev` | `lvl` | `d` の主なフィールド | 意味と読み方 |
|---|---|---|---|
| `log.meta` | info | `schema`, `host`, `version`, `port`, `slideLogMode` | **各ファイルの先頭 1 行**。スキーマ版とビルド版。これが無いファイルは途中から始まっている |
| `app.start` | info | `admin`, `targetFolder` | 起動。`admin:false` なら URLACL / Firewall 設定が入っていない可能性 |
| `app.stop` | info | `reason` | 記録された終了。`reason` は `normal`（通常終了）/ `not-admin`（管理者権限なし）/ `no-target-folder`（対象フォルダ不存在）/ `ppt-launch-failed`（PowerPoint 起動失敗。直前の `ppt.launch.fail` を見る）。**`app.stop` が無いまま終わっているログは異常終了**（クラッシュ・強制終了・電源断） |
| `net.binding` | info | `url`, `port`, `adapters[]` | 実際に待ち受けた URL と、案内した IP の一覧。「繋がらない」の切り分けはまずここ |
| `net.listener.start` | info | — | 受付開始 |
| `net.listener.stop` | info | — | 受付終了 |
| `net.listener.error` | error | `msg` | listener 自体の異常。ポート競合・URLACL 不足が典型 |

> ログの書き込み失敗はイベントとしては記録されない（書けない状況で書けないため）。
> `seq` は書き込みを試みる前に消費されるので、**失敗は必ず `seq` の穴として現れる**（§3）。
> Console 側には最初の 1 回だけ警告が出る。

### 4.2 認証

| `ev` | `lvl` | `d` | 意味と読み方 |
|---|---|---|---|
| `auth.ok` | info | — | PIN 認証成功。以降その端末は Cookie で通る |
| `auth.fail` | warn | — | PIN 不一致。**単発は打ち間違い**。同一 IP から毎秒 1 件のペースで続くなら総当たり |
| `auth.throttled` | warn | — | 1 秒窓による拒否。連発は自動化されたアクセスの兆候 |

> PIN の値・token・Cookie は**記録されない**（§6）。「入力された PIN が何だったか」は原理的に分からない。

### 4.3 操作権（lock）

| `ev` | `lvl` | `d` | 意味と読み方 |
|---|---|---|---|
| `lock.acquire` | info | `from`, `to` | 空き状態から取得 |
| `lock.steal` | warn | `from`, `to` | **他端末からの奪取**。仕様上は無条件で成功する。連続していれば端末の取り合い |
| `lock.release` | info | `from` | 明示的な解放 |
| `lock.expire` | info | `from`, `idleSec` | 15 秒無反応による自動解放。**離席・画面スリープで日常的に出る（正常）**。`cid` を持たない＝サーバ起因であり、端末が明示的に離した `lock.release` と区別できる |

### 4.4 スライドショー

| `ev` | `lvl` | `d` | 意味と読み方 |
|---|---|---|---|
| `show.start` | info | `deck` | 再生開始。ここから NowPlaying モード。総スライド数はまだ未取得のため持たない（`show.end` の `total` を見る） |
| `show.slide` | info | `cmd`, `from`, `to`, `black`, `white`, `ok` | スライド操作。既定（`change`）では**位置・暗転・白転のいずれかが変化したとき、または操作が失敗（`ok:false`）したときだけ**記録する。位置だけの比較ではないので、位置を変えない暗転操作も残る。ポーリングで読んだ位置は記録しない<br>`-SlideLogMode all` のときは拒否された要求も `rejected:"locked"` / `owner` 付きで記録される（`lvl:warn`）。どちらのモードで動いていたかは先頭の `log.meta` の `slideLogMode` を見る |
| `show.end` | info | `reason`, `pos`, `total` | 再生終了（末尾到達・PowerPoint 側の終了）。`pos`/`total` で「何枚中どこで終わったか」が分かる。<br>**`pos` は Web リモコン経由で最後に観測した位置**であり、端末が一度も接続されなかった回は `0` のまま。`0` は「1枚も進まなかった」ではなく「Web から見えていない」を意味する |
| `show.stop` | info | — | **`/stop` による手動停止**。誰が押したかは `cid` / `ip` |
| `show.error` | error | `deck`, `hr`, `msg` | デッキの open・再生開始・実行中の例外による中断。**`show.start` を伴わずに出た場合はファイルを開けなかった**（壊れた pptx 等）ことを意味する。直後は Lobby に戻る |

### 4.5 COM / PowerPoint

| `ev` | `lvl` | `d` | 意味と読み方 |
|---|---|---|---|
| `com.transient` | warn | `hr` | **一時的な COM 拒否。投影は継続しているとみなす**。`0x80010001`（RPC_E_CALL_REJECTED）と `0x800A175D`（PowerPoint の列挙エラー）が該当。**単発は正常**<br>この判定は再生中ループの毎周（10〜20 回/秒）走るため、**連続する同一 transient は先頭 1 件しか記録されない**。継続時間は次の `com.recovery` の `suppressed` で読む |
| `com.fatal` | error | `hr`, `afterTransient`, `msg` | 上記以外の COM 例外。**投影は終了したとみなして処理が進む**。`afterTransient` が大きければ、突発ではなく**劣化が続いた末の転落**を意味する |
| `com.recovery` | warn | `suppressed` | **transient 連続からの復帰**。`suppressed` は抑制された transient の件数（≒ ループ周回数）。値が大きいほど PowerPoint が長く応答しなかったことを示す。**`com.fatal` の後には出ない**（そちらは復帰ではないため） |
| `ppt.launch` | info | `attempts` | PowerPoint の取得に成功した。`attempts` が 2 以上なら初回が失敗している |
| `ppt.launch.fail` | error | `hr`, `msg` | 起動時の PowerPoint 取得が全試行（3 回 + 任意の stale 掃除後 1 回）失敗。直後に `app.stop`（reason: `ppt-launch-failed`）で終了する |
| `ppt.recover` | warn | `killedStale` | 応答しない既存 PowerPoint を掃除して再取得した（`-KillStalePowerPoint` 指定時のみ発生） |
| `ppt.dead` | warn | `hr`, `msg` | デッキ開始時の生存確認で COM オブジェクトの死亡を検知。直後に再取得を試みる（`ppt.relaunch` / `ppt.relaunch.fail` が対になる） |
| `ppt.relaunch` | info | — | 死亡した COM の再取得に成功。直後の `ppt.guard` で道連れ紐付けの結果を見る |
| `ppt.relaunch.fail` | error | `hr`, `msg` | 再取得に失敗。**再生は始まらず Lobby に戻る**。連続して出る場合は PowerPoint 環境自体の故障 |
| `ppt.guard` | info | `pid`, `bound` | 道連れ終了（JobObject）への紐付け結果。`bound:false` は PID を解決できなかったか、オペレータ自身のインスタンスだったことを示す。**その場合、異常終了時に PowerPoint が残る** |

### 4.6 ファイル移動（finish）

| `ev` | `lvl` | `d` | 意味と読み方 |
|---|---|---|---|
| `file.finish.ok` | info | `dest`, `renamed` | `finish/` への移動成功。`renamed:true` は同名衝突でタイムスタンプを付与したことを示す |
| `file.finish.retry` | warn | `attempt`, `delayMs` | ファイルロック解放待ちの再試行（200 / 400 / 800ms の 3 回。`attempt` は 1 始まり） |
| `file.finish.fail` | error | `msg`, `stage?` | **元ファイルは移動されていない**。既定は 3 回とも失敗。`stage:"resolve"` は移動先名の解決段階で失敗（移動自体は未試行）。`msg:"source-missing"` は再試行中に元ファイルが消えた（他所で移動・削除された）ことを示す |

### 4.7 Web 操作（ui）

| `ev` | `lvl` | `d` | 意味と読み方 |
|---|---|---|---|
| `ui.action` | info | `action`, `file?` | Lobby / Dialog での Web 操作（`start` / `next` / `retry` / `lobby` / `exit` / `select`）。`select` のみ `file` を持つ。**cid は持たない**（Lobby / Dialog のページは cid を送らない）— 操作元は `ip` で追う。**コンソール操作はこのイベントを出さない**: `app.stop` の前に `action:"exit"` が無ければホスト PC のコンソールから終了されたと読める |
| `ui.select.miss` | warn | `name` | 選択されたファイルが開始時点で見つからず**再生されなかった**（一覧表示後に手動で移動・削除された等）。直後は Lobby に戻る。コンソール選択でも発生しうる（その場合、対応する `ui.action` は無い） |

---

## 5. access ログのスキーマ

### 5.1 非ポーリング要求（全件）

```json
{"ts":"...","t":193000,"sid":"...","seq":88,"lvl":"info","ev":"http.req","cid":"a1b2c3","ip":"192.168.1.24","d":{"m":"POST","p":"/slide/next","st":200,"ms":12,"bytes":34,"fields":["cid"]}}
```

| フィールド | 意味 |
|---|---|
| `m` / `p` | メソッド / パス |
| `st` | 応答ステータスコード |
| `ms` | サーバ側の処理時間 |
| `bytes` | 応答本文のバイト数 |
| `fields` | **リクエストボディのキー名のみ**。値は記録しない（§6） |

### 5.2 ポーリングの 60 秒集約

```json
{"ts":"...","t":240000,"sid":"...","seq":91,"lvl":"info","ev":"http.poll.rollup","d":{"win":60,"p":"/status","n":1780,"clients":3,"p50":4,"p95":21,"err":0}}
```

| フィールド | 意味 |
|---|---|
| `win` | 集約窓（秒） |
| `n` | 窓内の件数 |
| `clients` | 窓内に出現した `cid` の異なり数 |
| `p50` / `p95` | 処理時間の中央値 / 95 パーセンタイル |
| `err` | 非 2xx の件数 |

**`n` から接続端末数を検算できる。** ポーリング間隔は `/status` が 300ms（Lobby）と 500ms（Processing）、`/slide/state` が 1200ms（NowPlaying）。
60 秒あたりの理論値は 1 端末につき `/status` 200 件、`/slide/state` 50 件。
`n` が理論値より**大きく下回る**なら、端末が離脱したか通信が不安定。`p95` の悪化は**サーバ側の詰まり**（単一スレッド逐次処理のため全端末に同時に出る）。

---

## 6. 意図的に記録していないもの

**以下は「欠陥」ではなく設計判断である。無いことを異常と解釈しないこと。**

| 記録しないもの | 理由 |
|---|---|
| PIN / token / Cookie の値 | 秘匿情報をログに出さない方針 |
| リクエストボディの**値** | キー名のみ記録。PIN が平文で残る経路を構造的に無くすため |
| レスポンス本文 | ステータスと本文バイト数のみ。HTML 全文は巨大かつ無意味 |
| **COM 呼び出し単位の記録** | 再生中は毎周スライド位置を読むため、記録すると信号がノイズに埋もれる。**例外・状態遷移・復旧のみ**を残す |
| ポーリングの個別行 | 3 時間で 5 万行規模になるため 60 秒集約に置換（§5.2） |
| listener コンテキスト取得の単発失敗 | クライアント切断や listener 停止時の読み取り失敗は記録しない。単発は無害で、持続時は取得ループが最悪数百回/秒で回るため、抑制なしには events の行数前提を壊す。listener レベルの障害は `net.listener.error` と access ログ（`http.poll.rollup` の `err` / `p95`）で観測する |

---

## 7. 正常なセッションの見え方

```
log.meta → app.start → ppt.launch → ppt.guard → net.listener.start → net.binding
  → auth.ok（端末ごと）
  → ui.action（start / select。Web 操作の場合のみ）
  → show.start → show.slide × N（送るたび）
  → lock.acquire / lock.expire（運転席の移動）
  → show.end → ui.action（next / retry / lobby）→ file.finish.ok
  → （次のデッキで show.start …）
  → net.listener.stop → app.stop
```

この骨格から外れている箇所が調査対象になる。特に **`app.stop` で終わっていないログは異常終了**。

---

## 8. 「正常な異常」— 障害と読み間違えやすいもの

| 現象 | 実際の意味 |
|---|---|
| `com.transient` → `com.recovery` が `suppressed` 数件で閉じる | **正常**。PowerPoint がビジーのときの一時拒否で、投影は続いている |
| `com.transient` に対応する `com.recovery` が無い | 復帰しないまま再生が終わっている。直後の `com.fatal` / `show.end` を見る |
| `lock.expire` が繰り返し出る | **正常**。離席・画面スリープで 15 秒 TTL に掛かっているだけ |
| `access` の `err` が一時的に増え、`events` は無風 | **クライアント側の通信断**（会場 Wi-Fi の瞬断）。サーバは正常。ブラウザ側は offline overlay を出して自動復帰する |
| `auth.fail` が 1〜2 件 | **正常**。PIN の打ち間違い |
| `lock.steal` が出る | **正常**。登壇者交代の通常操作。仕様上 steal は無条件で成功する |
| 日付が変わる時刻でファイルが途切れ、`app.stop` が無い | 日跨ぎローテーションの失敗の可能性。アプリ自体は稼働を続けている場合がある。Console 側の警告（`Logging disabled after write failure`）の有無で切り分ける |

---

## 9. 障害シナリオ別・最初に見る場所

| 症状 | 最初に見る | 判断 |
|---|---|---|
| スマホから繋がらない | `net.binding` / `net.listener.error` | 待ち受け URL と案内 IP の一致、ポート競合、`app.start` の `admin` |
| 選んだのに再生が始まらない | `show.error` / `ui.select.miss` / `ppt.dead`→`ppt.relaunch.fail` | `show.error` はファイルが開けない（壊れた pptx 等）。`ui.select.miss` は選択時点でファイルが無い。`ppt.relaunch.fail` は PowerPoint 自体の故障 |
| 投影が勝手に止まった | `show.stop` / `show.end` / `com.fatal` | `show.stop` があれば誰かが `/stop` を押した（`cid` / `ip` で特定）。無ければ COM 側 |
| 操作できない端末がある | `lock.*` の `from` / `to` | 運転席が他端末にある。`lock.expire` を待つか steal したかを追う |
| 全端末が同時にもたつく | `http.poll.rollup` の `p95` | サーバ側の詰まり。単一スレッド逐次処理のため全端末に同時に出る |
| 特定端末だけ遅い | 同上（`p95` は正常のはず） | ネットワーク側。サーバは無関係 |
| ファイルが `finish/` に移動していない | `file.finish.fail` / `.retry` | ロック解放待ちの 3 回再試行に失敗。元ファイルは残っている |
| ログが途中で切れている | `seq` の飛び / 最終行が `app.stop` か | 穴があれば書き込み失敗、`app.stop` が無ければ異常終了かローテーション失敗 |

---

## 10. AI への質問テンプレート

```
添付は ppt-orchestrator のイベントログ（NDJSON）と、その読み方をまとめた docs/06 です。
sid=<セッションID> に絞って、以下を答えてください。
1. このセッションで異常と判断すべき事象を、時系列（t の昇順）で列挙してください。
2. §8「正常な異常」に該当するものは除外し、除外した理由も示してください。
3. 投影が停止した原因を、根拠となる行（seq）を挙げて説明してください。
推測を述べる場合は、根拠のある記述と明確に区別してください。
```

```
2 つのセッション（sid=A と sid=B）を比較し、B でのみ発生している事象を挙げてください。
イベントの出現順序の違いにも注目してください。
```

---

## 11. 本書の更新義務

- `ev` の語彙を追加・変更する PR は、**§4 の辞書を同 PR で更新**する。
- スキーマ（共通フィールド）を変更する PR は、`log.meta` の `schema` 版を上げ、**§3 を同 PR で更新**する。
- 記録しない方針（§6）を変える場合は、`docs/03_refactoring_plan.md` に仕様判断として記録してから変更する。
