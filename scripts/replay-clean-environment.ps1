<#
.SYNOPSIS
  Rebuilds the whole project from the public GitHub repository in a throwaway container and runs every test.
  It never touches your own database: it uses its own project name, container, volume and port.

.DESCRIPTION
  1. clones the repository from GitHub into a temporary folder
  2. writes a .env with newly generated passwords, a separate container name (mysql-jdv-replay-db) and port 3308
  3. starts MySQL with the repository's compose.yaml (only the volume name is changed in the temporary copy)
  4. runs scripts/setup-database.ps1 (the verified script order and the structure and row-count checks)
  5. in api/: npm ci, npm test, npm run typecheck, npm run test:integration
  6. writes replay-report.txt (no passwords, no local paths), then removes the container, volume and temporary folder

  Needs: git, Docker Desktop (running), Node.js 24 or newer with npm, internet access (GitHub, npm registry, Docker Hub).
  Not covered: npm run examples (it needs a running server) and the web or AI parts (not built).

.PARAMETER Ref
  Branch, tag or commit to check out after cloning. Default: main.

.PARAMETER OutDir
  Folder for replay-report.txt. Default: the current folder.

.PARAMETER Keep
  Keep the container, volume and temporary folder afterwards (for debugging).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/replay-clean-environment.ps1 -OutDir D:\replay-evidence
#>
param(
  [string]$RepoUrl = 'https://github.com/morad1998/mysql-jdv-quality-inspection.git',
  [string]$Ref = 'main',
  [int]$Port = 3308,
  [string]$OutDir = '',
  [switch]$Keep
)

$ErrorActionPreference = 'Continue'
if ($OutDir -eq '') { $OutDir = (Get-Location).Path }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$reportPath = Join-Path $OutDir 'replay-report.txt'
$report = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Add-Line([string]$Text) { $report.Add($Text); Write-Host $Text }
function Pass([string]$Text) { Add-Line "PASS  $Text" }
function FailLine([string]$Text) { $script:failed = $true; Add-Line "FAIL  $Text" }
function Save-Report { [System.IO.File]::WriteAllLines($reportPath, $report, (New-Object System.Text.UTF8Encoding($false))) }

$project = 'mysql-jdv-replay'
$container = 'mysql-jdv-replay-db'
$volume = 'mysql-jdv-replay-data'
$work = Join-Path $env:TEMP ('jdv-replay-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$repoDir = Join-Path $work 'repo'
$composeUp = $false

Add-Line 'Clean-environment replay of the MySQL JDV quality-inspection project'
Add-Line ('Started (UTC): ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))

# ---- pre-checks (nothing is changed before they pass) ----
foreach ($tool in 'git', 'docker', 'node', 'npm') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { FailLine "$tool is not installed or not on PATH"; Save-Report; exit 1 }
}
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { FailLine 'Docker is not running'; Save-Report; exit 1 }
if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) { FailLine "port $Port is already in use; choose another with -Port"; Save-Report; exit 1 }
if (docker ps -a --filter "name=^$container$" --format '{{.Names}}') { FailLine "a container named $container already exists; remove it first"; Save-Report; exit 1 }
if (docker volume ls --filter "name=^$volume$" --format '{{.Name}}') { FailLine "a volume named $volume already exists; remove it first"; Save-Report; exit 1 }
Add-Line ('Tools: ' + (git --version) + '; ' + (docker --version) + '; Node ' + (node --version) + '; npm ' + (npm --version))
if ([int]((node --version).TrimStart('v').Split('.')[0]) -lt 24) { FailLine 'Node.js 24 or newer is required'; Save-Report; exit 1 }

try {
  # ---- 1. clone ----
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  git clone --quiet $RepoUrl $repoDir 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { FailLine 'git clone failed'; throw 'stop' }
  git -C $repoDir checkout --quiet $Ref 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { FailLine "git checkout $Ref failed"; throw 'stop' }
  $commit = (git -C $repoDir rev-parse HEAD).Trim()
  Pass "cloned from GitHub; commit $commit (ref $Ref)"

  # ---- 2. .env with new passwords, separate names and port ----
  $rp = (New-Guid).ToString('N'); $ap = (New-Guid).ToString('N')
  if (($rp.Length -ne 32) -or ($ap.Length -ne 32)) { FailLine 'password generation failed'; throw 'stop' }
  $lines = foreach ($l in (Get-Content -LiteralPath (Join-Path $repoDir '.env.example'))) {
    if ($l -match '^MYSQL_PASSWORD=') { "MYSQL_PASSWORD=$ap" }
    elseif ($l -match '^MYSQL_ROOT_PASSWORD=') { "MYSQL_ROOT_PASSWORD=$rp" }
    elseif ($l -match '^MYSQL_CONTAINER_NAME=') { "MYSQL_CONTAINER_NAME=$container" }
    elseif ($l -match '^MYSQL_PORT=') { "MYSQL_PORT=$Port" }
    else { $l }
  }
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllLines((Join-Path $repoDir '.env'), $lines, $utf8)
  $composePath = Join-Path $repoDir 'compose.yaml'
  $compose = [System.IO.File]::ReadAllText($composePath).Replace('mysql-jdv-quality-data', $volume)
  if ($compose.Contains('mysql-jdv-quality-data')) { FailLine 'could not rename the volume in the temporary compose file'; throw 'stop' }
  [System.IO.File]::WriteAllText($composePath, $compose, $utf8)
  Pass ".env written with new passwords, container $container, port $Port; volume renamed to $volume in the temporary compose file only"

  # ---- 3. start MySQL with the repository's compose file ----
  Push-Location $repoDir
  docker compose --project-name $project up -d 2>&1 | ForEach-Object { "$_" } | Out-Null
  $composeUp = $true
  if ($LASTEXITCODE -ne 0) { Pop-Location; FailLine 'docker compose up failed'; throw 'stop' }
  Pop-Location
  $healthy = $false
  foreach ($i in 1..60) {
    $state = docker inspect $container --format '{{.State.Status}}' 2>$null
    if ($state -ne 'running') { FailLine "container state is '$state'"; docker logs $container 2>&1 | Select-Object -Last 8 | ForEach-Object { Add-Line "      $_" }; throw 'stop' }
    if ((docker inspect $container --format '{{.State.Health.Status}}' 2>$null) -eq 'healthy') { $healthy = $true; break }
    Start-Sleep -Seconds 3
  }
  if (-not $healthy) { FailLine 'the container did not become healthy within 3 minutes'; throw 'stop' }
  $ver = ('SELECT VERSION();' | docker exec -i $container sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot --batch --skip-column-names' 2>$null)
  Pass "MySQL container healthy; server version $($ver.Trim())"

  # ---- 4. database scripts ----
  $setupOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoDir 'scripts\setup-database.ps1') -EnvFile (Join-Path $repoDir '.env') 2>&1 | ForEach-Object { "$_" }
  $setupCode = $LASTEXITCODE
  foreach ($l in $setupOut) { if ($l -match '^\s+ok ' -or $l -match '^(FAIL|STOP|DONE)') { Add-Line "      $l" } }
  if ($setupCode -ne 0) { FailLine 'scripts/setup-database.ps1 failed (see the lines above and run it again with -Keep to inspect)'; throw 'stop' }
  Pass 'database scripts loaded in the verified order; structure and row counts match'

  # ---- 5. API: install and tests ----
  Push-Location (Join-Path $repoDir 'api')
  $ciOut = npm ci 2>&1 | ForEach-Object { "$_" }
  $ciCode = $LASTEXITCODE
  if ($ciCode -ne 0) { Pop-Location; FailLine 'npm ci failed'; ($ciOut | Select-Object -Last 8) | ForEach-Object { Add-Line "      $_" }; throw 'stop' }
  $pkgs = (npm ls --depth=0 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^\+--|^`--' })
  Pass 'npm ci succeeded from package-lock.json'
  foreach ($p in $pkgs) { Add-Line "      $($p.Trim())" }

  $t = npm test 2>&1 | ForEach-Object { "$_" }
  $tc = $LASTEXITCODE
  $tests = ([regex]::Match(($t -join "`n"), 'tests (\d+)')).Groups[1].Value
  $pass = ([regex]::Match(($t -join "`n"), 'pass (\d+)')).Groups[1].Value
  $fail = ([regex]::Match(($t -join "`n"), 'fail (\d+)')).Groups[1].Value
  if ($tc -eq 0 -and $tests -eq '54' -and $pass -eq '54' -and $fail -eq '0') { Pass 'npm test: 54 tests, 54 pass, 0 fail (in-memory model)' } else { FailLine "npm test: tests $tests, pass $pass, fail $fail, exit code $tc (expected 54, 54, 0, 0)" }

  $tsc = npm run typecheck 2>&1 | ForEach-Object { "$_" }
  if ($LASTEXITCODE -eq 0 -and -not (($tsc -join "`n") -match 'error TS\d+')) { Pass 'npm run typecheck: no errors' } else { FailLine 'npm run typecheck reported errors'; ($tsc | Select-Object -Last 8) | ForEach-Object { Add-Line "      $_" } }

  $it = npm run test:integration 2>&1 | ForEach-Object { "$_" }
  $ic = $LASTEXITCODE
  $itText = ($it -join "`n")
  $tests = ([regex]::Match($itText, 'tests (\d+)')).Groups[1].Value
  $pass = ([regex]::Match($itText, 'pass (\d+)')).Groups[1].Value
  $fail = ([regex]::Match($itText, 'fail (\d+)')).Groups[1].Value
  if ($ic -eq 0 -and $tests -eq '16' -and $pass -eq '16' -and $fail -eq '0') { Pass 'npm run test:integration: 16 tests, 16 pass, 0 fail (real database)' } else { FailLine "npm run test:integration: tests $tests, pass $pass, fail $fail, exit code $ic (expected 16, 16, 0, 0)"; ($it | Select-Object -Last 25) | ForEach-Object { Add-Line "      $_" } }
  $reopen = [regex]::Match($itText, 'reopen attempt answered[^\r\n]*').Value
  if ($reopen -ne '') { Add-Line ('      ' + $reopen.Trim()) }
  Pop-Location

  # ---- 6. the replay database must be back at baseline after the integration tests ----
  $after = ('SELECT (SELECT COUNT(*) FROM inspection_card), (SELECT COUNT(*) FROM measurement_result), (SELECT COUNT(*) FROM checklist_result), (SELECT COUNT(*) FROM quality_finding), (SELECT COUNT(*) FROM attachment_metadata);' | docker exec -i $container sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot quality_inspection --batch --skip-column-names' 2>$null)
  $afterText = (($after -join ' ').Trim() -split '\s+') -join ' '
  if ($afterText -eq '2 4 6 1 2') { Pass 'replay database is back at baseline after the tests: cards 2, measurements 4, checklist 6, findings 1, attachments 2' } else { FailLine "replay database counts after the tests are [$afterText], expected [2 4 6 1 2]" }
}
catch {
  if ($_.Exception.Message -ne 'stop') { FailLine ('unexpected error: ' + $_.Exception.Message) }
}
finally {
  if (Get-Location | Where-Object { $_.Path -like "$work*" }) { Set-Location $env:TEMP }
  if (-not $Keep) {
    if ($composeUp) { Push-Location $repoDir; docker compose --project-name $project down -v 2>&1 | Out-Null; Pop-Location }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    $left = @(docker ps -a --filter "name=^$container$" --format '{{.Names}}') + @(docker volume ls --filter "name=^$volume$" --format '{{.Name}}')
    if ($left.Count -eq 0) { Add-Line 'CLEANUP  replay container, volume and temporary folder removed' } else { Add-Line ('CLEANUP  still present: ' + ($left -join ', ')) }
  } else {
    Add-Line "KEEP  container $container, volume $volume and the temporary folder were kept (remove with: docker compose --project-name $project down -v)"
  }
  Add-Line ('Finished (UTC): ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))
  if ($script:failed) { Add-Line 'RESULT: FAILED' } else { Add-Line 'RESULT: PASSED' }
  Save-Report
  Write-Host "Report: $reportPath"
}
if ($script:failed) { exit 1 } else { exit 0 }
