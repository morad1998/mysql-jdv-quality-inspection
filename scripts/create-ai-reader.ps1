<#
.SYNOPSIS
  Creates the restricted database account ai_reader (SELECT on nine agent objects only) and stores its password in .env.

.DESCRIPTION
  Run it from the repository root after database/03_ai_boundary/01 and 02 have been applied.
  - generates a random password, or reuses AI_DB_PASSWORD from .env if it is already there
  - appends AI_DB_USER and AI_DB_PASSWORD to .env (.env is not tracked by Git)
  - creates or updates the account as MySQL root, then applies database/03_ai_boundary/05_ai_reader_grants.sql
  The password is never printed.
#>
param([string]$EnvFile = '')

$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
if ($EnvFile -eq '') { $EnvFile = Join-Path $repo '.env' }
if (-not (Test-Path -LiteralPath $EnvFile)) { Write-Host "STOP: $EnvFile not found."; exit 1 }

function Read-EnvValue([string]$Name, [string]$Default) {
  $line = Get-Content -LiteralPath $EnvFile | Where-Object { $_ -match ('^\s*' + $Name + '\s*=') } | Select-Object -First 1
  if (-not $line) { return $Default }
  $value = ($line -split '=', 2)[1].Trim().Trim('"')
  if ($value -eq '') { return $Default }
  return $value
}

$container = Read-EnvValue 'MYSQL_CONTAINER_NAME' 'mysql-jdv-quality-db'
$health = docker inspect $container --format '{{.State.Health.Status}}' 2>$null
if ($health -ne 'healthy') { Write-Host "STOP: container $container is not healthy (status: $health)."; exit 1 }

$grants = Join-Path $repo 'database\03_ai_boundary\05_ai_reader_grants.sql'
if (-not (Test-Path -LiteralPath $grants)) { Write-Host 'STOP: database/03_ai_boundary/05_ai_reader_grants.sql not found.'; exit 1 }

$pw = Read-EnvValue 'AI_DB_PASSWORD' ''
if ($pw -eq '') {
  $pw = (New-Guid).ToString('N')
  if ($pw.Length -ne 32) { Write-Host 'STOP: password generation failed.'; exit 1 }
  [System.IO.File]::AppendAllText($EnvFile, "`nAI_DB_USER=ai_reader`nAI_DB_PASSWORD=$pw`n")
  Write-Host 'Generated a password and appended AI_DB_USER and AI_DB_PASSWORD to .env'
} else {
  Write-Host 'Reusing AI_DB_PASSWORD from .env'
}

$create = "CREATE USER IF NOT EXISTS 'ai_reader'@'%' IDENTIFIED BY '$pw'; ALTER USER 'ai_reader'@'%' IDENTIFIED BY '$pw';"
$out = $create | docker exec -i $container sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot' 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL: could not create the account'; Write-Host ($out -replace [regex]::Escape($pw), '***'); exit 1 }
Write-Host '  ok  account ai_reader created or updated'

$out = Get-Content -LiteralPath $grants -Raw | docker exec -i $container sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot --table' 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL: grants'; Write-Host $out; exit 1 }
Write-Host $out
Write-Host 'DONE. Next: run the denial tests (database/03_ai_boundary/06_ai_reader_denial_tests.sql) as ai_reader.'
exit 0
