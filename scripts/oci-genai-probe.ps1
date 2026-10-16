<#
.SYNOPSIS
  OCI step 1: one small chat call to OCI Generative AI from this laptop, through the personal-profile wrapper.
  It proves three things before anything is deployed: the profile is the right account, the region offers the model,
  and the account may call it on demand.

.DESCRIPTION
  Every OCI call goes through D:\ov\ocip.ps1, which adds the personal config file and the PERSONAL profile itself.
  This script never reads an OCI config file and never chooses a profile.
  Request format: COHERE (chat-result chat-cohere-chat-request), on-demand serving, max 50 output tokens.
  Output: the model's reply text and the token usage only.
  This is a PAID inference call (a few dozen tokens).

.PARAMETER Region
  Generative AI region. The model must be offered on demand there.

.PARAMETER ModelId
  On-demand Cohere chat model id.

.PARAMETER CompartmentName
  Name of the compartment to bill the call to. Its OCID is looked up through the wrapper.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/oci-genai-probe.ps1
#>
param(
  [string]$Region = 'me-riyadh-1',
  [string]$ModelId = 'cohere.command-a-03-2025',
  [string]$CompartmentName = 'mysql-jdv-quality-inspection',
  [string]$Message = 'Reply with OK.',
  [int]$MaxTokens = 50
)

$ErrorActionPreference = 'Continue'
$ocip = 'D:\ov\ocip.ps1'
if (-not (Test-Path -LiteralPath $ocip)) { Write-Host "STOP: $ocip not found."; exit 1 }

# Runs the wrapper and keeps stdout (JSON) apart from stderr (warnings and errors).
function Invoke-Ocip([string[]]$CliArgs) {
  $out = New-Object System.Collections.Generic.List[string]
  $err = New-Object System.Collections.Generic.List[string]
  & $ocip @CliArgs 2>&1 | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) { $err.Add("$_") } else { $out.Add("$_") }
  }
  return @{ Code = $LASTEXITCODE; Out = ($out -join "`n"); Err = ($err -join "`n") }
}

function Write-Short([string]$Text) { Write-Host ($Text.Substring(0, [Math]::Min(800, $Text.Length))) }

# 1. Compartment OCID, by name, anywhere in the tenancy.
$r = Invoke-Ocip @('iam', 'compartment', 'list', '--all', '--compartment-id-in-subtree', 'true',
                   '--name', $CompartmentName, '--lifecycle-state', 'ACTIVE', '--query', 'data[0].id', '--raw-output')
$compartmentId = $r.Out.Trim()
if ($r.Code -ne 0 -or $compartmentId -notlike 'ocid1.compartment.*') {
  Write-Host "STOP: could not find the active compartment '$CompartmentName' (exit code $($r.Code))."
  if ($r.Err) { Write-Short $r.Err }
  exit 1
}

# 2. One on-demand Cohere chat call.
$work = Join-Path $env:TEMP ('oci-probe-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
  $servingFile = Join-Path $work 'serving-mode.json'
  $serving = @{ servingType = 'ON_DEMAND'; modelId = $ModelId } | ConvertTo-Json -Compress
  [System.IO.File]::WriteAllText($servingFile, $serving, (New-Object System.Text.UTF8Encoding($false)))

  Write-Host "Region: $Region   Model: $ModelId   Compartment: $CompartmentName"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $r = Invoke-Ocip @('generative-ai-inference', 'chat-result', 'chat-cohere-chat-request',
                     '--region', $Region,
                     '--compartment-id', $compartmentId,
                     '--serving-mode', "file://$servingFile",
                     '--chat-request-message', $Message,
                     '--chat-request-max-tokens', "$MaxTokens")
  $sw.Stop()

  if ($r.Code -ne 0) {
    Write-Host "FAIL  the call did not succeed (exit code $($r.Code)). The service said:"
    Write-Short $r.Err
    Write-Host ''
    Write-Host 'Common causes: 404 = model not offered on demand in this region, or wrong compartment; 401 or 403 = account or policy;'
    Write-Host '400 = request format does not suit this model.'
    exit 1
  }

  try { $resp = ($r.Out | ConvertFrom-Json).data.'chat-response' } catch { $resp = $null }
  if (-not $resp -or -not $resp.text) { Write-Host 'NOTE  the call succeeded but no reply text was found in the response.'; exit 2 }

  Write-Host ("Reply ({0} ms): {1}" -f $sw.ElapsedMilliseconds, $resp.text.Trim())
  $u = $resp.usage
  if ($u) {
    Write-Host ("Tokens: prompt {0}, completion {1}, total {2}" -f $u.'prompt-tokens', $u.'completion-tokens', $u.'total-tokens')
  } else {
    Write-Host 'Tokens: the response carried no usage block.'
  }
  exit 0
}
finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
