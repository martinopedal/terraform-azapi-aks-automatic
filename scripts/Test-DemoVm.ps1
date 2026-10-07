#Requires -Version 7
<#
.SYNOPSIS
    Prove the demo VM is ready for the from-zero Copilot CLI and Squad demo.
.DESCRIPTION
    1. Opens a Bastion tunnel to the VM's RDP port with your Entra login and
       performs a real RDP protocol handshake (X.224 Connection Confirm).
    2. Runs read-only checks inside the VM: egress IP equals the NAT
       Gateway, GitHub/winget/npm reachable, winget present, PowerShell 7
       present, and Git, Copilot CLI and Squad NOT yet installed (a clean
       starting point). Exits 1 if any check fails.
    Run after Connect-DemoVm.ps1 has started the VM, or with the VM running.
.EXAMPLE
    ./scripts/Test-DemoVm.ps1 -Subscription <online-subscription-id>
#>
param(
    [string]$Subscription = $env:AZURE_SUBSCRIPTION_ID_ONLINE,
    [string]$ResourceGroup = 'rg-demo-vm-online',
    [string]$VmName = 'vm-demo-copilot',
    [string]$BastionName = 'bas-demo-copilot',
    [int]$LocalPort = 55389
)
$ErrorActionPreference = 'Continue'
if (-not $Subscription) { throw 'Set -Subscription or $env:AZURE_SUBSCRIPTION_ID_ONLINE.' }
$fail = 0
function Check([string]$name, [bool]$ok, [string]$detail) {
    '{0,-46} {1,-5} {2}' -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail
    if (-not $ok) { $script:fail++ }
}

# 1. Bastion tunnel + RDP handshake.
az extension show -n bastion -o none 2>$null
if ($LASTEXITCODE) { az extension add -n bastion --only-show-errors }
$vmId = az vm show -g $ResourceGroup -n $VmName --subscription $Subscription --query id -o tsv
$job = Start-Job -ScriptBlock {
    param($s, $rg, $b, $id, $p)
    az network bastion tunnel --name $b --resource-group $rg --target-resource-id $id --resource-port 3389 --port $p --subscription $s 2>&1
} -ArgumentList $Subscription, $ResourceGroup, $BastionName, $vmId, $LocalPort
$open = $false
for ($i = 0; $i -lt 20 -and -not $open; $i++) {
    Start-Sleep 3
    $open = (Test-NetConnection -ComputerName 127.0.0.1 -Port $LocalPort -WarningAction SilentlyContinue).TcpTestSucceeded
}
Check 'Bastion tunnel to VM RDP port' $open "localhost:$LocalPort"
if ($open) {
    $c = [Net.Sockets.TcpClient]::new('127.0.0.1', $LocalPort); $st = $c.GetStream(); $st.ReadTimeout = 8000
    [byte[]]$req = 0x03, 0x00, 0x00, 0x13, 0x0e, 0xe0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x08, 0x00, 0x03, 0x00, 0x00, 0x00
    $st.Write($req, 0, $req.Length); $buf = [byte[]]::new(64)
    $n = try { $st.Read($buf, 0, 64) } catch { 0 }
    Check 'RDP protocol handshake through Bastion' ($n -gt 0 -and $buf[0] -eq 0x03) "$n bytes, TPKT 0x$('{0:X2}' -f $buf[0])"
    $c.Close()
}
Stop-Job $job; Remove-Job $job -Force

# 2. In-VM checks (read-only).
$natIp = az network public-ip show -g $ResourceGroup -n pip-demo-copilot-natgw --subscription $Subscription --query ipAddress -o tsv
$tmp = Join-Path $env:TEMP 'demo-vm-check.ps1'
@'
$ProgressPreference = 'SilentlyContinue'
"EGRESS=" + (Invoke-RestMethod -Uri https://api.ipify.org -TimeoutSec 15)
foreach ($u in 'https://github.com', 'https://api.github.com', 'https://cdn.winget.microsoft.com/cache/source.msix', 'https://registry.npmjs.org') {
    try { $r = Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 15; "REACH=$u=$($r.StatusCode)" } catch { "REACH=$u=FAIL" }
}
"WINGET=" + [bool](Get-AppxPackage -AllUsers Microsoft.DesktopAppInstaller)
$pw = 'C:\Program Files\PowerShell\7\pwsh.exe'
"PWSH=" + $(if (Test-Path $pw) { & $pw -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' } else { 'missing' })
# Run Command executes as SYSTEM, which cannot see per-user WinGet installs on PATH; also scan every profile.
$pkgs = 'C:\Users\*\AppData\Local\Microsoft\WinGet\Packages'
$links = 'C:\Users\*\AppData\Local\Microsoft\WinGet\Links'
"GIT=" + [bool]((Get-Command git -ErrorAction SilentlyContinue) -or (Test-Path 'C:\Program Files\Git\cmd\git.exe') -or (Test-Path 'C:\Users\*\AppData\Local\Programs\Git\cmd\git.exe'))
"COPILOT=" + [bool]((Get-Command copilot -ErrorAction SilentlyContinue) -or (Test-Path "$pkgs\GitHub.Copilot*") -or (Test-Path "$links\copilot.exe"))
"SQUAD=" + [bool]((Get-Command squad -ErrorAction SilentlyContinue) -or (Test-Path "$pkgs\bradygaster.Squad*"))
"DEMOCLONE=" + [bool](Test-Path 'C:\Users\*\demo')
"ENTRA=" + ((dsregcmd /status | Select-String 'AzureAdJoined').Line -replace '\s', '')
'@ | Set-Content $tmp -Encoding utf8
$out = az vm run-command invoke -g $ResourceGroup -n $VmName --subscription $Subscription --command-id RunPowerShellScript --scripts "@$tmp" --query "value[0].message" -o tsv
Remove-Item $tmp
$kv = @{}; foreach ($l in ($out -split "`n")) { if ($l -match '^(\w+)=(.*)$') { $kv[$matches[1]] = $matches[2].Trim() } }
Check 'Egress through NAT Gateway' ($kv.EGRESS -eq $natIp) "vm=$($kv.EGRESS) nat=$natIp"
foreach ($l in ($out -split "`n" | Where-Object { $_ -like 'REACH=*' })) { $p = $l -split '='; Check "Reach $($p[1])" ($p[2] -eq '200') $p[2] }
Check 'winget (App Installer) present' ($kv.WINGET -eq 'True') ''
Check 'PowerShell 7 prerequisite' ($kv.PWSH -like '7.*') $kv.PWSH
Check 'Entra ID joined' ($kv.ENTRA -eq 'AzureAdJoined:YES') $kv.ENTRA
Check 'Clean start: Git not installed' ($kv.GIT -eq 'False') ''
Check 'Clean start: Copilot CLI not installed' ($kv.COPILOT -eq 'False') ''
Check 'Clean start: Squad not installed' ($kv.SQUAD -eq 'False') ''
Check 'Clean start: no demo clone left from a previous take' ($kv.DEMOCLONE -eq 'False') ''
"FAILED: $fail"
if ($fail) { exit 1 }
