# SQL-02 AC-03 disposable scratch runner; PowerShell 5.1+ and sqlcmd.
# Requires Windows integrated authentication (-E) and CREATE/DROP DATABASE permission.
# Each run creates a new database; existing targets are NEVER reset or reused.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ServerInstance,
    [string]$ScratchDatabase,
    [string]$SqlcmdPath = 'sqlcmd',
    [switch]$KeepDatabase,
    [switch]$IncludeSql03A,
    [switch]$IncludeSql03B,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'test-results')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:TestRunId = [guid]::NewGuid().ToString('D')
$script:ExitStatus = 1
$script:CreatedDatabase = $false
$script:MarkerCreated = $false
$script:DbName = if ([string]::IsNullOrWhiteSpace($ScratchDatabase)) {
    'fmcg_sql02_' + [guid]::NewGuid().ToString('N')
} else { $ScratchDatabase }
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$logPath = Join-Path $OutputDirectory ($script:TestRunId + '.json')
$report = [ordered]@{
    TestRunId = $script:TestRunId
    Status = 'NOT_RUN'
    SqlId = 'SQL-02'
    AcId = 'AC-03'
    Database = $script:DbName
    ServerArgument = $ServerInstance
    StartedUtc = [datetime]::UtcNow.ToString('o')
    Baseline = 'business/reference-data/expected-results/golden-oracles.json#AC-03'
    Engine = $null
    CompatibilityLevel = $null
    GuardChecks = @()
    Checkpoints = @()
    Error = $null
    Cleanup = 'NOT_ATTEMPTED'
}

function Run-Sql {
    param([string]$Database,[string]$Query,[string]$File,[string]$Label)
    $arguments = @('-S',$ServerInstance,'-E','-d',$Database,'-b','-V','11',
                   '-r','1','-W','-h','-1','-w','65535')
    if (-not [string]::IsNullOrEmpty($File)) {
        $arguments += @('-i',$File)
    } elseif (-not [string]::IsNullOrEmpty($Query)) {
        $arguments += @('-Q',$Query)
    } else { throw 'Run-Sql requires a query or input file' }
    $messages = @(& $SqlcmdPath @arguments 2>&1 | ForEach-Object { $_.ToString() })
    $code = $LASTEXITCODE
    $value = ($messages -join [Environment]::NewLine).Trim()
    if ($code -ne 0) { throw "sqlcmd [$Label] exit=$code database=$Database : $value" }
    return $value
}
function Assert-ScratchName {
    param([string]$Name)
    if ($Name -notmatch '^fmcg_sql02_[0-9a-f]{32}$') {
        throw "UNSAFE_TARGET: scratch database must match fmcg_sql02_<32 lowercase hex digits>; got [$Name]"
    }
    if ($Name -in @('master','model','msdb','tempdb')) {
        throw "UNSAFE_TARGET: system database [$Name]"
    }
}
function Assert-FreshTarget {
    param([string]$Name)
    Assert-ScratchName $Name
    $query = "SET NOCOUNT ON; IF DB_ID(N'$Name') IS NOT NULL THROW 52001, 'SCRATCH_TARGET_EXISTS_REFUSE_RESET', 1; SELECT 'FRESH';"
    $answer = Run-Sql -Database 'master' -Query $query -Label 'preflight no-existing-db'
    if ($answer -ne 'FRESH') { throw "UNSAFE_TARGET: nonfresh target [$Name]: $answer" }
}
function Assert-OwnedMarker {
    param([string]$Name,[string]$Nonce)
    Assert-ScratchName $Name
    $query = @"
SET NOCOUNT ON;
IF DB_NAME()<>N'$Name' THROW 52002, 'WRONG_DATABASE_CONTEXT', 1;
IF OBJECT_ID(N'dbo.__Ac03ScratchMarker',N'U') IS NULL THROW 52003, 'MISSING_SCRATCH_MARKER', 1;
IF NOT EXISTS (
 SELECT 1 FROM dbo.__Ac03ScratchMarker
 WHERE Harness='fmcg-distribution-sql/SQL-02/AC-03'
   AND DatabaseName=DB_NAME()
   AND InstanceName=CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))
   AND RunnerNonce=CONVERT(uniqueidentifier,'$Nonce')
) THROW 52004, 'UNOWNED_SCRATCH_REFUSE_MUTATION', 1;
SELECT 'OWNED';
"@
    $answer = Run-Sql -Database $Name -Query $query -Label 'ownership guard'
    if ($answer -ne 'OWNED') { throw "UNOWNED_SCRATCH: $Name" }
}
function Drop-OwnedDatabase {
    param([string]$Name,[string]$Nonce)
    Assert-OwnedMarker $Name $Nonce
    # Repeat ownership verification in the SAME master batch immediately before DROP.
    $query = @"
SET NOCOUNT ON;
DECLARE @Trusted bit=0;
EXEC [$Name].sys.sp_executesql
 N'IF OBJECT_ID(N''dbo.__Ac03ScratchMarker'',N''U'') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.__Ac03ScratchMarker
    WHERE Harness=''fmcg-distribution-sql/SQL-02/AC-03''
      AND DatabaseName=DB_NAME()
      AND InstanceName=CONVERT(nvarchar(128),SERVERPROPERTY(''ServerName''))
      AND RunnerNonce=CONVERT(uniqueidentifier,''$Nonce''))
    SET @p=1;',
 N'@p bit OUTPUT',@p=@Trusted OUTPUT;
IF @Trusted<>1 THROW 52005, 'UNOWNED_SCRATCH_REFUSE_DROP', 1;
ALTER DATABASE [$Name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [$Name];
SELECT 'DROPPED';
"@
    $answer = Run-Sql -Database 'master' -Query $query -Label 'guarded scratch cleanup'
    if ($answer -ne 'DROPPED') { throw "SCRATCH_CLEANUP_UNCONFIRMED: $answer" }
}

try {
    if ([string]::IsNullOrWhiteSpace($ServerInstance) -or
        $ServerInstance.Contains('*') -or $ServerInstance.Contains('?')) {
        throw 'An explicit, concrete -ServerInstance is required.'
    }
    Get-Command $SqlcmdPath -ErrorAction Stop | Out-Null
    Assert-ScratchName $script:DbName
    $identityQuery = @"
SET NOCOUNT ON;
SELECT CONVERT(varchar(128),SERVERPROPERTY('ServerName'))+'|'+DB_NAME()
       +'|'+CONVERT(varchar(128),SERVERPROPERTY('ProductVersion'));
"@
    $identity = Run-Sql -Database 'master' -Query $identityQuery -Label 'server/instance identity'
    $parts = $identity.Split('|')
    if ($parts.Count -ne 3 -or $parts[1] -ne 'master') {
        throw "Unsafe or ambiguous server response: [$identity]"
    }
    if ([int]($parts[2].Split('.')[0]) -lt 14) {
        throw "SQL Server 2017+ required; server reports $($parts[2])"
    }
    $report.Engine = $identity
    Assert-FreshTarget $script:DbName
    $report.GuardChecks += 'PRECREATE_FRESH_TARGET_PASS'

    # Name has been regex validated, master verified and DB_ID checked; no existing DB is touched.
    $create = "SET NOCOUNT ON; IF DB_ID(N'$($script:DbName)') IS NOT NULL THROW 52006, 'DB_EXISTS_RACE_REFUSE', 1; CREATE DATABASE [$($script:DbName)]; SELECT 'CREATED';"
    $created = Run-Sql -Database 'master' -Query $create -Label 'create new scratch only'
    if ($created -ne 'CREATED') { throw "Scratch create not confirmed: [$created]" }
    $script:CreatedDatabase = $true

    $mark = @"
SET NOCOUNT ON;
CREATE TABLE dbo.__Ac03ScratchMarker(
 Harness varchar(100) NOT NULL,
 DatabaseName sysname NOT NULL,
 InstanceName nvarchar(128) NOT NULL,
 RunnerNonce uniqueidentifier NOT NULL,
 CreatedAtUtc datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);
INSERT dbo.__Ac03ScratchMarker(Harness,DatabaseName,InstanceName,RunnerNonce)
VALUES('fmcg-distribution-sql/SQL-02/AC-03',DB_NAME(),
       CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')),
       CONVERT(uniqueidentifier,'$($script:TestRunId)'));
SELECT 'MARKED';
"@
    $marked = Run-Sql -Database $script:DbName -Query $mark -Label 'write new scratch marker'
    if ($marked -ne 'MARKED') { throw "Scratch marker creation not confirmed: [$marked]" }
    $script:MarkerCreated = $true
    Assert-OwnedMarker $script:DbName $script:TestRunId
    $report.GuardChecks += 'INSTANCE_DB_MARKER_NONCE_PASS'

    # Negative guard probes never execute a destructive statement.
    $denied = 0
    try { Assert-FreshTarget 'master' } catch { $denied++ }
    try { Assert-FreshTarget $script:DbName } catch { $denied++ }
    try { Assert-OwnedMarker $script:DbName ([guid]::Empty.ToString('D')) } catch { $denied++ }
    if ($denied -ne 3) { throw "GUARD_NEGATIVE_PROBES_FAILED: expected 3 denials, got $denied" }
    $report.GuardChecks += 'MASTER_EXISTING_TARGET_WRONG_NONCE_DENIED'

    $versionQuery = @"
SET NOCOUNT ON;
SELECT CONVERT(varchar(10),compatibility_level) FROM sys.databases WHERE name=DB_NAME();
"@
    $version = Run-Sql -Database $script:DbName -Query $versionQuery -Label 'compatibility'
    $report.CompatibilityLevel = [int]$version
    if ($report.CompatibilityLevel -lt 140) {
        throw "SQL compatibility level 140+ required; actual=$version"
    }
    Write-Host "SQL Server engine: $identity; scratch compatibility level: $version"

    foreach ($file in @(
        'schema/001_ac03.sql',
        'schema/002_commands.sql',
        'schema/003_assert_invariants.sql',
        'seed/ac03.sql',
        'scenarios/ac03.sql',
        'tests/negative.sql'
    )) {
        Assert-OwnedMarker $script:DbName $script:TestRunId
        $path = Join-Path $PSScriptRoot ($file.Replace('/', [IO.Path]::DirectorySeparatorChar))
        [void](Run-Sql -Database $script:DbName -File $path -Label $file)
    }

    # One source of expected data, read at runtime and never copied into SQL.
    $oracleFile = Join-Path $root 'business/reference-data/expected-results/golden-oracles.json'
    $json = Get-Content -LiteralPath $oracleFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $oracle = $json.PSObject.Properties['AC-03'].Value
    if ($oracle.unit -ne 'SYNTHETIC_UNITLESS' -or $oracle.invoiceEligible -ne $false) {
        throw 'AC03_ORACLE_UNIT_OR_INVOICE_STATUS_UNEXPECTED'
    }
    $columnNames = @('step','mainQty','tripQty','soldQty','mainCost','tripCost','cogs',
                     'aHold','bQuota','arA','arB','custody','fund')
    if (($oracle.cols -join ',') -ne ($columnNames -join ',') -or $oracle.steps.Count -ne 7) {
        throw 'AC03_ORACLE_SHAPE_CHANGED'
    }
    $fieldsSql = @('Step')
    $fieldsSql += @('MainQty','TripQty','SoldQty','MainCost','TripCost','Cogs',
                    'AHold','BQuota','ArA','ArB','Custody','Fund') |
        ForEach-Object { "CONVERT(varchar(80),[$_])" }
    $exportSql = 'SET NOCOUNT ON; SELECT ' + ($fieldsSql -join ',') +
                 ' FROM ac03.CheckpointActual ORDER BY StepOrdinal;'
    # sqlcmd -s uses a delimiter between the 13 string columns.
    $sqlargs = @('-S',$ServerInstance,'-E','-d',$script:DbName,'-b','-V','11','-r','1',
                 '-W','-h','-1','-w','65535','-s','|','-Q',$exportSql)
    $lines = @(& $SqlcmdPath @sqlargs 2>&1 | ForEach-Object { $_.ToString() })
    if ($LASTEXITCODE -ne 0) { throw "SQL actual export failed: $($lines -join '; ')" }
    $rows = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($rows.Count -ne 7) { throw "Expected 7 SQL rows, got $($rows.Count): $($rows -join '; ')" }

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    for ($i=0; $i -lt 7; $i++) {
        $cells = @($rows[$i].Split('|') | ForEach-Object { $_.Trim() })
        $expected = $oracle.steps[$i]
        if ($cells.Count -ne 13 -or $expected.Count -ne 13) {
            throw "Wrong AC03 width at checkpoint index $i"
        }
        $actualRow = [ordered]@{ step=$cells[0] }
        $diff = @()
        if ($cells[0] -cne [string]$expected[0]) {
            $diff += "step expected=$($expected[0]) actual=$($cells[0])"
        }
        for ($j=1; $j -lt 13; $j++) {
            $actualValue = [decimal]::Parse($cells[$j],
                  [System.Globalization.NumberStyles]::Number,$culture)
            $expectedValue = [decimal]$expected[$j]
            $actualRow[$columnNames[$j]] = $actualValue
            if ($actualValue -ne $expectedValue) {
                $diff += "$($columnNames[$j]) expected=$expectedValue actual=$actualValue"
            }
        }
        $report.Checkpoints += [ordered]@{
            Step=$actualRow.step
            Expected=$expected
            Actual=$actualRow
            Status=if($diff.Count -eq 0){'PASS'}else{'FAIL'}
            Differences=$diff
        }
        Write-Host "$($actualRow.step) : $(if($diff.Count -eq 0){'PASS'}else{'FAIL'})"
        if ($diff.Count -gt 0) { throw "AC03 oracle mismatch at $($actualRow.step): $($diff -join '; ')" }
    }
    if ($IncludeSql03A) {
        Assert-OwnedMarker $script:DbName $script:TestRunId
        . (Join-Path $PSScriptRoot 'include-ac09.ps1')
    }
    if ($IncludeSql03B) {
        Assert-OwnedMarker $script:DbName $script:TestRunId
        . (Join-Path $PSScriptRoot 'include-ac21.ps1')
    }
    $report.Status = 'PASS'
    $script:ExitStatus = 0
} catch {
    $report.Status = 'FAIL'
    $report.Error = $_.Exception.Message
    Write-Error -ErrorAction Continue "SQL-02 AC-03 FAIL: $($report.Error)"
} finally {
    if ($script:CreatedDatabase -and -not $KeepDatabase) {
        if (-not $script:MarkerCreated) {
            $report.Cleanup = 'BLOCKED_MISSING_MARKER_SCRATCH_RETAINED'
            $script:ExitStatus = 1
        } else {
            try {
                Drop-OwnedDatabase $script:DbName $script:TestRunId
                $report.Cleanup = 'GUARDED_DROP_PASS'
            } catch {
                $report.Cleanup = 'FAILED_SCRATCH_RETAINED'
                $report.Error = "$($report.Error); cleanup: $($_.Exception.Message)"
                $script:ExitStatus = 1
            }
        }
    } elseif ($script:CreatedDatabase) {
        $report.Cleanup = 'KEPT_BY_REQUEST'
    } else {
        $report.Cleanup = 'NO_DATABASE_CREATED'
    }
    if ($script:ExitStatus -ne 0) { $report.Status = 'FAIL' }
    $report.EndedUtc = [datetime]::UtcNow.ToString('o')
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $logPath -Encoding UTF8
    Write-Host "TestRunId: $($script:TestRunId)"
    Write-Host "Evidence: $logPath"
    Write-Host "Database: $($script:DbName) ($($report.Cleanup))"
}
exit $script:ExitStatus
