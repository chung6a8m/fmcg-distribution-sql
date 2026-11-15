# SQL-03C / AC-06 extension to the guarded SQL-02 disposable scratch runner.
# The expected values are NEVER embedded in SQL. Read the frozen JSON at run time.
$report['SqlId'] = $report['SqlId'] + '+SQL-03C'
$report['AcId'] = $report['AcId'] + '+AC-06'
$report['Ac06Oracle'] = 'business/reference-data/expected-results/additional-oracles.json#AC-06'
$report['Ac06Fields'] = @()
$report['Ac06Checkpoints'] = @()
$report['Ac06Negative'] = 'NOT_RUN'
foreach ($file in @(
    'schema/008_ac06.sql',
    'schema/009_ac06_commands.sql',
    'scenarios/ac06.sql',
    'tests/ac06-negative.sql'
)) {
    Assert-OwnedMarker $script:DbName $script:TestRunId
    $path = Join-Path $PSScriptRoot ($file.Replace('/', [IO.Path]::DirectorySeparatorChar))
    [void](Run-Sql -Database $script:DbName -File $path -Label $file)
}
$report['Ac06Negative'] = 'PASS'
$oracleFile = Join-Path $root 'business/reference-data/expected-results/additional-oracles.json'
$golden = Get-Content -LiteralPath $oracleFile -Raw -Encoding UTF8 | ConvertFrom-Json
$oracle = $golden.PSObject.Properties['AC-06'].Value
if ($null -eq $oracle -or $golden.metadata.status -ne 'MODEL_ONLY' -or
    ($oracle.ruleRefs -join ',') -cne 'BR-07,BR-20' -or
    $oracle.lockedPeriodMutationAllowed -ne $false) {
    throw 'AC06_ORACLE_PROVENANCE_OR_SHAPE_CHANGED'
}
$fields = @('sourceQty','sourceOriginalCost','firstRefund',
            'originalSecondRefund','sourceAdjustedCost','firstRefundAdjustment',
            'finalSecondRefund','expectedOriginalSum','expectedAdjustedSum',
            'lockedPeriodMutationAllowed')
$sqlFields = @('SourceQty','SourceOriginalCost','FirstRefund',
               'OriginalSecondRefund','SourceAdjustedCost','FirstRefundAdjustment',
               'FinalSecondRefund','ExpectedOriginalSum','ExpectedAdjustedSum',
               'LockedPeriodMutationAllowed')
if ($oracle.PSObject.Properties.Count -lt 12) {
    throw 'AC06_ORACLE_FIELD_SET_UNEXPECTED'
}
$query = 'SET NOCOUNT ON; SELECT ' +
         (($sqlFields | ForEach-Object { "CONVERT(varchar(80),[$_])" }) -join ',') +
         " FROM ac06.CaseActual WHERE TenantId='T_COST' AND SourceId='ISSUE_MAIN';"
$argsSql = @('-S',$ServerInstance,'-E','-d',$script:DbName,
             '-b','-V','11','-r','1','-W','-h','-1','-w','65535',
             '-s','|','-Q',$query)
$output = @(& $SqlcmdPath @argsSql 2>&1 | ForEach-Object { $_.ToString() })
if ($LASTEXITCODE -ne 0) { throw "AC-06 actual export failed: $($output -join '; ')" }
$rows = @($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($rows.Count -ne 1) { throw "AC-06 expected one source row, got $($rows.Count)" }
$cells = @($rows[0].Split('|') | ForEach-Object { $_.Trim() })
if ($cells.Count -ne $fields.Count) {
    throw "AC-06 actual width differs: $($cells.Count) vs $($fields.Count)"
}
$culture = [System.Globalization.CultureInfo]::InvariantCulture
for ($i=0; $i -lt $fields.Count; $i++) {
    $field = $fields[$i]
    $expected = $oracle.PSObject.Properties[$field].Value
    if ($null -eq $expected) { throw "AC-06 missing golden field [$field]" }
    if ($field -eq 'lockedPeriodMutationAllowed') {
        if ($cells[$i] -notin @('0','1')) {
            throw "AC-06 locked-period probe must be a bit: $($cells[$i])"
        }
        $actual = ($cells[$i] -eq '1')
        $same = ($actual -eq [bool]$expected)
    } else {
        $actual = [decimal]::Parse($cells[$i],
                [System.Globalization.NumberStyles]::Number,$culture)
        $same = ($actual -eq [decimal]$expected)
    }
    $status = if ($same) { 'PASS' } else { 'FAIL' }
    $report['Ac06Fields'] += [ordered]@{
        Field = $field
        Expected = $expected
        Actual = $actual
        Status = $status
    }
    Write-Host "AC-06 $field : $status"
    if (-not $same) {
        throw "AC-06 golden mismatch at $field : expected=$expected actual=$actual"
    }
}
# Preserve real intermediate balances for reviewer inspection; this is not
# another hardcoded set of step expectations.
$checkpointQuery = 'SET NOCOUNT ON; SELECT StepOrdinal,StepName,' +
  'CONVERT(varchar(50),SourceVersion),CONVERT(varchar(50),SourceTotalCost),' +
  'CONVERT(varchar(50),ReturnedQty),CONVERT(varchar(50),RefundTotal),' +
  'CONVERT(varchar(50),Cogs),CONVERT(varchar(50),MainQty),' +
  'CONVERT(varchar(50),MainValue),CONVERT(varchar(50),QuarantineQty),' +
  'CONVERT(varchar(50),QuarantineValue) FROM ac06.Checkpoint ORDER BY StepOrdinal;'
$argsSql[-1] = $checkpointQuery
$output = @(& $SqlcmdPath @argsSql 2>&1 | ForEach-Object { $_.ToString() })
if ($LASTEXITCODE -ne 0) { throw "AC-06 checkpoints export failed: $($output -join '; ')" }
$rows = @($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($rows.Count -ne 3) { throw "AC-06 expected 3 actual checkpoints, got $($rows.Count)" }
$checkpointNames = @('FIRST_RETURN','AFTER_ADJUST','FINAL_RETURN')
for ($i=0; $i -lt $rows.Count; $i++) {
    $part = @($rows[$i].Split('|') | ForEach-Object { $_.Trim() })
    if ($part.Count -ne 11 -or $part[0] -ne [string]($i+1) -or
        $part[1] -cne $checkpointNames[$i]) {
        throw "AC-06 checkpoint order/width mismatch at $i : $($rows[$i])"
    }
    $report['Ac06Checkpoints'] += [ordered]@{
        StepOrdinal = $i+1
        StepName = $part[1]
        SourceVersion = [int]$part[2]
        SourceTotalCost = [decimal]$part[3]
        ReturnedQty = [int]$part[4]
        RefundTotal = [decimal]$part[5]
        Cogs = [decimal]$part[6]
        MainQty = [int]$part[7]
        MainValue = [decimal]$part[8]
        QuarantineQty = [int]$part[9]
        QuarantineValue = [decimal]$part[10]
    }
}
