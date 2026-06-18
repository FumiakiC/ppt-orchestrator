# =============================================================================
#  tests/securepin.tests.ps1  —  New-SecurePin の characterization テスト
#
#  副作用回避方法: 【AST 抽出 (Resolve-SrcFunction)】
#  理由: config.ps1 は先頭に param() ブロックと Add-Type（System.Web と
#        kernel32.dll / Win32 P/Invoke）を持ち、ファイル全体を dot-source すると
#        CI (ubuntu-latest) で Win32 API ロードを試みて失敗する。
#        Resolve-SrcFunction が New-SecurePin の Extent.Text のみを ScriptBlock
#        として返すため、Add-Type は実行されない（副作用ゼロ）。
#        Phase 1.3 で純粋ファイルへ移行後はパスを書き替えるだけでよい（期待値不変）。
# =============================================================================

. (Resolve-SrcFunction -Path "$PSScriptRoot/../src/config.ps1" -Name 'New-SecurePin')

# --- 性質テスト: 2000 回ループで範囲外を一度も返さないことを確認 ---
$allInRange = $true
for ($i = 0; $i -lt 2000; $i++) {
    $pin = New-SecurePin
    if (-not ($pin -is [int]) -or $pin -lt 100000 -or $pin -gt 999999) {
        $allInRange = $false
        break
    }
}
Assert-True $allInRange 'New-SecurePin: 2000 iterations all [int] in [100000,999999]'

# 6 桁であること（文字列表現で確認）
Assert-Equal 6 ("$(New-SecurePin)").Length 'New-SecurePin: result is 6 digits'
