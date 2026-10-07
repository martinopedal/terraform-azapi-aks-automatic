#Requires -Version 7
<#
.SYNOPSIS
    Connect to the demo VM through Azure Bastion with Microsoft Entra ID.
.DESCRIPTION
    Starts the VM if it is deallocated (it auto-shuts down daily), then opens
    a native-client RDP session through Bastion Standard (tunneling) with
    Entra ID sign-in. Requires the Azure CLI bastion extension, Reader on the
    resource group, and Virtual Machine Administrator Login on the VM.
    B2B guests cannot use Entra sign-in to VMs: they connect through Bastion
    with a local account instead (see the operations runbook).
.EXAMPLE
    ./scripts/Connect-DemoVm.ps1 -Subscription <online-subscription-id>
#>
param(
    [string]$Subscription = $env:AZURE_SUBSCRIPTION_ID_ONLINE,
    [string]$ResourceGroup = 'rg-demo-vm-online',
    [string]$VmName = 'vm-demo-copilot',
    [string]$BastionName = 'bas-demo-copilot'
)
$ErrorActionPreference = 'Stop'
if (-not $Subscription) { throw 'Set -Subscription or $env:AZURE_SUBSCRIPTION_ID_ONLINE.' }

az extension show -n bastion -o none 2>$null
if ($LASTEXITCODE) { az extension add -n bastion --only-show-errors }

$power = az vm get-instance-view -g $ResourceGroup -n $VmName --subscription $Subscription `
    --query "instanceView.statuses[?starts_with(code,'PowerState/')].code | [0]" -o tsv
if ($power -ne 'PowerState/running') {
    Write-Host "VM is $power; starting it (about 1-2 minutes)..."
    az vm start -g $ResourceGroup -n $VmName --subscription $Subscription -o none
}

$vmId = az vm show -g $ResourceGroup -n $VmName --subscription $Subscription --query id -o tsv
Write-Host 'Opening native RDP through Bastion with Microsoft Entra ID...'
az network bastion rdp --name $BastionName --resource-group $ResourceGroup --subscription $Subscription `
    --target-resource-id $vmId --enable-mfa
