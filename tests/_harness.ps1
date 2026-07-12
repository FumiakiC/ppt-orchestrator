# =============================================================================
#  tests/_harness.ps1  —  共通アサーション（Zero-Dependency: if/throw のみ）
#  run-tests.ps1 から dot-source して使う。テストファイルは直接読み込まない。
# =============================================================================

$script:TestPass    = 0
$script:TestFail    = 0
$script:TestPending = 0
$script:Failures    = @()

function Assert-Equal {
    param($Expected, $Actual, [string]$Because = '')
    # Null guard: both null → pass; one null → fail (distinguishes $null from '')
    if ($null -eq $Expected -and $null -eq $Actual) { $script:TestPass++; return }
    if ($null -eq $Expected -or  $null -eq $Actual) {
        $script:TestFail++
        $ne = if ($null -eq $Expected) { '<null>' } else { "$Expected" }
        $na = if ($null -eq $Actual)   { '<null>' } else { "$Actual" }
        $script:Failures += "[FAIL] $Because`n    expected: <$ne>`n    actual:   <$na>"
        return
    }
    if ($Expected -is [System.Array] -or $Actual -is [System.Array]) {
        $e = ($Expected -join '|'); $a = ($Actual -join '|')
    } else { $e = "$Expected"; $a = "$Actual" }
    if ($e -ceq $a) { $script:TestPass++ }
    else {
        $script:TestFail++
        $script:Failures += "[FAIL] $Because`n    expected: <$e>`n    actual:   <$a>"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Because = '')
    if ($Condition) { $script:TestPass++ }
    else { $script:TestFail++; $script:Failures += "[FAIL] $Because (expected: True)" }
}

function Write-TestPending {
    param([string]$Name)
    $script:TestPending++
    Write-Host "  [PENDING] $Name" -ForegroundColor Yellow
}

function Resolve-SrcFunction {
    # Uses the PowerShell AST to extract a single named function from $Path.
    # Returns a ScriptBlock of that function definition only — no other code
    # in the source file (Add-Type, param blocks, COM init, etc.) is executed.
    param([string]$Path, [string]$Name)
    $fullPath = (Resolve-Path -LiteralPath $Path).Path
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $fullPath, [ref]$tokens, [ref]$errors)
    if ($errors) { throw "Resolve-SrcFunction: parse error in '$Path': $($errors[0].Message)" }
    $found = $ast.FindAll(
        { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] },
        $true
    ) | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
    if (-not $found) { throw "Resolve-SrcFunction: '$Name' not found in '$Path'" }
    return [System.Management.Automation.ScriptBlock]::Create($found.Extent.Text)
}

function Invoke-TestSummary {
    Write-Host ""
    Write-Host "PASS: $script:TestPass  FAIL: $script:TestFail  PENDING: $script:TestPending"
    if ($script:TestFail -gt 0) {
        Write-Host ""
        $script:Failures | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        exit 1
    }
    exit 0
}
