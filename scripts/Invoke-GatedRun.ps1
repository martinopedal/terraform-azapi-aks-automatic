#Requires -Version 7
<#
.SYNOPSIS
    Dispatch a gated workflow, approve its environment gate once the gate
    exists, verify the approval took effect, and wait for completion.
.DESCRIPTION
    Fixes a real race: approving right after dispatch can fail because GitHub
    has not registered the pending deployment yet. This waits for the gate
    (up to 10 minutes), approves, and confirms the run left "waiting". Prints
    a status line about every 5 minutes, then the run summary lines.
    You are the approver: run it only after reading the plan you approve.
.EXAMPLE
    ./scripts/Invoke-GatedRun.ps1 -Workflow deploy-online.yml -Inputs 'apply=false' -StartRunner
    ./scripts/Invoke-GatedRun.ps1 -Workflow deploy-demo-vm.yml -Inputs 'action=recreate-vm' -StartRunner
#>
param(
    [Parameter(Mandatory)][string]$Workflow,
    [string[]]$Inputs = @(),
    [string]$Repo = 'martinopedal/terraform-azapi-aks-automatic',
    [string]$Environment = 'online',
    [string]$Comment = 'operator approval',
    [string]$Subscription = $env:AZURE_SUBSCRIPTION_ID_ONLINE,
    [switch]$StartRunner
)
$ErrorActionPreference = 'Continue'
$EnvId = gh api "repos/$Repo/environments/$Environment" --jq .id
if (-not $EnvId) { throw "Environment $Environment not found in $Repo." }
if ($StartRunner) {
    if (-not $Subscription) { throw 'Set -Subscription or $env:AZURE_SUBSCRIPTION_ID_ONLINE to start the runner.' }
    & (Join-Path $PSScriptRoot 'start-online-runner.ps1') -Subscription $Subscription 2>&1 | Where-Object { $_ -match 'Started|online' }
}
$before = gh run list --repo $Repo --workflow $Workflow --limit 1 --json databaseId --jq '.[0].databaseId'
$f = @(); foreach ($kv in $Inputs) { $f += '-f'; $f += $kv }
gh workflow run $Workflow --repo $Repo @f | Out-Null

# 1. Find the new run (not the previous one).
$id = $null
for ($i = 0; $i -lt 30 -and -not $id; $i++) {
    Start-Sleep 5
    $cand = gh run list --repo $Repo --workflow $Workflow --limit 1 --json databaseId --jq '.[0].databaseId'
    if ($cand -and $cand -ne $before) { $id = $cand }
}
if (-not $id) { throw "Run for $Workflow did not appear." }
"run $id dispatched"

# 2. Wait for the gate, approve, verify (up to 10 minutes).
$approved = $false
for ($i = 0; $i -lt 60 -and -not $approved; $i++) {
    $pending = gh api "repos/$Repo/actions/runs/$id/pending_deployments" --jq 'length' 2>$null
    if ([int]$pending -gt 0) {
        gh api --method POST "repos/$Repo/actions/runs/$id/pending_deployments" -F "environment_ids[]=$EnvId" -f state=approved -f comment=$Comment --jq '.[0].environment' 2>$null | Out-Null
        Start-Sleep 5
        $after = gh api "repos/$Repo/actions/runs/$id/pending_deployments" --jq 'length' 2>$null
        if ($after -eq '0') { $approved = $true; "approved at $(Get-Date -Format HH:mm:ss)" }
    } else {
        $st = gh run view $id --repo $Repo --json status --jq .status
        if ($st -eq 'completed') { break }
    }
    if (-not $approved) { Start-Sleep 10 }
}
if (-not $approved) { "WARNING: gate not approved (run may have no gate or ended)" }

# 3. Wait for completion, with a status line about every 5 minutes.
$t0 = Get-Date; $last = Get-Date
while ($true) {
    $r = gh run view $id --repo $Repo --json status,conclusion,jobs | ConvertFrom-Json
    if ($r.status -eq 'completed') { break }
    if (((Get-Date) - $last).TotalMinutes -ge 5) {
        $step = ($r.jobs[0].steps | Where-Object status -eq 'in_progress' | Select-Object -First 1).name
        "[{0:HH:mm}] run {1} still running ({2:N0} min) - current step: {3}" -f (Get-Date), $id, ((Get-Date) - $t0).TotalMinutes, $step
        $last = Get-Date
    }
    Start-Sleep 20
}
"== $Workflow run $id -> $($r.conclusion) after $([int]((Get-Date)-$t0).TotalMinutes) min"
$log = gh run view $id --repo $Repo --log 2>&1 | ForEach-Object { ($_ -split "`t")[-1] -replace '\x1b\[[0-9;]*m', '' -replace '\^\[\[[0-9;]*m', '' -replace '^\S+Z ', '' }
$log | Select-String -Pattern '^\s*# .* (will|must)|^Plan:|No changes\.|Apply complete|Destroy complete|Error:|"message"|^\| |::error::' | Select-Object -Unique -First 40 | ForEach-Object { $_.Line.Trim() }
"password-leak check (adminPassword literal values in log): " + ($log | Select-String -Pattern 'adminPassword\s*=\s*"[^(]').Count

