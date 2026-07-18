# =============================================================================
#  tests/finish.tests.ps1  —  finish/ 移動先解決・移動処理のテスト
#
#  副作用回避方法: 【AST 抽出 (Resolve-SrcFunction)】
#  理由: utils.ps1 全体を dot-source せず、対象 2 関数だけを抽出して実行する。
#        Resolve-FinishDestination は FS 非依存の純粋関数としてテーブルテストし、
#        Move-ToFinishIfPending は temp ディレクトリ内だけで実ファイル移動を検証する。
# =============================================================================

. (Resolve-SrcFunction -Path "$PSScriptRoot/../src/utils.ps1" -Name 'Resolve-FinishDestination')
. (Resolve-SrcFunction -Path "$PSScriptRoot/../src/utils.ps1" -Name 'Move-ToFinishIfPending')

$ts = [datetime]'2026-07-18T12:34:56'

# --- Resolve-FinishDestination: 純粋関数 7 ケース ---
Assert-Equal 'deck.pptx' (Resolve-FinishDestination -FileName 'deck.pptx' -ExistingNames @() -Timestamp $ts) 'Resolve-FinishDestination: no collision keeps original name'
Assert-Equal 'deck.pptx' (Resolve-FinishDestination -FileName 'deck.pptx' -ExistingNames @('other.pptx') -Timestamp $ts) 'Resolve-FinishDestination: unrelated existing names keep original name'
Assert-Equal 'deck_20260718-123456.pptx' (Resolve-FinishDestination -FileName 'deck.pptx' -ExistingNames @('deck.pptx') -Timestamp $ts) 'Resolve-FinishDestination: collision inserts timestamp before extension'
Assert-Equal 'deck_20260718-123456-2.pptx' (Resolve-FinishDestination -FileName 'deck.pptx' -ExistingNames @('deck.pptx', 'deck_20260718-123456.pptx') -Timestamp $ts) 'Resolve-FinishDestination: same-second collision appends counter 2'
Assert-Equal 'deck_20260718-123456-3.pptx' (Resolve-FinishDestination -FileName 'deck.pptx' -ExistingNames @('deck.pptx', 'deck_20260718-123456.pptx', 'deck_20260718-123456-2.pptx') -Timestamp $ts) 'Resolve-FinishDestination: same-second collision advances counter'
Assert-Equal 'DECK_20260718-123456.PPTX' (Resolve-FinishDestination -FileName 'DECK.PPTX' -ExistingNames @('deck.pptx') -Timestamp $ts) 'Resolve-FinishDestination: existing names are compared case-insensitively'
Assert-Equal 'README_20260718-123456' (Resolve-FinishDestination -FileName 'README' -ExistingNames @('README') -Timestamp $ts) 'Resolve-FinishDestination: extensionless file uses timestamp suffix'

# --- Move-ToFinishIfPending: temp ディレクトリでの移動 5 シナリオ ---
$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("finishtest_" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmpRoot | Out-Null

try {
    $sourceDir = Join-Path $tmpRoot 'src'
    $finishDir = Join-Path $tmpRoot 'finish'
    New-Item -ItemType Directory -Path $sourceDir | Out-Null
    New-Item -ItemType Directory -Path $finishDir | Out-Null

    # 1. 基本移動: finish/ へ原名で移動される
    $basicPath = Join-Path $sourceDir 'basic.pptx'
    Set-Content -LiteralPath $basicPath -Value 'basic' -NoNewline
    $basicItem = Get-Item -LiteralPath $basicPath
    $basicMoved = Move-ToFinishIfPending -TargetFileItem $basicItem -FinishFolderPath $finishDir -Presentation $null -RetryDelaysMs @()

    Assert-True  (Test-Path -LiteralPath (Join-Path $finishDir 'basic.pptx')) 'Move-ToFinishIfPending: basic move creates destination file'
    Assert-True  (-not (Test-Path -LiteralPath $basicPath)) 'Move-ToFinishIfPending: basic move removes source file'
    Assert-Equal 'basic.pptx' $basicMoved.Name 'Move-ToFinishIfPending: basic move returns moved item'

    # 2. 衝突非上書き: 既存ファイルを残し、timestamp 付き別名へ移動される
    $collisionPath = Join-Path $sourceDir 'collision.pptx'
    $existingCollisionPath = Join-Path $finishDir 'collision.pptx'
    Set-Content -LiteralPath $collisionPath -Value 'new' -NoNewline
    Set-Content -LiteralPath $existingCollisionPath -Value 'old' -NoNewline
    $collisionItem = Get-Item -LiteralPath $collisionPath
    $collisionMoved = Move-ToFinishIfPending -TargetFileItem $collisionItem -FinishFolderPath $finishDir -Presentation $null -RetryDelaysMs @()
    $collisionFiles = Get-ChildItem -LiteralPath $finishDir -File | Where-Object { $_.Name -like 'collision*.pptx' } | Sort-Object Name

    Assert-Equal 'old' (Get-Content -LiteralPath $existingCollisionPath -Raw) 'Move-ToFinishIfPending: collision does not overwrite existing file'
    Assert-Equal 2 $collisionFiles.Count 'Move-ToFinishIfPending: collision leaves two files'
    Assert-True  ($collisionMoved.Name -ne 'collision.pptx') 'Move-ToFinishIfPending: collision returns renamed destination item'
    Assert-True  ($collisionMoved.Name -like 'collision_*.pptx') 'Move-ToFinishIfPending: collision destination has timestamp suffix'

    # 3. idempotent: 既に finish/ 内のファイルは再移動しない
    $finishedPath = Join-Path $finishDir 'already.pptx'
    Set-Content -LiteralPath $finishedPath -Value 'finished' -NoNewline
    $finishedItem = Get-Item -LiteralPath $finishedPath
    $finishedResult = Move-ToFinishIfPending -TargetFileItem $finishedItem -FinishFolderPath $finishDir -Presentation $null -RetryDelaysMs @()

    Assert-Equal $finishedItem.FullName $finishedResult.FullName 'Move-ToFinishIfPending: idempotent guard returns original item'
    Assert-Equal 1 @((Get-ChildItem -LiteralPath $finishDir -File | Where-Object { $_.Name -eq 'already.pptx' })).Count 'Move-ToFinishIfPending: idempotent guard does not duplicate file'

    # 4. ソース不在: 何もせず元 item を返す
    $missingPath = Join-Path $sourceDir 'missing.pptx'
    Set-Content -LiteralPath $missingPath -Value 'missing' -NoNewline
    $missingItem = Get-Item -LiteralPath $missingPath
    Remove-Item -LiteralPath $missingPath
    $missingResult = Move-ToFinishIfPending -TargetFileItem $missingItem -FinishFolderPath $finishDir -Presentation $null -RetryDelaysMs @()

    Assert-Equal $missingItem.FullName $missingResult.FullName 'Move-ToFinishIfPending: missing source returns original item'
    Assert-True  (-not (Test-Path -LiteralPath (Join-Path $finishDir 'missing.pptx'))) 'Move-ToFinishIfPending: missing source does not create destination'

    # 5. retry give-up: Move-Item が継続失敗したら retry 後に諦め、元 item とソースを保持する
    $retryPath = Join-Path $sourceDir 'retry.pptx'
    Set-Content -LiteralPath $retryPath -Value 'retry' -NoNewline
    $retryItem = Get-Item -LiteralPath $retryPath
    $script:InjectedMoveAttempts = 0

    function Move-Item {
        param(
            [string]$LiteralPath,
            [string]$Destination,
            [switch]$PassThru,
            [System.Management.Automation.ActionPreference]$ErrorAction
        )
        $script:InjectedMoveAttempts++
        throw ([System.IO.IOException]::new('simulated sharing violation'))
    }

    try {
        $retryResult = Move-ToFinishIfPending -TargetFileItem $retryItem -FinishFolderPath $finishDir -Presentation $null -RetryDelaysMs @(0, 0)

        Assert-Equal $retryItem.FullName $retryResult.FullName 'Move-ToFinishIfPending: retry give-up returns original item'
        Assert-True  (Test-Path -LiteralPath $retryPath) 'Move-ToFinishIfPending: retry give-up leaves source file in place'
        Assert-Equal 3 $script:InjectedMoveAttempts 'Move-ToFinishIfPending: retry count is attempts plus configured delays'
    } finally {
        Remove-Item Function:\Move-Item -Force -ErrorAction SilentlyContinue
        Remove-Variable -Name InjectedMoveAttempts -Scope Script -ErrorAction SilentlyContinue
    }
} finally {
    Remove-Item -Path $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
