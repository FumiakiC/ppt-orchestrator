# =============================================================================
#  tests/golden.pin.tests.ps1  —  PIN 抽出 の期待入出力テーブル（層2 pending）
#
#  TODO Phase 1.3: Get-PinFromBody が src/ から純粋関数として抽出されたら、
#                  下記コメント内のアサーションを有効化して Write-TestPending を削除する。
#
#  対象ロジック（現状 src/auth.ps1 Invoke-AuthHandler にインライン）:
#    if ([System.Web.HttpUtility]::UrlDecode($Body) -match "pin=([0-9]{6})") { $submittedPin = $matches[1] }
#
#  現状仕様として固定する挙動（このファイル内の期待表 [E]）:
#    'pin=123456'      -> '123456'
#    'PIN=123456'      -> '123456'   # -match 既定で大小無視
#    'a=b&pin=000123'  -> '000123'
#    'pin=12345'       -> ''         # 5 桁は {6} に満たず不一致
#    'pin=1234567'     -> '123456'   # ★アンカー無し→先頭 6 桁を捕捉（現状仕様として固定）
#    'xpin=123456'     -> '123456'   # ★部分一致許容（現状仕様として固定）
# =============================================================================

Write-TestPending '[E] pin=123456 -> 123456'
# Assert-Equal '123456' (Get-PinFromBody 'pin=123456')      '[E] pin=123456'

Write-TestPending '[E] PIN=123456 -> 123456 (case-insensitive)'
# Assert-Equal '123456' (Get-PinFromBody 'PIN=123456')      '[E] PIN=123456'

Write-TestPending '[E] a=b&pin=000123 -> 000123'
# Assert-Equal '000123' (Get-PinFromBody 'a=b&pin=000123')  '[E] a=b&pin=000123'

Write-TestPending '[E] pin=12345 -> empty (5 digits)'
# Assert-Equal ''       (Get-PinFromBody 'pin=12345')       '[E] pin=12345'

Write-TestPending '[E] pin=1234567 -> 123456 (first 6 digits, no anchor)'
# Assert-Equal '123456' (Get-PinFromBody 'pin=1234567')     '[E] pin=1234567'

Write-TestPending '[E] xpin=123456 -> 123456 (partial match allowed)'
# Assert-Equal '123456' (Get-PinFromBody 'xpin=123456')     '[E] xpin=123456'
