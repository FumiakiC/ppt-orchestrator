# docs/05_windows_smoke_checklist.md — Windows 実機スモーク手順

CI（ubuntu / pwsh）は **build / Parser 検証 / 残骸ガード / tests** しか回せない。
**COM / HttpListener / Console / `.bat` / Firewall / URLACL の実挙動は Windows 実機でしか検証できない。**
これが CI の恒常的な穴であり、本書は **CI green とは独立したマージゲート**である。

## 1. スモークが必須になる PR（該当判定）

以下のいずれかに触れる PR は、CI green に加えて本書のスモーク実施が**マージ条件**。

- PowerPoint COM 呼び出し（`src/com-handler.ps1`、`Watch-RunningPresentation`、スライドショー起動・復旧）
- `System.Net.HttpListener`（`src/server.ps1`、`Get-SafeContextAsync`、listener 起動/停止）
- Console UI / Win32 P/Invoke（`src/ui-console.ps1`、`src/config.ps1` の `Add-Type`、JobObject）
- `Start-Presenter.bat`（UAC 昇格 / URLACL / Firewall / cleanup）
- `finish/` へのファイル移動
- ポート・ネットワーク設定（`WebPort`、`ALLOWED_REMOTE`）

該当しない PR（docs のみ・純粋関数のみ・テストのみ）は **不要**。PR 本文に「不要（理由）」と明記する。

## 2. 環境

- Parallels の Windows VM（Windows PowerShell **5.1** / Microsoft PowerPoint インストール済み）
- ホスト Mac、またはスマートフォン 2 台（操作権の奪取・排他を確認するため **2 クライアント必要**）
- VM と操作端末が同一ネットワークにいること

## 3. 準備

```powershell
# 1) 対象ブランチを VM に取得し、dist を生成
git switch <branch>
powershell -NoProfile -File .\build\build.ps1 -Version dev
# 代替（PowerShell 7）
# pwsh -NoProfile -File .\build\build.ps1 -Version dev
```

> 根拠（実コード確認済み）:
> - `build/build.ps1` は `[System.IO.File]::WriteAllText(..., New-Object System.Text.UTF8Encoding($true))` で BOM 付き UTF-8 を固定出力しているため、5.1 / PS7 のどちらでビルドしても dist の BOM 差分は発生しない。
> - `build/build.ps1` は `#Requires` を持たず、確認範囲に PS7 専用構文はないため 5.1 で動作する。
> - ただしスモークの主目的は本番ランタイム（Windows PowerShell 5.1）での挙動確認なので、既定コマンドは `powershell` とする。

`finish/` を空にする。項目 12（同名 collision）を検証する回に限り、テスト用 `.pptx` のうち 1 枚と同名のファイルを `finish/` 側にも置いておく。

## 4. チェックリスト（計画書 §10 と 1:1 対応）

PR 本文にはこの表から**該当項目だけ**を抜き出して貼り、結果を記録する。

| # | 項目 | 期待結果 | 結果 |
|---|---|---|---|
| 1 | `Start-Presenter.bat` ダブルクリック | UAC 昇格ダイアログが出る | ☐ |
| 2 | 起動直後 | URLACL と Firewall rule が追加される（`netsh http show urlacl` / `netsh advfirewall firewall show rule`）。Console に `[URLACL] User: <登録ユーザー>` が表示される（PR-B / #32）。ドメイン参加機では UPN 形式（`user@domain`）、非ドメイン機では fallback（`PC名\user`）となるため、**どちらを表示したかを記録する** | ☐ |
| 3 | Console 表示 | PIN と Web URL が表示される | ☐ |
| 4 | スマホから `http://<host>:8090/` | ページに到達する | ☐ |
| 5 | PIN 認証 | 成功・失敗・再入力が期待どおり（失敗連打で throttle される） | ☐ |
| 6 | Lobby | pending deck を開始できる | ☐ |
| 7 | 開始後 | PowerPoint が全画面スライドショーで開く | ☐ |
| 8 | NowPlaying（2 端末） | lock on / off / steal が機能する。非 owner 端末の `/slide/*` 操作はサーバ側で拒否される。⚠ `/stop` は owner チェックがなく、認証済みなら任意端末が停止できる（PR-E） | ☐ |
| 9 | 操作 | next / prev / first / last / blackout / whiteout が機能する | ☐ |
| 10 | 最終スライド | next が抑止される（`atEnd`） | ☐ |
| 11 | 復帰経路 | `/stop` / スライドショー終了 / PowerPoint 手動 close の**各 path**で Dialog または Lobby に戻る | ☐ |
| 12 | finish 移動 | 正しく移動する。⚠ 現状は `finish/` 同名 collision 時に `Move-Item -Force` で上書きされ、既存ファイルは失われる（PR-F 対象）。PR-F 完了までは上書きが現状仕様。PR-F マージ後に期待値を「既存ファイルを消さない」へ更新する | ☐ |
| 13 | file lock | ファイルが開かれている状態での retry が期待どおり | ☐ |
| 14 | PC Console | Start / Select / Page / Update Network / Retry / Lobby / Exit が動く | ☐ |
| 15 | 瞬断耐性 | スマホの Wi-Fi を一時 OFF → **投影は止まらず**、復帰後に offline overlay が消える | ☐ |
| 16 | 終了時 cleanup | PowerPoint / listener / URLACL / Firewall rule がすべて片付く | ☐ |
| 17 | 巻き込み防止 | **事前に手動で開いておいた別の PowerPoint を kill しない**（JobObject の道連れ kill が自分の起動分のみ） | ☐ |
| 18 | ログ | token / Cookie が Console・ログに出ない。⚠ PIN の Console 表示は仕様（運用者が参照） | ☐ |

## 5. 記録の残し方

- PR 本文の「検証」欄に該当項目のみを転記し、`☐ → ☑`（または NG 内容）を記入する。
- NG が出た場合は**マージしない**（main への squash merge = 自動リリースのため）。
- 実機でしか出ない事象（COM の HResult、listener の例外）は、HResult / 例外メッセージを PR に貼る。
