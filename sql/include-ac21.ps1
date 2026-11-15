# SQL-03B AC-21 + optional AC-20, dot-sourced by the owned SQL-02 scratch runner.
# Always read the frozen golden-oracles.json at runtime; no duplicated expected.
$report['SqlId'] = $report['SqlId'] + '+SQL-03B'
$report['AcId'] = $report['AcId'] + '+AC-21+AC-20'
$report['Ac21Oracle'] = 'business/reference-data/expected-results/golden-oracles.json#AC-21'
$report['Ac20Oracle'] = 'business/reference-data/expected-results/golden-oracles.json#AC-20'
$report['Ac21Checkpoints'] = @()
$report['Ac20Checkpoints'] = @()
$report['Ac21Negative'] = 'NOT_RUN'

foreach ($file in @(
    'schema/006_ac21.sql',
    'schema/007_ac21_commands.sql',
    'scenarios/ac21.sql',
    'tests/ac21-negative.sql'
)) {
    Assert-OwnedMarker $script:DbName $script:TestRunId
    $path = Join-Path $PSScriptRoot ($file.Replace('/', [IO.Path]::DirectorySeparatorChar))
    [void](Run-Sql -Database $script:DbName -File $path -Label $file)
}
$report['Ac21Negative'] = 'PASS'
$goldenFile = Join-Path $root 'business/reference-data/expected-results/golden-oracles.json'
$golden = Get-Content -LiteralPath $goldenFile -Raw -Encoding UTF8 | ConvertFrom-Json

function Compare-Ac21Golden {
    param([string]$AcId)
    if ($AcId -eq 'AC-21') {
        $cols = @('step','ar','credit','custody','fund','allocated')
        $sqlCols = @('Ar','Credit','Custody','Fund','Allocated')
        $table = 'CustomerCheckpoint'
        $evidenceKey = 'Ac21Checkpoints'
    } elseif ($AcId -eq 'AC-20') {
        $cols = @('step','issued','approvedExpenses','cashierAcceptedReturns','outstanding')
        $sqlCols = @('Issued','ApprovedExpenses','CashierAcceptedReturns','Outstanding')
        $table = 'AdvanceCheckpoint'
        $evidenceKey = 'Ac20Checkpoints'
    } else {
        throw "Unknown AC golden identity [$AcId]"
    }
    $oracle = $golden.PSObject.Properties[$AcId].Value
    if ($null -eq $oracle -or $oracle.currency -ne 'VND' -or
        $oracle.status -ne 'MODEL_ONLY' -or
        ($oracle.cols -join ',') -cne ($cols -join ',') -or
        $oracle.steps.Count -ne 5) {
        throw "$AcId oracle shape/currency/status unexpectedly changed"
    }
    $fields = @('Step')
    $fields += $sqlCols | ForEach-Object { "CONVERT(varchar(80),[$_])" }
    $query = 'SET NOCOUNT ON; SELECT ' + ($fields -join ',') +
             " FROM ac21.$table ORDER BY StepOrdinal;"
    $argsSql = @('-S',$ServerInstance,'-E','-d',$script:DbName,
                 '-b','-V','11','-r','1','-W','-h','-1','-w','65535',
                 '-s','|','-Q',$query)
    $output = @(& $SqlcmdPath @argsSql 2>&1 | ForEach-Object { $_.ToString() })
    if ($LASTEXITCODE -ne 0) { throw "$AcId actual export failed: $($output -join '; ')" }
    $rows = @($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($rows.Count -ne 5) { throw "$AcId expected 5 SQL rows, got $($rows.Count): $($rows -join '; ')" }
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    for ($i = 0; $i -lt 5; $i++) {
        $cells = @($rows[$i].Split('|') | ForEach-Object { $_.Trim() })
        $expected = @($oracle.steps[$i])
        if ($cells.Count -ne $cols.Count -or $expected.Count -ne $cols.Count) {
            throw "$AcId checkpoint index $i width mismatch"
        }
        $diff = @()
        $actual = [ordered]@{step=$cells[0]}
        if ($cells[0] -cne [string]$expected[0]) {
            $diff += "step expected=$($expected[0]) actual=$($cells[0])"
        }
        for ($j = 1; $j -lt $cols.Count; $j++) {
            $value = [decimal]::Parse($cells[$j],
                        [System.Globalization.NumberStyles]::Number,$culture)
            $expectedValue = [decimal]$expected[$j]
            $actual[$cols[$j]] = $value
            if ($value -ne $expectedValue) {
                $diff += "$($cols[$j]) expected=$expectedValue actual=$value"
            }
        }
        $report[$evidenceKey] += [ordered]@{
            Step=$actual.step
            Expected=$expected
            Actual=$actual
            Status=if ($diff.Count -eq 0) {'PASS'} else {'FAIL'}
            Differences=$diff
        }
        Write-Host "$AcId $($actual.step) : $(if ($diff.Count -eq 0) {'PASS'} else {'FAIL'})"
        if ($diff.Count -gt 0) {
            throw "$AcId golden mismatch: $($diff -join '; ')"
        }
    }
}
Compare-Ac21Golden 'AC-21'
Compare-Ac21Golden 'AC-20'
