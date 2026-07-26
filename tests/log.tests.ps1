# =============================================================================
#  tests/log.tests.ps1  —  Format-LogEvent の characterization テスト
#
#  副作用回避方法: 【AST 抽出 (Resolve-SrcFunction)】
#  理由: utils.ps1 は結合前提のソースで、ドットソースすると他関数も定義される。
#        Resolve-SrcFunction が Parser::ParseFile で AST を構築し、Format-LogEvent の
#        Extent.Text のみを ScriptBlock として返すため、他コードは一切実行されず
#        副作用ゼロで純粋関数だけを検証できる（newdir.tests.ps1 と同方式）。
#
#  Timestamp は固定値で渡す（Format-LogEvent は Timestamp に既定値を持たない純粋関数）。
# =============================================================================

. (Resolve-SrcFunction -Path "$PSScriptRoot/../src/utils.ps1" -Name 'Format-LogEvent')

$ts   = [datetime]::new(2026, 7, 26, 14, 3, 22, 145, [System.DateTimeKind]::Local)
$base = @{ Timestamp = $ts; ElapsedMs = 193145; Sid = '20260726-140009'; Seq = 412 }

# --- 1) フィールド順序: ts, t, sid, seq, lvl, ev, cid, ip, d の登場順が単調増加 ---
$line = Format-LogEvent @base -Level 'info' -EventName 'slide.next' -Cid 'C1' -Ip '10.0.0.5' -Data ([ordered]@{ n = 3 })
$order = @('"ts"','"t"','"sid"','"seq"','"lvl"','"ev"','"cid"','"ip"','"d"')
$idx = $order | ForEach-Object { $line.IndexOf($_) }
$monotonic = $true
for ($i = 1; $i -lt $idx.Count; $i++) {
    if ($idx[$i] -le $idx[$i - 1] -or $idx[$i] -lt 0) { $monotonic = $false; break }
}
Assert-True $monotonic 'Format-LogEvent: emits fields in fixed order ts,t,sid,seq,lvl,ev,cid,ip,d'

# --- 2) 1行であること: 物理的な改行を含まない ---
$oneLine = Format-LogEvent @base -EventName 'status.ok'
Assert-True (-not $oneLine.Contains("`n") -and -not $oneLine.Contains("`r")) 'Format-LogEvent: returns a single physical line (no CR/LF)'

# --- 3) 改行のエスケープ: 値中の改行は \n としてエスケープされ、行は割れない ---
$nlLine = Format-LogEvent @base -EventName "a`nb"
Assert-True ($nlLine.Contains('a\nb') -and -not $nlLine.Contains("`n") -and -not $nlLine.Contains("`r")) 'Format-LogEvent: escapes embedded newline without splitting the physical line'

# --- 4) 空 cid の省略: 空文字なら "cid" キー自体を出さない ---
$noCid = Format-LogEvent @base -EventName 'e' -Cid ''
Assert-True (-not $noCid.Contains('"cid"')) 'Format-LogEvent: omits cid key when empty'

# --- 5) 空 ip の省略: 空文字なら "ip" キー自体を出さない ---
$noIp = Format-LogEvent @base -EventName 'e' -Ip ''
Assert-True (-not $noIp.Contains('"ip"')) 'Format-LogEvent: omits ip key when empty'

# --- 6) cid の出力: 値ありなら "cid":"..." が出る ---
$withCid = Format-LogEvent @base -EventName 'e' -Cid 'abc123'
Assert-True ($withCid.Contains('"cid":"abc123"')) 'Format-LogEvent: emits cid when provided'

# --- 7) ip の出力: 値ありなら "ip":"..." が出る ---
$withIp = Format-LogEvent @base -EventName 'e' -Ip '192.168.1.42'
Assert-True ($withIp.Contains('"ip":"192.168.1.42"')) 'Format-LogEvent: emits ip when provided'

# --- 8) 数値が数値型のまま: t / seq / Data 内の数値が引用符なしで出る ---
$numLine = Format-LogEvent @base -EventName 'm' -Data ([ordered]@{ count = 7 })
Assert-True ($numLine.Contains('"t":193145') -and $numLine.Contains('"seq":412') -and $numLine.Contains('"count":7')) 'Format-LogEvent: numeric values stay bare numbers'

# --- 9) 空 Data で d を出さない: 未指定・0件のどちらでも "d" キーを出さない ---
$noData = Format-LogEvent @base -EventName 'e'
$emptyData = Format-LogEvent @base -EventName 'e' -Data ([ordered]@{})
Assert-True (-not $noData.Contains('"d"') -and -not $emptyData.Contains('"d"')) 'Format-LogEvent: omits d when Data is absent or empty'

# --- 10) 配列が Depth で潰れない: 入れ子配列が [..] として保持される ---
$arrLine = Format-LogEvent @base -EventName 'e' -Data ([ordered]@{ vals = @(1, 2, 3) })
Assert-True ($arrLine.Contains('"vals":[1,2,3]')) 'Format-LogEvent: nested array is preserved (not collapsed by Depth)'

# --- 11) Level の ValidateSet(有効): warn を受け入れて "lvl":"warn" を出す ---
$warnLine = Format-LogEvent @base -Level 'warn' -EventName 'e'
Assert-True ($warnLine.Contains('"lvl":"warn"')) 'Format-LogEvent: accepts valid Level (warn)'

# --- 12) Level の ValidateSet(無効): 未定義値は例外で拒否する ---
$threw = $false
try { Format-LogEvent @base -Level 'debug' -EventName 'e' } catch { $threw = $true }
Assert-True $threw 'Format-LogEvent: rejects Level outside the ValidateSet'
