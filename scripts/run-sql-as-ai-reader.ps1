<#
.SYNOPSIS
  Runs one SQL file as the restricted account ai_reader inside the MySQL container (with --force, so expected errors do not stop it).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/run-sql-as-ai-reader.ps1 database/03_ai_boundary/06_ai_reader_denial_tests.sql
.NOTES
  The password is passed to the container as an environment variable for this one command; it is briefly visible in this
  computer's process list. Acceptable for a local demo account that can only read the agent views; not for production.
#>
param([Parameter(Mandatory = $true)][string]$SqlFile, [string]$EnvFile = '')

$repo = Split-Path -Parent $PSScriptRoot
if ($EnvFile -eq '') { $EnvFile = Join-Path $repo '.env' }
function Read-EnvValue([string]$Name, [string]$Default) {
  $line = Get-Content -LiteralPath $EnvFile | Where-Object { $_ -match ('^\s*' + $Name + '\s*=') } | Select-Object -First 1
  if (-not $line) { return $Default }
  $v = ($line -split '=', 2)[1].Trim().Trim('"'); if ($v -eq '') { return $Default }; return $v
}
$container = Read-EnvValue 'MYSQL_CONTAINER_NAME' 'mysql-jdv-quality-db'
$pw = Read-EnvValue 'AI_DB_PASSWORD' ''
if ($pw -eq '') { Write-Host 'STOP: AI_DB_PASSWORD is not in .env. Run scripts/create-ai-reader.ps1 first.'; exit 1 }
$path = $(if ([System.IO.Path]::IsPathRooted($SqlFile)) { $SqlFile } else { Join-Path (Get-Location) $SqlFile })
if (-not (Test-Path -LiteralPath $path)) { Write-Host "STOP: $path not found."; exit 1 }
Get-Content -LiteralPath $path -Raw | docker exec -i -e "MYSQL_PWD=$pw" $container mysql -uai_reader --default-character-set=utf8mb4 --force --table 2>&1
