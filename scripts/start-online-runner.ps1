#Requires -Version 7
<#
.SYNOPSIS
    Start one ephemeral self-hosted runner execution for deploy-online.yml.

.DESCRIPTION
    The Online Terraform state account is private-only (tenant policy forces
    publicNetworkAccess=Disabled), so plan/apply run on an Azure Container
    Apps Job inside the VNet that holds the state private endpoint.

    Each run of this script:
      1. Mints a fresh repo-scoped runner registration token (valid ~1 h).
      2. Stores it as a Container Apps secret (never a plain env var).
      3. Re-asserts the pinned runner image and runner settings.
      4. Starts exactly one execution. The runner is ephemeral: it takes one
         job and exits.

    Run it, then dispatch the workflow within the replica timeout:
      ./scripts/start-online-runner.ps1
      gh workflow run deploy-online.yml -f apply=true

.NOTES
    Requires: az (logged in to the Online subscription), gh (repo admin).
#>
[CmdletBinding()]
param(
    [string]$Subscription = $env:AZURE_SUBSCRIPTION_ID_ONLINE,
    [string]$ResourceGroup = 'rg-runners-shared-personal',
    [string]$JobName = 'caj-online-demo-runner',
    [string]$Repo = 'martinopedal/terraform-azapi-aks-automatic',
    [string]$Image = 'myoung34/github-runner:2.337.0-ubuntu-noble'
)

$ErrorActionPreference = 'Stop'
if (-not $Subscription) { throw 'Set -Subscription or $env:AZURE_SUBSCRIPTION_ID_ONLINE.' }

$token = gh api --method POST "repos/$Repo/actions/runners/registration-token" --jq .token
if (-not $token) { throw 'Failed to mint runner registration token.' }

az containerapp job secret set -g $ResourceGroup -n $JobName --subscription $Subscription `
    --secrets "runner-token=$token" -o none
if ($LASTEXITCODE) { throw 'Failed to set runner-token secret.' }

az containerapp job update -g $ResourceGroup -n $JobName --subscription $Subscription `
    --image $Image `
    --replica-timeout 3600 `
    --set-env-vars "RUNNER_TOKEN=secretref:runner-token" "EPHEMERAL=true" "DISABLE_RUNNER_UPDATE=true" `
    -o none
if ($LASTEXITCODE) { throw 'Failed to update runner job.' }

$execution = az containerapp job start -g $ResourceGroup -n $JobName --subscription $Subscription --query name -o tsv
if ($LASTEXITCODE) { throw 'Failed to start runner execution.' }

Write-Host "Started $execution. Waiting for the runner to register..."
for ($i = 0; $i -lt 24; $i++) {
    $online = gh api "repos/$Repo/actions/runners" --jq '[.runners[] | select(.status=="online")] | length'
    if ([int]$online -gt 0) { Write-Host 'Runner online. Dispatch deploy-online.yml now.'; exit 0 }
    Start-Sleep -Seconds 5
}
throw 'Runner did not come online within 2 minutes. Check the job execution logs.'
