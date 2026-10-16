<#
.SYNOPSIS
  Creates the shared key between this API server and the OCI function, without ever printing it.

.DESCRIPTION
  Generates a random key, stores it in the untracked .env as AI_OCI_API_KEY (the server sends it as a bearer token), and prints
  only its SHA-256 hash. The hash is what you put in the function's configuration (API_KEY_SHA256), so the function never holds the
  key itself. Refuses to run if .env is not ignored by Git. Running it again replaces the key: the function configuration then
  needs the new hash.
#>
param([string]$EnvFile = '')

$repo = Split-Path -Parent $PSScriptRoot
if ($EnvFile -eq '') { $EnvFile = Join-Path $repo '.env' }
if (-not (Test-Path -LiteralPath $EnvFile)) { Write-Host "STOP: $EnvFile not found."; exit 1 }

Push-Location $repo
git check-ignore -q -- $EnvFile 2>$null
$ignored = ($LASTEXITCODE -eq 0)
Pop-Location
if (-not $ignored) { Write-Host 'STOP: .env is not ignored by Git. Fix .gitignore first.'; exit 1 }

$bytes = New-Object byte[] 32
$rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
$rng.GetBytes($bytes)
$key = (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
if ($key.Length -ne 64) { Write-Host 'STOP: key generation failed.'; exit 1 }
$sha = New-Object System.Security.Cryptography.SHA256Managed
$hash = (($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($key)) | ForEach-Object { $_.ToString('x2') }) -join '')

$name = 'AI_OCI_API_KEY'
$existing = @(Get-Content -LiteralPath $EnvFile)
$found = $false
$out = foreach ($l in $existing) { if ($l -match ('^\s*' + $name + '\s*=')) { $found = $true; "$name=$key" } else { $l } }
if (-not $found) { $out = @($out) + "$name=$key" }
[System.IO.File]::WriteAllLines($EnvFile, [string[]]$out, (New-Object System.Text.UTF8Encoding($false)))
$key = $null

Write-Host $(if ($found) { "Replaced $name in .env" } else { "Added $name to .env" })
Write-Host 'Put this value in the function configuration as API_KEY_SHA256 (it is a hash, not the key):'
Write-Host $hash
