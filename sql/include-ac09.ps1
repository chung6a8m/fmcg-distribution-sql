# Dot-sourced by run-tests.ps1 after AC-03 assertions. Shares its guarded
# scratch DB, sqlcmd wrapper and evidence; never creates/reuses a target itself.
# All oracle numbers come from frozen additional-oracles.json at runtime.
$report['SqlId'] = 'SQL-02+SQL-03A'
$report['AcId'] = 'AC-03+AC-09'
$report['Ac09Oracle'] = 'business/reference-data/expected-results/additional-oracles.json#AC-09'
$report['Ac09Cases'] = @()
$report['Ac09Negative'] = 'NOT_RUN'
$report['Ac09Races'] = @()

function Format-SqlNumber {
    param([object]$Number)
    return ([decimal]$Number).ToString([System.Globalization.CultureInfo]::InvariantCulture)
}
function Invoke-ParallelSqlRace {
    param([string]$RaceId)
    $jobs = @()
    try {
        foreach ($side in @('A','B')) {
            # Start-Job spawns two distinct PowerShell/sqlcmd processes and thus
            # two actual SQL connections. SQL barrier requires both SPIDs to
            # begin before either sale can reach its serialization lock.
            $jobs += Start-Job -ScriptBlock {
                param($Exe,$Instance,$Db,$Race,$Attempt)
                $query = "SET NOCOUNT ON; EXEC ac09.RunRaceAttempt '$Race','$Attempt';"
                $out = @(& $Exe '-S' $Instance '-E' '-d' $Db '-b' '-V' '11' '-r' '1' '-W' '-h' '-1' '-Q' $query 2>&1 |
                         ForEach-Object { $_.ToString() })
                [pscustomobject]@{
                    Attempt = $Attempt
                    ExitCode = $LASTEXITCODE
                    Output = ($out -join [Environment]::NewLine).Trim()
                }
            } -ArgumentList $SqlcmdPath,$ServerInstance,$script:DbName,$RaceId,$side
        }
        $null = Wait-Job -Job $jobs -Timeout 100
        $results = @()
        foreach ($job in $jobs) {
            if ($job.State -ne 'Completed') {
                throw "SQL03A_RACE_JOB_NOT_COMPLETED: $RaceId $($job.State)"
            }
            $received = @(Receive-Job -Job $job -ErrorAction Stop)
            if ($received.Count -ne 1 -or $received[0].ExitCode -ne 0 -or
                $received[0].Output -notmatch "RACE_RESULT\|$RaceId\|[AB]\|(ACCEPTED|REJECTED)\|[0-9]+") {
                throw "SQL03A_RACE_CLIENT_FAILED: $RaceId $($received | Out-String)"
            }
            $results += $received[0]
        }
        return $results
    } finally {
        foreach ($job in $jobs) {
            if ($job.State -eq 'Running') { Stop-Job -Job $job -ErrorAction SilentlyContinue }
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }
}

foreach ($file in @('schema/004_ac09.sql','schema/005_ac09_commands.sql')) {
    Assert-OwnedMarker $script:DbName $script:TestRunId
    [void](Run-Sql -Database $script:DbName -File (Join-Path $PSScriptRoot $file) -Label $file)
}
$oracleFile = Join-Path $root 'business/reference-data/expected-results/additional-oracles.json'
$additional = Get-Content -LiteralPath $oracleFile -Raw -Encoding UTF8 | ConvertFrom-Json
$oracle09 = $additional.PSObject.Properties['AC-09'].Value
$cases = @($oracle09.cases)
$caseIds = @('CASH_60','CASH_100','CASH_60_CREDIT_20','BANK_PENDING','CASH_OVERPAY_120')
if ($cases.Count -ne 5 -or @(Compare-Object -ReferenceObject $caseIds -DifferenceObject @($cases | ForEach-Object { $_.caseId })).Count -ne 0) {
    throw 'AC09_ORACLE_CASE_SET_CHANGED'
}

foreach ($case in $cases) {
    $id = [string]$case.caseId
    if ($id -cnotmatch '^[A-Z0-9_]{1,32}$') { throw "AC09_UNSAFE_ORACLE_CASE_ID: $id" }
    $p = Format-SqlNumber $case.P
    $cash = Format-SqlNumber $case.verifiedReceiptApplied
    $credit = Format-SqlNumber $case.reservedCustomerCreditApplied
    $grant = Format-SqlNumber $case.openingGrant
    $actualCash = if ($case.PSObject.Properties['actualCashReceived']) {
        Format-SqlNumber $case.actualCashReceived
    } else { $cash }
    # BANK_PENDING has no verified receipt and no cash custody. The pending
    # evidence is deliberately P, fixture-only, not an eligible payment.
    $bankPending = if ($id -eq 'BANK_PENDING') { $p } else { '0' }
    if ([decimal]$actualCash -lt [decimal]$cash) { throw "AC09_INVALID_ORACLE_CASH_INPUT: $id" }
    # Synthetic trip has one unit/one B right, source cost10. The only
    # opening credit is pre-reserved for the credit20 branch.
    $setup = "SET NOCOUNT ON; INSERT ac09.Pool VALUES('T09','$id','TR_$id','SKU01','C_B',1,1,$grant,$credit,10); SELECT 'SEEDED';"
    Assert-OwnedMarker $script:DbName $script:TestRunId
    $seeded = Run-Sql -Database $script:DbName -Query $setup -Label "ac09 seed $id"
    if ($seeded -ne 'SEEDED') { throw "AC09_POOL_SEED_FAILED $id : $seeded" }
    $sql = @"
SET NOCOUNT ON;
DECLARE @R varchar(32);
EXEC ac09.ExecuteSale @PoolId='$id',@CommandId='SALE_$id',
    @Qty=1,@UnitPrice=$p,@CashApplied=$cash,@ReservedCreditApplied=$credit,
    @ActualCashReceived=$actualCash,@PendingBankEvidence=$bankPending,@Result=@R OUTPUT;
SELECT @R;
"@
    $result = Run-Sql -Database $script:DbName -Query $sql -Label "ac09 execute $id"
    if ($result -ne 'ACCEPTED') { throw "AC09_SALE_NOT_ACCEPTED $id : $result" }
    [void](Run-Sql -Database $script:DbName -Query "EXEC ac09.AssertPool '$id';" -Label "ac09 invariant $id")

    $names = @('ArRemaining','GrantRemaining','CustodyCash','NewCustomerCredit',
               'CreditRemaining','QuotaRemaining','StockRemaining','Cogs',
               'AppliedCash','AppliedCredit','ConfirmedCash','PendingBank','CommandCount')
    $extract = "SET NOCOUNT ON; SELECT CONCAT(" + (($names | ForEach-Object {
        "CONVERT(varchar(80),[$_])"
    }) -join ",'|',") + ") FROM ac09.PoolBalances WHERE TenantId='T09' AND PoolId='$id';"
    $raw = Run-Sql -Database $script:DbName -Query $extract -Label "ac09 actual $id"
    $cells = @($raw.Split('|') | ForEach-Object { $_.Trim() })
    if ($cells.Count -ne $names.Count) { throw "AC09_ACTUAL_WIDTH $id : $raw" }
    $mint = if ($case.PSObject.Properties['expectedNewCustomerCredit']) {
        [decimal]$case.expectedNewCustomerCredit
    } else { [decimal]0 }
    $expected = [ordered]@{
        ArRemaining       = [decimal]$case.expectedAR
        GrantRemaining    = [decimal]$case.expectedGrantRemaining
        CustodyCash       = [decimal]$case.expectedCashCustodyDelta
        NewCustomerCredit = $mint
        CreditRemaining   = [decimal]$credit - [decimal]$credit + $mint
        QuotaRemaining    = [decimal]0
        StockRemaining    = [decimal]0
        Cogs              = [decimal]10
        AppliedCash       = [decimal]$cash
        AppliedCredit     = [decimal]$credit
        ConfirmedCash     = [decimal]$actualCash
        PendingBank       = [decimal]$bankPending
        CommandCount      = [decimal]1
    }
    $actual = [ordered]@{}
    $diff = @()
    for ($i=0; $i -lt $names.Count; $i++) {
        $field = $names[$i]
        $value = [decimal]::Parse($cells[$i],[System.Globalization.NumberStyles]::Number,
                                 [System.Globalization.CultureInfo]::InvariantCulture)
        $actual[$field] = $value
        if ($value -ne $expected[$field]) {
            $diff += "$field expected=$($expected[$field]) actual=$value"
        }
    }
    $report['Ac09Cases'] += [ordered]@{
        CaseId=$id
        Expected=$expected
        Actual=$actual
        Differences=$diff
        Status=if ($diff.Count -eq 0) { 'PASS' } else { 'FAIL' }
    }
    Write-Host "AC-09 $id : $(if ($diff.Count -eq 0) { 'PASS' } else { 'FAIL' })"
    if ($diff.Count -gt 0) { throw "AC09_ORACLE_MISMATCH $id : $($diff -join '; ')" }
}

Assert-OwnedMarker $script:DbName $script:TestRunId
$negative = Run-Sql -Database $script:DbName -File (Join-Path $PSScriptRoot 'tests/ac09-negative.sql') -Label 'ac09 negative'
if ($negative -ne 'AC09_NEGATIVE_PASS') { throw "AC09_NEGATIVE_NOT_CONFIRMED: $negative" }
$report['Ac09Negative'] = 'PASS'
Assert-OwnedMarker $script:DbName $script:TestRunId
$ready = Run-Sql -Database $script:DbName -File (Join-Path $PSScriptRoot 'tests/ac09-races-setup.sql') -Label 'ac09 race setup'
if ($ready -ne 'RACES_READY') { throw "AC09_RACE_SETUP_NOT_CONFIRMED: $ready" }
foreach ($raceId in @('RACE_GRANT','RACE_QUOTA')) {
    Assert-OwnedMarker $script:DbName $script:TestRunId
    $clients = @(Invoke-ParallelSqlRace -RaceId $raceId)
    foreach ($client in $clients) { Write-Host "AC-09 $raceId $($client.Attempt): $($client.Output)" }
    $report['Ac09Races'] += [ordered]@{
        RaceId=$raceId
        Clients=@($clients)
        Status='CLIENTS_COMPLETED_PENDING_DB_ASSERT'
    }
    Write-Host "AC-09 $raceId : two independent SQL connections completed"
}
Assert-OwnedMarker $script:DbName $script:TestRunId
$assert = Run-Sql -Database $script:DbName -File (Join-Path $PSScriptRoot 'tests/ac09-races-assert.sql') -Label 'ac09 concurrency asserts'
if ($assert -ne 'TWO_INDEPENDENT_TWO_SESSION_RACES_PASS') { throw "AC09_RACE_NOT_VERIFIED: $assert" }
foreach ($race in $report['Ac09Races']) { $race['Status'] = 'PASS' }
$report['Ac09RacesActual'] = Run-Sql -Database $script:DbName -Query @"
SET NOCOUNT ON;
SELECT CONCAT(RaceId,'|',AttemptId,'|',SessionId,'|',
              CONVERT(varchar(23),StartedUtc,121),'|',
              CONVERT(varchar(23),FinishedUtc,121),'|',Outcome,'|',
              ISNULL(CONVERT(varchar(11),ErrorNumber),'0'))
FROM ac09.RaceAttempt ORDER BY RaceId,AttemptId;
"@ -Label 'ac09 concurrency trace'
Write-Host 'AC-09 oracle 5/5, fault/retry, grant race and quota race PASS'
