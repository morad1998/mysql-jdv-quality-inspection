<#
.SYNOPSIS
  Loads the database scripts into the running MySQL container, in the verified order
  (Path B2 in docs/runbooks/restore-from-backup.md), and checks the result.

.DESCRIPTION
  Run it from the repository root after "docker compose up -d" reports the container healthy.
  It reads the container name and database name from .env, never prints a password, and
  refuses to run when the database already has tables (it does not drop anything).

  Order (D = database/):
    root  : create the disposable jdv_spike database and its grant
    app   : D00_environment/01_minimum_jdv_spike.sql   (Day 0 views, jdv_spike)
    app   : D01_domain_model/01_schema.sql             (12 tables)
    root  : D01_domain_model/02_rules_triggers.sql     (5 triggers)
    app   : D01_domain_model/03_seed.sql               (demo data)
    app   : D01_domain_model/04_tests.sql              (tests; creates the baseline cards 1 and 2)
    root  : D01_domain_model/05_final_card_lock_triggers.sql
    root  : D01_domain_model/06_final_card_lock_triggers_v2.sql
    app   : D02_duality_views/17_inspection_card_dv_with_attachments.sql  (read view)
    app   : D02_duality_views/23_inspection_card_edit_dv_with_arrays.sql  (edit view)
  "root" and "app" are the MySQL accounts: the root account is needed for the triggers (see D-013).

.PARAMETER EnvFile
  Path to the .env file. Default: .env in the repository root.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/setup-database.ps1
#>
param(
  [string]$EnvFile = ''
)

$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
if ($EnvFile -eq '') { $EnvFile = Join-Path $repo '.env' }
if (-not (Test-Path -LiteralPath $EnvFile)) { Write-Host "STOP: $EnvFile not found. Copy .env.example to .env and set the two passwords."; exit 1 }

function Read-EnvValue([string]$Name, [string]$Default) {
  $line = Get-Content -LiteralPath $EnvFile | Where-Object { $_ -match ('^\s*' + $Name + '\s*=') } | Select-Object -First 1
  if (-not $line) { return $Default }
  $value = ($line -split '=', 2)[1].Trim().Trim('"')
  if ($value -eq '') { return $Default }
  return $value
}

$Container = Read-EnvValue 'MYSQL_CONTAINER_NAME' 'mysql-jdv-quality-db'
$Database  = Read-EnvValue 'MYSQL_DATABASE' 'quality_inspection'
if ($Database -ne 'quality_inspection') { Write-Host 'STOP: the scripts are written for the database name quality_inspection.'; exit 1 }

# The mysql client runs INSIDE the container; the passwords come from the container's own environment.
$rootCmd = 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot --default-character-set=utf8mb4'
$appCmd  = 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" --default-character-set=utf8mb4'

function Invoke-SqlText([string]$Sql, [string]$As, [bool]$Force, [bool]$Plain) {
  $cmd = $(if ($As -eq 'root') { $rootCmd } else { $appCmd })
  if ($Plain) { $cmd += ' --batch --skip-column-names' } else { $cmd += ' --table' }
  if ($Force) { $cmd += ' --force' }
  $out = $Sql | docker exec -i $Container sh -c $cmd 2>&1 | ForEach-Object { "$_" }
  $code = $LASTEXITCODE
  return [pscustomobject]@{ ExitCode = $code; Output = ($out -join "`n") }
}

function Invoke-SqlFile([string]$RelativePath, [string]$As, [bool]$Force) {
  $path = Join-Path $repo $RelativePath
  if (-not (Test-Path -LiteralPath $path)) { Write-Host "STOP: missing script $RelativePath"; exit 1 }
  return Invoke-SqlText (Get-Content -LiteralPath $path -Raw) $As $Force $false
}

function Fail([string]$Message, $Result) {
  Write-Host "FAIL: $Message"
  if ($Result) { Write-Host $Result.Output }
  exit 1
}

# 1. the container must be healthy
$health = docker inspect $Container --format '{{.State.Health.Status}}' 2>$null
if ($health -ne 'healthy') { Write-Host "STOP: container $Container is not healthy (status: $health). Run: docker compose up -d, and wait."; exit 1 }

# 2. the database must be empty
$r = Invoke-SqlText "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='quality_inspection';" 'root' $false $true
if ($r.ExitCode -ne 0) { Fail 'cannot query the database' $r }
if ($r.Output.Trim() -ne '0') { Write-Host "STOP: quality_inspection already has $($r.Output.Trim()) objects. This script only loads an empty database. Remove the volume (docker compose down -v) to start again."; exit 1 }

Write-Host "Loading the database scripts into $Container ..."

# 3. jdv_spike and its grant
$r = Invoke-SqlText "CREATE DATABASE IF NOT EXISTS jdv_spike CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci; GRANT ALL PRIVILEGES ON jdv_spike.* TO 'quality_app'@'%';" 'root' $false $false
if ($r.ExitCode -ne 0) { Fail 'creating jdv_spike' $r }
Write-Host '  ok  jdv_spike database and grant'

# 4. the ordered scripts. Force = continue after expected errors (only 04_tests.sql).
$steps = @(
  @('database/00_environment/01_minimum_jdv_spike.sql', 'app', $false),
  @('database/01_domain_model/01_schema.sql', 'app', $false),
  @('database/01_domain_model/02_rules_triggers.sql', 'root', $false),
  @('database/01_domain_model/03_seed.sql', 'app', $false),
  @('database/01_domain_model/04_tests.sql', 'app', $true),
  @('database/01_domain_model/05_final_card_lock_triggers.sql', 'root', $false),
  @('database/01_domain_model/06_final_card_lock_triggers_v2.sql', 'root', $false),
  @('database/02_duality_views/17_inspection_card_dv_with_attachments.sql', 'app', $false),
  @('database/02_duality_views/23_inspection_card_edit_dv_with_arrays.sql', 'app', $false)
)
foreach ($s in $steps) {
  $file = $s[0]; $as = $s[1]; $force = [bool]$s[2]
  $r = Invoke-SqlFile $file $as $force
  if ($file -like '*04_tests.sql') {
    # 04_tests.sql raises exactly eight expected errors, then must leave the baseline.
    $found = @([regex]::Matches($r.Output, 'ERROR (\d+) \(\w+\) at line \d+') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
    $want  = @('1062', '1452', '3819', '50001', '50002', '50003', '50010', '50011')
    if (($found -join ',') -ne ($want -join ',')) { Fail ("04_tests.sql raised [" + ($found -join ', ') + '] but [' + ($want -join ', ') + '] were expected') $r }
    Write-Host '  ok  database/01_domain_model/04_tests.sql  (8 expected errors: 1062 1452 3819 50001 50002 50003 50010 50011)'
  } else {
    if ($r.ExitCode -ne 0) { Fail "$file exited with code $($r.ExitCode)" $r }
    Write-Host "  ok  $file"
  }
}

# 5. verify the structure and the row counts
$q1 = @"
SELECT
 (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='quality_inspection' AND TABLE_TYPE='BASE TABLE'),
 (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS WHERE TABLE_SCHEMA='quality_inspection' AND CONSTRAINT_TYPE='FOREIGN KEY'),
 (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS WHERE TABLE_SCHEMA='quality_inspection' AND CONSTRAINT_TYPE='CHECK'),
 (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS WHERE TABLE_SCHEMA='quality_inspection' AND CONSTRAINT_TYPE='UNIQUE'),
 (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TRIGGERS WHERE TRIGGER_SCHEMA='quality_inspection'),
 (SELECT COUNT(*) FROM INFORMATION_SCHEMA.JSON_DUALITY_VIEWS WHERE TABLE_SCHEMA IN ('quality_inspection','jdv_spike') AND STATUS='valid');
"@
$r = Invoke-SqlText $q1 'root' $false $true
if ($r.ExitCode -ne 0) { Fail 'structure query' $r }
$got = (($r.Output.Trim() -split '\s+') -join ' ')
$expectedStructure = '12 18 17 11 8 4'
if ($got -ne $expectedStructure) { Fail "structure is [$got] (tables, foreign keys, CHECK, UNIQUE, triggers, valid duality views) but [$expectedStructure] was expected" $r }
Write-Host "  ok  structure: 12 tables, 18 foreign keys, 17 CHECK, 11 UNIQUE, 8 triggers, 4 valid duality views"

$tables = 'app_user', 'work_order', 'production_unit', 'inspection_section', 'measurement_definition', 'checklist_definition', 'inspection_card', 'measurement_result', 'checklist_result', 'quality_finding', 'attachment_metadata', 'audit_event'
$q2 = 'SELECT ' + (($tables | ForEach-Object { "(SELECT COUNT(*) FROM quality_inspection.$_)" }) -join ', ') + ';'
$r = Invoke-SqlText $q2 'root' $false $true
if ($r.ExitCode -ne 0) { Fail 'row count query' $r }
$got = (($r.Output.Trim() -split '\s+') -join ' ')
$expectedRows = '3 2 3 2 2 3 2 4 6 1 2 1'
if ($got -ne $expectedRows) { Fail "row counts are [$got] but [$expectedRows] were expected" $r }
Write-Host "  ok  row counts: $($tables -join ', ') = $expectedRows"

Write-Host ''
Write-Host 'DONE. The database is in the verified state. Next: cd api; npm ci; npm test; npm run test:integration'
exit 0
