# =============================================================================
#  tests/newdir.tests.ps1  —  New-DirectoryIfMissing の characterization テスト
#
#  副作用回避方法: 【AST 抽出 (Resolve-SrcFunction)】
#  理由: config.ps1 は param ブロック・Add-Type・トップレベルの状態ロード処理を含む。
#        ドットソースするとそれらが実行されるため、Resolve-SrcFunction が
#        Parser::ParseFile で AST を構築し、New-DirectoryIfMissing の
#        Extent.Text のみを ScriptBlock として返す。
#        他のコードは一切実行されないため副作用ゼロ。
# =============================================================================

. (Resolve-SrcFunction -Path "$PSScriptRoot/../src/config.ps1" -Name 'New-DirectoryIfMissing')

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("newdirtest_" + [System.IO.Path]::GetRandomFileName())
[void][System.IO.Directory]::CreateDirectory($root)

try {
    $bracketDir = Join-Path $root 'deck[1]'
    New-DirectoryIfMissing -Path $bracketDir

    Assert-True ([System.IO.Directory]::Exists($bracketDir)) 'New-DirectoryIfMissing: creates bracket directory literally'
    Assert-True (-not [System.IO.Directory]::Exists((Join-Path $root 'deck1'))) 'New-DirectoryIfMissing: does not wildcard-expand bracket path'

    New-DirectoryIfMissing -Path $bracketDir
    Assert-True ([System.IO.Directory]::Exists($bracketDir)) 'New-DirectoryIfMissing: idempotent for existing directory'

    $nestedDir = Join-Path (Join-Path $root 'a') 'b'
    New-DirectoryIfMissing -Path $nestedDir
    Assert-True ([System.IO.Directory]::Exists($nestedDir)) 'New-DirectoryIfMissing: creates intermediate directories'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
