# 03 — UI/UX デザイン仕様書（ppt-orchestrator リデザイン "Quiet Signal"）

本書はリデザインの**完全仕様**です。最終的な見た目・挙動の正解は
`reference/mockup/`（実際に動くモックアップ）です。数値に迷ったらモックアップの
`assets/style.css` / `assets/views.js` を参照してください。

---

## 1. コンセプト "Quiet Signal"

発表中の**暗転した会場**で、オペレータの視線は舞台にある。
リモコンは普段は静か（Quiet）に控え、**状態の変化だけが信号（Signal）として光る**。

設計原則:

1. **状態色の一貫性** — 色は装飾ではなく信号。Green=開始・安全 / Amber=注意・待機 / Red=破壊・ライブ / Blue=情報・選択
2. **誤操作の構造的防止** — 重要操作は全て長押し。ボタンは大きく、押下フィードバックは即座に
3. **レイアウト不変性** — 状態変化でボタンの位置が動かない（例: ロック切替でメッセージが出ても高さ固定）
4. **操作の非遮蔽** — 通知（SLOW 接続など）は操作面を覆わない。トップバーのピルに集約
5. **単一コードベースのレスポンシブ** — マークアップは1つ。コンテナクエリで電話=1カラム、タブレット/PC=2ペイン

---

## 2. デザイントークン

スコープ: アプリ画面のルート要素（モックアップでは `.screen, .dev-screen, .tkscope`）に定義。
本番ではリモコン UI のルートコンテナに同様に定義する。

### 2.1 カラー

| トークン | 値 | 用途 |
|---|---|---|
| `--s-bg` | `#0A0C10` | アプリ背景（ほぼ黒の深い紺） |
| `--s-ink` | `#F4F6F9` | 主テキスト |
| `--s-ink2` | `#A7AFBB` | 副テキスト |
| `--s-ink3` | `#5F6875` | ラベル・ヒント・非強調 |
| `--s-card` | `rgba(255,255,255,.042)` | カード背景 |
| `--s-card2` | `rgba(255,255,255,.065)` | カード背景（強） |
| `--s-brd` | `rgba(255,255,255,.075)` | ヘアライン枠 |
| `--s-brd2` | `rgba(255,255,255,.13)` | 枠（強） |
| `--s-green` | `#3DDC97` | Signal Green — 開始・安全・完了 |
| `--s-red` | `#FB4D57` | Signal Red — 破壊的操作・ON AIR・オフライン |
| `--s-amber` | `#FFB224` | Standby Amber — 待機・注意・SLOW |
| `--s-blue` | `#6EA8FF` | Info Blue — ロック・選択状態・進捗バー |

信号色のボタン表現ルール（**全ボタン共通のゴーストスタイル**）:

- 背景: 役割色の 6–8% 透過（例: `rgba(61,220,151,.08)`）
- 枠線: 役割色の 30–42% 透過（例: `rgba(61,220,151,.42)`）
- 文字: 役割色（Red 系ボタンの文字は `#FF848C` のような明るめ派生色も可）
- ベタ塗り（実色背景）は**使わない**。視覚的強調は「色の役割」で行う

### 2.2 形状・モーション

- 角丸: `--s-r: 18px`（大ボタン・カード）、`--s-r-sm: 13px`（小要素）
- イージング: `--s-ease: cubic-bezier(.22,.9,.32,1)`
- 押下: `transform: scale(.94–.98)`＋背景の僅かな濃化
- 画面遷移: `.s-view` に `sIn .35s var(--s-ease)`（フェード＋微移動）

### 2.3 タイポグラフィ

- UI フォント: **Inter**（system-ui フォールバック）
- 数字・ラベル: **JetBrains Mono**（`--s-mono`）— タイマー・位置・カウント・キーヒント
- タイマー: `font-weight:300`、`font-variant-numeric:tabular-nums`、スマホ 56px / 広幅 82px
- ラベル系: mono・10px 前後・`letter-spacing: 1.6–3px`・大文字

### 2.4 状態ごとの環境グロー

`.s-view::before` に画面状態別のごく薄い放射グラデーション（上端中央）:

- `data-st="auth"/standby` 系: Blue または Amber 系
- `data-st="live"`（NowPlaying）: Red 系
- `data-st="done"`（Ended/Exit）: Green 系

---

## 3. 共通コンポーネント

### 3.1 トップバー（`.s-top`）

- 左: ブランド（▶マーク＋`PPT ORCHESTRATOR`、mono・10px・letter-spacing 2.4px・ink2）
- 右: **接続ピル `.s-conn`**（下記）
- 実機フルスクリーン時の上パディング: `max(22px, env(safe-area-inset-top) + 16px)`

### 3.2 接続ピル（`.s-conn`）

信号バー4本アイコン＋状態テキストのピル。**接続状態の唯一の表示場所**（下部ポップアップは廃止）。

| 状態 | クラス | 表現 |
|---|---|---|
| LIVE | `.c-live` | Green 系。バー4本とも実線 |
| SLOW | `.c-slow` | Amber 系。**ピル全体が 1.8s 周期で脈動**（`slowPulse`）。最上位バーだけ 25% 透過 |
| OFFLINE | `.c-off` | Red 系。先頭バー以外 22% 透過。併せて**オフラインオーバーレイ**を全画面表示 |

### 3.3 オフラインオーバーレイ（`.s-off`）

- 全画面（`inset:0`）、`rgba(8,9,13,.74)`＋`backdrop-filter: blur(10px)`、フェード .3s
- 内容: パルスする Red の接続断アイコン、「Connection lost」、「Reconnecting to host PC …」（ドットアニメ）、
  下部注記「✓ The show keeps running on the host PC.」（上演は継続することを必ず伝える）

### 3.4 長押し確定（`.holdable` + `.hfill`）

- 対象: デッキ開始、GO、終了、ロック奪取、Exit、Replay など**全ての重要/破壊的操作**
- 実装: ボタン内に絶対配置の `.hfill`（`scaleX(0)→1`、線形、所要時間＝`data-hold` ms）。
  `pointerdown` で開始、`pointerup/cancel/leave` で取消（フィルを .18s で巻き戻す）。
  完了時にのみアクション発火
- `.holdable` は `isolation:isolate` でフィルをボタン内に閉じ込める
- **所要時間は製品値: 1500ms（デッキ開始・GO・停止・奪取・Replay・戻る）、2000ms（Exit 系）**
  （原版 `hold.js` の既定・各テンプレートの `data-hold` と同一。モックアップもこの値で動作）
- 原版の挙動も踏襲すること: 420ms 未満の解放で長押しヒントをトースト表示、
  開始・完了時に `navigator.vibrate` で触覚フィードバック

### 3.5 ボタン族（代表寸法）

| クラス | 用途 | 高さ | 備考 |
|---|---|---|---|
| `.go` | GO（次デッキ開始） | 62px | Green ゴースト。`HOLD` キックラベル＋デッキ名（省略記号処理） |
| `.pwr` | 電源/Exit | 62px 角 | Red ゴースト、電源 SVG |
| `.nav` | スライド送り/戻し | 86px（広幅 106px） | 大きな矢印。非ゴースト（`--s-card` 系グラデ） |
| `.mini` | First/Last/Black/White | 48px | 4列グリッド。アクティブ時は Blue 発光（`.act`） |
| `.stopb` | Hold to Stop | 62px | Red ゴースト（`.go` と同じ高さ・スマホでは同じ下端位置） |
| `.steal` | Hold to take control | 38px 程度 | Amber ゴースト（ロックメッセージ行内） |
| `.e-btn` | 終了後アクション | 54px | `.primary`(Green) / `.warn`(Amber) / `.sub`(neutral) / `.exit`(Red) |
| `.a-key` | PIN キー | 62px 円形 | 数字のみ（電話式サブ文字は付けない） |
| `.a-unlock` | Unlock Remote | 52px | Amber グラデ（**唯一の実色ボタン**=認証の特異点）。未6桁時 `opacity:.35` + `pointer-events:none` |

### 3.6 ロックスイッチ（`.sw`）とロック状態モデル

- 52×31px のピルスイッチ。ON で Blue 発光、ノブ右移動
- **ロックは3状態**（原版 API の `lock`/`mine` に対応）:
  - `mine`（自分が保持）: スイッチ ON、パッド武装。メッセージは控えめに「You hold the lock」
  - `none`（誰も未保持＝**デッキ開始直後の初期状態**）: スイッチ OFF、パッド無効。
    Amber の誘導文「Tap the switch above to take control.」→ スイッチで `/lock/on` 取得
  - `other`（他端末が保持）: スイッチ OFF（ON にできない）、パッド無効。
    「Another device holds the lock.」＋ `.steal` ボタン（Hold to take control → `/lock/steal`）
- 下の**メッセージ領域 `.lockmsg` は高さ 46px 固定**（`flex:0 0 auto`）—
  **どの状態でも高さが変わらない＝パッドが動かない**ことが重要
- ロック未保持時: `.pad.off`/`.pad2.off` でパッドを `opacity:.3; pointer-events:none`
- **デッキ開始のたびにロックは解放される**（原版の安全リセットと同じ）

### 3.7 マーキー（`.js-name` / `.nn-track` / `.nn-seg`）

原版 `remote.js` と**同一仕様**（維持項目）:

- 速度 45px/s、開始遅延 900ms、移動時間 = max(4s, 幅/45px)、終端で 3s 停止
- セグメント複製（末尾ギャップ `padding-right:2.4em`）、Web Animations API
- `prefers-reduced-motion: reduce` 時は**発動しない**（通常の ellipsis 表示）
- コンテナ幅評価で発動（`scrollWidth > clientWidth + 1` の時のみ）。リサイズ後の再評価も行う

---

## 4. 画面別仕様

全画面 `.s-view`（`position:absolute; inset:0` の縦 flex）。各画面の DOM 構造は
`reference/mockup/assets/views.js` の対応関数を参照。

### 4.1 Auth（`viewAuth` / `.v-auth`）

- 構成: シールドタイル → タイトル「Enter PIN」→ サブ「The 6-digit PIN is shown on the host PC console.」
  → 6桁スロット → エラー行（`.a-err`）→ テンキー `.a-pad` → `.a-unlock` → フッタ注記
- スロット `.a-slot`: 6個、**フレックス可変**（`flex:1 1 0; max-width:42px`、容器 max-width 264px）で狭幅でも溢れない。
  入力済み `.full`、現在位置 `.cur`
- テンキー: 3列グリッド、最終行は [ghost][0][⌫]。キーは円形
- **6桁入力で自動送信**（原版と同じ）。原版はさらにキーボード数字/Backspace/Enter・貼り付けにも対応（踏襲すること）
- 認証結果:
  - 一致 → Lobby へ
  - 不一致 → リデザインでは**同一画面でインラインエラー**（`.a-slots.shake`＋`.a-err` 表示、入力クリアして再入力待ち）。
    ※ 原版は `%%AUTH_ERROR%%='error'` の別ページ（auth-error.html）へ遷移する方式。
    サーバ契約（form POST `/auth`）を変えずにインライン化するか、別URL方式を維持するかは実装時に判断
- **実装上の注意（参照モックで修正済みの不具合）**: PIN 1桁ごとの入力はスロット／Unlock の
  **部分 DOM 更新**にとどめ、ビュー全体の再描画を避けること。全体再描画だと画面遷移アニメーション
  （sIn: 10px 浮き上がり）がキー入力のたびに再生され、画面が上下にガクつく。
  同様に、画面遷移アニメーションは**画面が実際に切り替わった時だけ**再生する
  （ロック切替やブラックアウト等の同一画面内更新では再生しない）
- **デモ PIN は `123456` 固定**（モックアップ・デモシム共通）
- **広幅（≥700px / タブレット）**: 2カラムグリッド（情報列 + テンキー列、gap 80px、パッド幅 284px）。
  キーは `aspect-ratio:1/1` の**真円（約87px）**、スロット 60px／タイル 72px／タイトル 26px にスケールアップ
  （スマホは従来のコンパクト仕様のまま）
- **PC（≥1100px）**: **Now Playing と同じ 2カラムステージ**（max-width 1140px、1.25:1 カラム比、
  中央に縦ディバイダ、コンテンツ上下中央）。キーは `aspect-ratio:1/1` の**真円**（約98px）、
  タイル 80px／タイトル 36px／スロット 72px／Unlock 64px に拡大（§5.5）
- 高さ不足時は `overflow-y:auto`＋`justify-content:safe center`（内容が潰れずスクロール）

### 4.2 Lobby（`viewLobby` / `.v-lobby`）

- トップバー → ヘッダ（「Lobby」＋右に `n STANDBY / n DONE` の mono カウント）
  → **UP NEXT カード（固定・スクロールしない）** → スクロール領域（Queue セクション → Completed セクション）
  → 下部ドック `.s-dock`（`.go`＋`.pwr`）
- **UP NEXT カード `.l-next-card`**: 次デッキを長押し開始できる強調カード（Amber ラベル「UP NEXT — HOLD TO START」）。
  **常時表示のためスクロール領域の外に固定**（リストをスクロールしても動かない）
- デッキ行 `.deck`: 番号（mono 2桁）＋ファイル名（1行省略）＋`n SLIDES`＋›。長押しで開始
- 完了行 `.deck.fin`: ✓＋ファイル名（非操作）
- **広幅（≥700px）**: キュー／完了とも **3列グリッド**（`repeat(3,minmax(0,1fr))`）、全要素 max-width 880px で中央揃え、
  左右ガター 32px、ドックは max-width 944px。**≥1100px** ではリスト 1020px／ドック・UP NEXT 1084px に拡幅
  （カード約333pxでデッキ名の省略が減る。Now Playing の `np-main` 1140px とスケール感を揃える）
- **広幅のブロック高さは固定**（§5.5 参照）: デッキ数が少なくても高さ・幅は変わらず、空白として表示される
- 全完了時: GO を disabled（`grayscale(.7); opacity:.5`）、キューに「All decks completed.」

### 4.3 Now Playing（`viewPlaying` / `.v-play`）

- モニタ部 `.np-monitor`: ON AIR ピル（Red 点滅）→ デッキ名（**マーキー対象**）→
  「REMOTE SLIDE CONTROL」→ タイマー `.js-timer` → 位置行（`n / total`＋Blue 進捗バー `.js-bar`）
  → **プロジェクタタイル `.np-proj`**（投影面の現在状態: スライド番号 / BLACK / WHITE＋状態文 `.js-pvtx`）。
  **カードは全状態で同一幅に固定**（`min-width: min(222px,100%)`、タブレット 258px、デスクトップ 266px、
  `justify-content:center`）— ブラックアウト/ホワイトアウト切替に加え、
  **3桁ページ（例: Slide 123 of 150 / 999 of 999）でも幅が変わらない**ことを保証する（§1「レイアウト不変性」）
- 操作部 `.np-controls`: ロック行 → 固定高メッセージ → `.pad`（◀ ▶）→ `.pad2`（First/Last/Black/White）→ `.stopb`
- **スマホの `.np-controls` は下端アンカー**（`justify-content:flex-end`、padding 16px **20px 26px**）:
  **Hold to Stop が Lobby ドックの Hold to Start と完全に同じ位置・同じサイズ（62px）に来る**
  （遷移時にボタンが上下にズレない）。タブレット/PC は各ペイン内で上下中央（従来通り）
- ブラックアウト/ホワイトアウト: `.mini.act` で Blue 発光＋プロジェクタタイルが `.pv.blk`/`.pv.wht` に
- 最下部 `.s-keys`（**広幅のみ表示**）: `SPACE / → NEXT` `← PREV` `B BLACKOUT` `W WHITEOUT` のキーヒント
- **広幅（≥700px）**: `.np-main` が横並び（モニタ flex 1.25＋右境界線 / 操作 flex 1）、
  各ペイン `min-width:0`（長いタイトルで潰れない）、タイマー 82px、`.np-divider` 非表示、
  **`np-main` max-width 880px**（ロビーのリスト幅と同一）
- **超広幅（≥1100px）**: `.np-main` を max-width 1140px でセンタリング

### 4.4 Processing（`viewProcessing` / `.v-proc`）

- スピナー `.prc-ring`（46px、3px、Amber トップカラー、1s 回転）
- 「Processing…」＋「The screen will refresh automatically.」＋切替対象ファイル名（`.prc-file`、任意）
- **表示時間は 1600ms**（製品のサーバ側 status 遷移に相当。デモシムの `PROCESSING_MS` と同値）

### 4.5 Ended（`viewEnded` / `.v-end`、原版 Dialog.html 相当）

- **到達経路**: ホスト側でのプレゼン終了（製品ではポーリングのステータス遷移、
  モック/デモシムでは「End show → Dialog」イベント）。**Stop ボタンでは到这里来ない**
  （Stop → Processing → Lobby。§「画面遷移」参照）
- 終了デッキは **pending（未確定）** 扱い: Start Next / Back to Lobby / Exit System で DONE 確定、
  Replay では破棄（DONE にせず同じデッキを再開始）
- Green チェックマーク `.e-mark` → 「Presentation complete」→ 終了ファイル名
- アクションスタック `.e-stack`（広幅時 max-width 430px）:
  - 次デッキあり: UP NEXT カード `.e-next`＋`.e-btn.primary`「Start Next Deck」（hold 1500ms）
  - 次デッキ無し: disabled ボタン「No slides in queue」（原版と同文言）
  - `.e-btn.warn`「Replay This Deck」（1500ms）/ `.e-btn.sub`「Back to Lobby」（1500ms）/
    `.e-btn.exit`「Exit System」（**2000ms**）
- 注記「Destructive actions require a long press.」

### 4.6 Exit（`viewExit` / `.v-exit`）

- Green チェック → 「System Shutdown」→「You can safely close this tab or window.」
- 「Shutting down safely …」（ドットアニメ `.dots`）

---

## 5. 画面遷移・状態機械（正本 demo-shim.js 準拠）

```
Auth ─PIN 一致─▶ Lobby ─hold deck / GO─▶ Processing ─1600ms─▶ NowPlaying
Auth ─PIN 不一致─▶ エラー表示（インライン or auth-error）
NowPlaying ─hold Stop─▶ Processing ─1600ms─▶ Lobby      …停止デッキは即 DONE 確定
NowPlaying ─ホスト側終了─▶ Ended(Dialog)                   …終了デッキは pending
Ended ─Start Next─▶ Processing ─▶ NowPlaying             …pending を DONE 確定
Ended ─Replay─▶ Processing ─▶ NowPlaying                 …pending 破棄（DONE にしない）
Ended ─Back to Lobby / Exit─▶ Lobby / Exit               …pending を DONE 確定
```

- デッキ開始時: pos=1、black/white 解除、経過 0、**ロック解放（none）**
- 直リンク時シナリオ（NowPlaying を直接開いた場合）: `00_Venue_Guide.pptx` 発表中・9/24・07:12・ロック未保持
- サンプルデッキ（原版 shim）: queue = `01_Opening_Keynote / 02_Product_Roadmap_2026 / 03_Engineering_Deep-Dive`、
  done = `00_Venue_Guide`。全 24 スライド
- **モックのデフォルトは 15 デッキ**（Queue 12 ＋ Completed 3 ＝ 広幅ロビーの 3列×5行グリッドを埋める密度。
  原版 5 本に、マーキーデモ用長名 1 本 `04_Product_Strategy_2026_Executive_Briefing` と
  追加 queue 8 本・追加 done 2 本（`00_Sponsor_Loop` / `00_Press_Briefing`）を拡張）

## 5.5 レスポンシブ仕様（コンテナクエリ）

- リモコン UI のルートに `container-type: size` を指定。**メディアクエリではなくコンテナクエリ**で分岐
  （`size` 型にすることで高さのコンテナクエリと `cqh` 単位が使え、
  ギャラリーの縮小フレーム内でも実機と同一のレイアウト分岐・寸法が再現される）
- 閾値は **700px**（`<700px` = 1カラム電話レイアウト / `≥700px` = 2ペイン・2列グリッド）
- **Lobby（タブレット・PC 共通 = ≥700px）**: **タイトル＋UP NEXT（固定）＋3列リスト＋GO/Exit ドックの
  ブロック全体を1グループとして上下中央配置**（`justify-content:center`。原版 UI の中央カードと同じ構成）。
  **ブロック高さは `height: min(580px, calc(100cqh - 250px))` で固定** ——
  デフォルト 15 デッキ（3列×5行）がちょうど収まる 580px を上限とし、
  デッキ数が少ない場合でも高さ・幅を変えず空白表示（レイアウト不変）。
  画面が低い場合は `100cqh - 250px` 側が効き、内部スクロール＋トップバーとのクリアランスを自動確保。
  他画面との高さバランス: Now Playing がフルハイトのペイン内でコンテンツを上下中央に置くのに対し、
  Lobby は画面高の約6〜8割を占める中央ブロック —— どちらも「画面中央に主コンテンツ」のリズムで統一。
  スマホ（<700px）は従来通り下部固定ドック（親指リーチ優先）。UP NEXT 固定はスマホでも同様
- 補助閾値 **1100px** = デスクトップ強化（**PC は Auth / Lobby / NowPlaying で同一ステージ**を共有:
  幅 1140px（Lobby はリスト 1020px／ドック 1084px）、高さは Now Playing の `np-main` ステージ
  ≒ `100cqh - 194px` + ドック分。画面遷移してもコンテンツの外接枠が動かない統一感）
  - **Lobby**: ブロック高さを `calc(100cqh - 194px)` に引き上げ（Now Playing のステージ 61→1035px/1080p と同一。
    余分な高さは固定高さルール通りスクロール領域内の空白となる）。リスト max-width 1020px／UP NEXT・ドック 1084px
  - **Auth**: Now Playing と同じ 1140px 2カラムステージに全面刷新（§4.1 参照）
  - **NowPlaying**: 表示スケールを一段拡大（タイマー 96px、ナビ 118px など）。`np-main` は max-width 1140px
  - ※ タブレット（700〜1099px）の NowPlaying は `np-main` max-width **880px**（ロビーのリスト幅と同一）
- hover 可能環境の hover スタイルは `@media (hover:hover)` 内に限定
- 実機フルスクリーン対応: `100dvh` 使用、`env(safe-area-inset-*)` でノッチ/ホームバー回避、
  `user-select:none`、`touch-action:manipulation`

**Screen Gallery（概要ページ）の基準サイズ**: スマホは独自フレーム（374×780、変更なし）、
タブレットは **iPad Pro 12.9″（1024×1366）**、PCは **24″ Full HD（1920×1080）** の
実サイズ描画をスケール表示。コンテナクエリ駆動なので、各基準サイズでの実レイアウトがそのまま確認できる。

## 6. キーボード操作（既存機能の可視化 — 2026-07-29 訂正）

**現行製品の `remote.js`（31–37 行目）にキーボードハンドラは既に存在する**（旧記述「現行製品には存在しない」は誤り）。
リデザインでは、この既存機能を `.s-keys` ヒントバー（広幅のみ表示）で**可視化**する。
現行ハンドラは **ロック保持（armed）中のみ有効**で、キー割当は以下の通り:

| キー | 動作 |
|---|---|
| `→` / `PageDown` | 次スライド |
| `←` / `PageUp` | 前スライド |
| `Home` / `End` | 先頭 / 末尾スライド |
| `B` | ブラックアウト トグル |
| `W` | ホワイトアウト トグル |
| `Space` | 常に抑止（誤操作防止） |

実装は **remote.js のハンドラをそのまま継承**し、ヒントバーの表示要素を追加するだけでよい
（割当を変更する場合のみ、ヒントバー表示とハンドラを同時に更新すること）。

## 6.5 接続状態の検出・表示（原版準拠の数値）

- SLOW 判定: `/status` ポーリングの往復が **600ms 超**（polling.js）
- オフライン overlay: 応答 **3000ms 無し**、または fetch 失敗で表示。
  失敗時は指数バックオフ（間隔 ×1.5、最大 5000ms）で再試行。表示中は操作を抑止
- リデザインでは表示場所だけを変更（下部ポップアップ → トップバーのピル脈動）。
  **検出ロジックは製品 polling.js をそのまま使う**（デモシムが実経路で動かす前提のため）

## 7. アクセシビリティ

- `prefers-reduced-motion`: マーキー停止＋UI アニメーション抑制
- スイッチに `role="switch" aria-checked`、ナビボタンに `aria-label`
- 状態は色＋テキスト/アイコンの二重符号化（色覚多様性対応）
- タップターゲットは最小 44px 超（主要操作 48–106px）

---

## 8. 参照実装の読み方

| ファイル | 内容 | 本番への対応 |
|---|---|---|
| `reference/mockup/assets/style.css` | 全スタイル。「IN-SCREEN UI」セクション以降がリモコン本体。末尾に実機フルスクリーン＋DEMO パネル用スタイル | トークン＋コンポーネントを本番 CSS に移植 |
| `reference/mockup/assets/views.js` | 6画面の DOM を生成する関数群（`viewAuth`…`viewExit`）＋`applyMarquee()` | **各 `views/*.html` テンプレートの構造設計図**として読む。クラス名・入れ子・文言を踏襲 |
| `reference/mockup/assets/stage.js` | モックの状態管理・長押し・キーボード・DEMO パネル。**状態機械は正本 `build/mockup/demo-shim.js` 準拠**（PIN 123456・Processing 1600ms・Stop→Processing→Lobby・開始時ロック解放・Dialog pending 確定ルール） | 画面遷移・ロックの意味論の参照実装。長押し（`wireContainer`）・キーボードガードの実装参考。通信層は本番のものを使う |
| `reference/mockup/assets/gallery.js` | 概要ページの静的ギャラリー | 本番移植は不要（資料用） |

### スクリーンショット（`reference/screenshots/`）

`00_demo_panel`（Auth でパネル展開＝Demo PIN 表示）、`01_auth`〜`06_exit`（電話 390px 各画面。
`03_nowplaying` は直リンクシナリオ＝00_Venue_Guide 9/24・ロック未保持の初期状態）、
`07_marquee`（長名デッキのスクロール＋ロック保持で武装）、`08_offline`（オフラインオーバーレイ）、
`09_nowplaying_tablet`（タブレット 2ペイン＝ロビーと同じ 880px 幅）、`10_nowplaying_desktop`（1440px 拡大スケール）、
`11_lobby_desktop`（PC ロビー＝UP NEXT 固定、15デッキ 3列×5行、ブロック高さは Now Playing のステージと同一）、
`12_auth_desktop`（PC Auth＝Now Playing と同じ 1140px 2カラムステージ、円形キー）
