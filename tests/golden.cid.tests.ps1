# =============================================================================
#  tests/golden.cid.tests.ps1  —  cid 抽出 の期待入出力テーブル（層2 有効）
#
#  対象ロジック（src/utils.ps1 Get-CidFromBody）:
#    $decoded = [System.Web.HttpUtility]::UrlDecode($Body)
#    if ($decoded -match 'cid=([A-Za-z0-9_\-]+)') { return $matches[1] } else { return '' }
#
#  現状仕様として固定する挙動（このファイル内の期待表 [D]）:
#    'cid=abc123'      -> 'abc123'
#    'cid=a_b-c'       -> 'a_b-c'
#    'x=1&cid=ZZ9'     -> 'ZZ9'
#    'CID=abc'         -> 'abc'        # -match 既定で大小無視
#    'cid=ab%E6%97%A5' -> 'ab'         # UrlDecode 後 'ab日'、日は許可文字外
#    'cid='            -> ''           # + は 1 文字以上を要求 → 不一致
#    'foo=bar'         -> ''           # cid キーなし
# =============================================================================

. (Resolve-SrcFunction -Path "$PSScriptRoot/../src/utils.ps1" -Name 'Get-CidFromBody')

Assert-Equal 'abc123' (Get-CidFromBody 'cid=abc123')      '[D] cid=abc123'
Assert-Equal 'a_b-c'  (Get-CidFromBody 'cid=a_b-c')       '[D] cid=a_b-c'
Assert-Equal 'ZZ9'    (Get-CidFromBody 'x=1&cid=ZZ9')     '[D] x=1&cid=ZZ9'
Assert-Equal 'abc'    (Get-CidFromBody 'CID=abc')          '[D] CID=abc'
Assert-Equal 'ab'     (Get-CidFromBody 'cid=ab%E6%97%A5') '[D] cid=ab%E6%97%A5'
Assert-Equal ''       (Get-CidFromBody 'cid=')             '[D] cid='
Assert-Equal ''       (Get-CidFromBody 'foo=bar')          '[D] foo=bar'
