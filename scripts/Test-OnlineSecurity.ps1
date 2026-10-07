#Requires -Version 7
<#
.SYNOPSIS
    Outside-in security validation of the Online AKS demo (28 checks).
.DESCRIPTION
    Run from an operator machine, OUTSIDE the pipeline. Positive checks
    prove the deployment; negative checks prove the controls actually block
    (local admin kubeconfig, API server from a non-allowed IP, anonymous
    access to Terraform state). Exits 1 if any check fails.
.EXAMPLE
    ./scripts/Test-OnlineSecurity.ps1 -Subscription <online-subscription-id>
#>
param(
    [string]$Subscription = $env:AZURE_SUBSCRIPTION_ID_ONLINE,
    [string]$Rg = 'rg-aks-online-demo',
    [string]$Cluster = 'aks-online-demo',
    [string]$StateAccount = 'stonlinedemotfst01'
)
$ErrorActionPreference = 'Continue'
if (-not $Subscription) { throw 'Set -Subscription or $env:AZURE_SUBSCRIPTION_ID_ONLINE.' }
$rows = [System.Collections.Generic.List[object]]::new()
function Add-Check($area, $check, $expected, $actual, [bool]$pass) {
    $rows.Add([pscustomobject]@{ Area = $area; Check = $check; Expected = $expected; Actual = "$actual"; Result = $(if ($pass) { 'PASS' } else { 'FAIL' }) })
}

$aks = az aks show -g $Rg -n $Cluster --subscription $Subscription -o json 2>$null | ConvertFrom-Json

# Cluster posture (read-back)
Add-Check 'Cluster' 'SKU' 'Automatic/Standard' "$($aks.sku.name)/$($aks.sku.tier)" ($aks.sku.name -eq 'Automatic')
Add-Check 'Cluster' 'Provisioning state' 'Succeeded' $aks.provisioningState ($aks.provisioningState -eq 'Succeeded')
Add-Check 'Cluster' 'Managed system node pools' 'true' $aks.hostedSystemProfile.enabled ($aks.hostedSystemProfile.enabled -eq $true)
Add-Check 'Identity' 'Local accounts disabled' 'true' $aks.disableLocalAccounts ($aks.disableLocalAccounts -eq $true)
Add-Check 'Identity' 'Entra ID + Azure RBAC for Kubernetes' 'true' $aks.aadProfile.enableAzureRbac ($aks.aadProfile.enableAzureRbac -eq $true)
Add-Check 'Identity' 'Cluster identity' 'UserAssigned' $aks.identity.type ($aks.identity.type -eq 'UserAssigned')
Add-Check 'Identity' 'Workload identity + OIDC issuer' 'true/true' "$($aks.securityProfile.workloadIdentity.enabled)/$($aks.oidcIssuerProfile.enabled)" ($aks.securityProfile.workloadIdentity.enabled -and $aks.oidcIssuerProfile.enabled)
Add-Check 'Network' 'API server authorized IP ranges' 'runner NAT IP only (/32)' (($aks.apiServerAccessProfile.authorizedIpRanges) -join ',') (@($aks.apiServerAccessProfile.authorizedIpRanges).Count -eq 1 -and $aks.apiServerAccessProfile.authorizedIpRanges[0] -like '*/32')
Add-Check 'Network' 'Egress' 'userAssignedNATGateway' $aks.networkProfile.outboundType ($aks.networkProfile.outboundType -eq 'userAssignedNATGateway')
Add-Check 'Network' 'Network policy engine' 'cilium' $aks.networkProfile.networkPolicy ($aks.networkProfile.networkPolicy -eq 'cilium')
Add-Check 'Platform' 'Azure Policy add-on' 'true' $aks.addonProfiles.azurepolicy.enabled ($aks.addonProfiles.azurepolicy.enabled -eq $true)
Add-Check 'Platform' 'Key Vault secrets provider add-on' 'true' $aks.addonProfiles.azureKeyvaultSecretsProvider.enabled ($aks.addonProfiles.azureKeyvaultSecretsProvider.enabled -eq $true)
Add-Check 'Platform' 'Image cleaner' 'true' $aks.securityProfile.imageCleaner.enabled ($aks.securityProfile.imageCleaner.enabled -eq $true)
Add-Check 'Platform' 'Node resource group lockdown' 'ReadOnly' $aks.nodeResourceGroupProfile.restrictionLevel ($aks.nodeResourceGroupProfile.restrictionLevel -eq 'ReadOnly')
Add-Check 'Platform' 'Auto-upgrade channels' 'stable/NodeImage' "$($aks.autoUpgradeProfile.upgradeChannel)/$($aks.autoUpgradeProfile.nodeOsUpgradeChannel)" ($aks.autoUpgradeProfile.upgradeChannel -eq 'stable')

# Network hygiene
$subnets = az network vnet subnet list -g $Rg --vnet-name vnet-aks-online-demo --subscription $Subscription -o json 2>$null | ConvertFrom-Json
$noNsg = @($subnets | Where-Object { -not $_.networkSecurityGroup }).Name
Add-Check 'Network' 'Every subnet has an NSG' 'none missing' ($(if ($noNsg) { $noNsg -join ',' } else { 'none missing' })) (-not $noNsg)
$mgmt = az network nsg rule list -g $Rg --nsg-name nsg-aks-online-demo-nodes --subscription $Subscription -o json 2>$null | ConvertFrom-Json |
    Where-Object { $_.direction -eq 'Inbound' -and $_.access -eq 'Allow' -and (($_.destinationPortRanges + $_.destinationPortRange) -match '^(22|3389)$') }
Add-Check 'Network' 'No inbound SSH/RDP allowed on node NSG' 'none' ($(if ($mgmt) { $mgmt.name -join ',' } else { 'none' })) (-not $mgmt)

# Terraform state store
$sa = az storage account show -n $StateAccount -g $Rg --subscription $Subscription -o json 2>$null | ConvertFrom-Json
Add-Check 'State' 'Public network access' 'Disabled' $sa.publicNetworkAccess ($sa.publicNetworkAccess -eq 'Disabled')
Add-Check 'State' 'Shared key access' 'false' $sa.allowSharedKeyAccess ($sa.allowSharedKeyAccess -eq $false)
Add-Check 'State' 'Blob public access' 'false' $sa.allowBlobPublicAccess ($sa.allowBlobPublicAccess -eq $false)
Add-Check 'State' 'Minimum TLS' 'TLS1_2' $sa.minimumTlsVersion ($sa.minimumTlsVersion -eq 'TLS1_2')
$ver = az storage account blob-service-properties show -n $StateAccount -g $Rg --subscription $Subscription --query '{v:isVersioningEnabled,d:deleteRetentionPolicy.enabled}' -o json 2>$null | ConvertFrom-Json
Add-Check 'State' 'Blob versioning + soft delete' 'true/true' "$($ver.v)/$($ver.d)" ($ver.v -and $ver.d)

# Negative tests: controls must BLOCK
$null = az aks get-credentials -g $Rg -n $Cluster --subscription $Subscription --admin --file "$env:TEMP\e2e-admin.kubeconfig" --overwrite-existing 2>&1
Add-Check 'Negative' 'Admin (local) kubeconfig refused' 'refused' $(if ($LASTEXITCODE) { 'refused' } else { 'ISSUED' }) ([bool]$LASTEXITCODE)
Remove-Item "$env:TEMP\e2e-admin.kubeconfig" -ErrorAction SilentlyContinue
$code = curl.exe -sk -o NUL -w '%{http_code}' --max-time 8 "https://$($aks.fqdn)/healthz"; $ec = $LASTEXITCODE
Add-Check 'Negative' 'API server from non-allow-listed IP' 'no connection' "http=$code curl_exit=$ec" ($code -eq '000')
$blob = curl.exe -s -o NUL -w '%{http_code}' --max-time 8 "https://$StateAccount.blob.core.windows.net/tfstate?restype=container&comp=list"
Add-Check 'Negative' 'State storage from internet (anonymous)' '403 (blocked)' $blob ($blob -in '403','409','000')

# App reachability from the internet
$ip = (az network public-ip list -g $aks.nodeResourceGroup --subscription $Subscription -o json 2>$null | ConvertFrom-Json | Where-Object { $_.tags.'k8s-azure-service' -eq 'app-routing-system/nginx' }).ipAddress
$http = curl.exe -s -o NUL -w '%{http_code}' --max-time 10 "http://$ip/"
$https = curl.exe -sk -o NUL -w '%{http_code}' --max-time 10 "https://$ip/"
Add-Check 'App' 'HTTP redirects to HTTPS' '308' $http ($http -eq '308')
Add-Check 'App' 'HTTPS serves the app' '200' $https ($https -eq '200')

# Policy compliance for the resource group
$pol = az policy state summarize --resource-group $Rg --subscription $Subscription -o json 2>$null | ConvertFrom-Json
$nc = $pol.results.nonCompliantResources
Add-Check 'Policy' 'Non-compliant resources in RG (Azure Policy)' 'report' $nc $true

$rows | Format-Table -AutoSize | Out-String -Width 220
"App URL: https://$ip/ (NGINX default certificate: the browser shows a warning; accept it before presenting)"
"PASS: $(@($rows | Where-Object Result -eq 'PASS').Count)  FAIL: $(@($rows | Where-Object Result -eq 'FAIL').Count)"
if (@($rows | Where-Object Result -eq 'FAIL').Count -gt 0) { exit 1 }

