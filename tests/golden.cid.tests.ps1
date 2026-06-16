# =============================================================================
#  tests/golden.cid.tests.ps1  —  cid 抽出 の期待入出力テーブル（層2 pending）
#
#  TODO Phase 1.3: Get-CidFromBody が src/ から純粋関数として抽出されたら、
#                  下記コメント内のアサーションを有効化して Write-TestPending を削除する。
#
#  対象ロジック（現状 src/com-handler.ps1 にインライン）:
#    $decoded = [System.Web.HttpUtility]::UrlDecode($reqBody)
#    if ($decoded -match 'cid=([A-Za-z0-9_\-]+)') { $cid = $matches[1] } else { $cid = '' }
#
#  現状仕様として固定する挙動（docs/01_characterization_spec.txt [D]）:
#    'cid=abc123'      -> 'abc123'
#    'cid=a_b-c'       -> 'a_b-c'
#    'x=1&cid=ZZ9'     -> 'ZZ9'
#    'CID=abc'         -> 'abc'        # -match 既定で大小無視
#    'cid=ab%E6%97%A5' -> 'ab'         # UrlDecode 後 'ab日'、日は許可文字外
#    'cid='            -> ''           # + は 1 文字以上を要求 → 不一致
#    'foo=bar'         -> ''           # cid キーなし
# =============================================================================

Write-TestPending '[D] cid=abc123 -> abc123'
# Assert-Equal 'abc123' (Get-CidFromBody 'cid=abc123')      '[D] cid=abc123'

Write-TestPending '[D] cid=a_b-c -> a_b-c'
# Assert-Equal 'a_b-c'  (Get-CidFromBody 'cid=a_b-c')       '[D] cid=a_b-c'

Write-TestPending '[D] x=1&cid=ZZ9 -> ZZ9'
# Assert-Equal 'ZZ9'    (Get-CidFromBody 'x=1&cid=ZZ9')     '[D] x=1&cid=ZZ9'

Write-TestPending '[D] CID=abc -> abc (case-insensitive)'
# Assert-Equal 'abc'    (Get-CidFromBody 'CID=abc')          '[D] CID=abc'

Write-TestPending '[D] cid=ab%E6%97%A5 -> ab (non-ASCII truncated)'
# Assert-Equal 'ab'     (Get-CidFromBody 'cid=ab%E6%97%A5') '[D] cid=ab%E6%97%A5'

Write-TestPending '[D] cid= -> empty string'
# Assert-Equal ''       (Get-CidFromBody 'cid=')             '[D] cid='

Write-TestPending '[D] foo=bar -> empty string (no cid key)'
# Assert-Equal ''       (Get-CidFromBody 'foo=bar')          '[D] foo=bar'
