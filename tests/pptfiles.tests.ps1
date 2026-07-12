# =============================================================================
#  tests/pptfiles.tests.ps1  —  Get-PptFiles の characterization テスト
#
#  副作用回避方法: 【AST 抽出 (Resolve-SrcFunction)】
#  理由: utils.ps1 は Get-HtmlHeader（$script:HtmlTemplates 依存）等を含む。
#        Resolve-SrcFunction が Parser::ParseFile で AST を構築し、
#        Get-PptFiles の Extent.Text のみを ScriptBlock として返す。
#        他の関数・グローバル参照は一切発生しないため副作用ゼロ。
#        Phase 1.3 で純粋ファイルへ移行後はパスを書き替えるだけでよい（期待値不変）。
# =============================================================================

. (Resolve-SrcFunction -Path "$PSScriptRoot/../src/utils.ps1" -Name 'Get-PptFiles')

# --- 一時ディレクトリにダミーファイルを作成してテスト ---
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ppttest_" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmpDir | Out-Null

try {
    foreach ($name in @('a.pptx', 'b.ppt', 'C.PPTX', '~$lock.pptx', 'note.txt', 'scan.pdf')) {
        New-Item -Path (Join-Path $tmpDir $name) -ItemType File | Out-Null
    }

    $result = Get-PptFiles -Path $tmpDir

    # 対象集合: .ppt / .pptx のみ、~$ 除外 → 3 ファイル
    Assert-Equal 3 $result.Count 'Get-PptFiles: returns 3 files'

    # ~$ ロックファイルは除外
    Assert-True  ($result.Name -notcontains '~$lock.pptx') 'Get-PptFiles: lock file excluded'

    # 非 PPT ファイルは除外
    Assert-True  ($result.Name -notcontains 'note.txt')    'Get-PptFiles: .txt excluded'
    Assert-True  ($result.Name -notcontains 'scan.pdf')    'Get-PptFiles: .pdf excluded'

    # 大文字拡張子 (.PPTX) も採用（-in は既定で大小無視）
    Assert-True  ($result.Name -contains 'C.PPTX')         'Get-PptFiles: uppercase .PPTX included'
    Assert-True  ($result.Name -contains 'a.pptx')         'Get-PptFiles: a.pptx included'
    Assert-True  ($result.Name -contains 'b.ppt')          'Get-PptFiles: b.ppt included'

    # Sort-Object Name が適用済みであること
    # （厳密な並び順は OS/ロケール依存のため、結果がそれ自身のソートと一致することで検証）
    $sortedNames = $result.Name | Sort-Object
    Assert-Equal $sortedNames $result.Name 'Get-PptFiles: result is sorted by Name'

} finally {
    Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
