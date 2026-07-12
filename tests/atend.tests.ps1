# =============================================================================
#  tests/atend.tests.ps1  —  Test-SlideShowAtEnd の characterization テスト
#
#  副作用回避方法: 【AST 抽出 (Resolve-SrcFunction)】
#  理由: com-handler.ps1 は Watch-RunningPresentation（HttpListener/COM 依存）や
#        Set-PptKillOnClose（Win32 P/Invoke）等を含む 350 行超のファイル。
#        Resolve-SrcFunction が Parser::ParseFile で AST を構築し、
#        Test-SlideShowAtEnd の Extent.Text のみを ScriptBlock として返す。
#        他のコードは一切実行されないため副作用ゼロ。
#        Phase 1.3 で純粋ファイルへ移行後はパスを書き替えるだけでよい（期待値不変）。
# =============================================================================

. (Resolve-SrcFunction -Path "$PSScriptRoot/../src/com-handler.ps1" -Name 'Test-SlideShowAtEnd')

# --- モックビュー（GetClickIndex / GetClickCount を持つ PSCustomObject） ---
function New-MockView {
    param([int]$ci, [int]$cc, [bool]$throws = $false)
    [pscustomobject]@{} |
        Add-Member -PassThru ScriptMethod GetClickIndex { if ($throws) { throw 'mock' }; $ci }.GetNewClosure() |
        Add-Member -PassThru ScriptMethod GetClickCount { $cc }.GetNewClosure()
}

# --- テストケース（このファイル内の期待表 [A] どおり） ---

# Total <= 0 ガード
Assert-Equal $false (Test-SlideShowAtEnd -View (New-MockView 0 0)         -Pos 3  -Total 0)  'Total=0 guard'
Assert-Equal $false (Test-SlideShowAtEnd -View (New-MockView 0 0)         -Pos 0  -Total -1) 'Total=-1 guard'

# Pos < Total → まだ手前
Assert-Equal $false (Test-SlideShowAtEnd -View (New-MockView 0 0)         -Pos 3  -Total 10) 'before end'

# 最終スライド & ビルド消化済み（ci >= cc）→ true
Assert-Equal $true  (Test-SlideShowAtEnd -View (New-MockView 2 2)         -Pos 10 -Total 10) 'end & builds consumed (ci=2 cc=2)'

# 最終スライド & 未消化ビルド残り（ci < cc）→ false
Assert-Equal $false (Test-SlideShowAtEnd -View (New-MockView 1 2)         -Pos 10 -Total 10) 'end & build remains (ci=1 cc=2)'

# View が例外 → フォールバック true
Assert-Equal $true  (Test-SlideShowAtEnd -View (New-MockView 0 0 $true)   -Pos 10 -Total 10) 'throw -> fallback true'
