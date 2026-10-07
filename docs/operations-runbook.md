# Operations runbook: Online demo and demo VM

Operator guide for the two pipeline-deployed environments in the Online landing zone:

- `deployments/online`: AKS Automatic cluster, NAT Gateway, App Routing ingress, sample app (`deploy-online.yml`).
- `deployments/demo-vm`: clean Windows 11 VM behind Azure Bastion for the from-zero Copilot CLI and Squad demo (`deploy-demo-vm.yml`).

Every change goes through a pull request, the required checks, and the `online` environment gate (one required reviewer, protected branches only, admin bypass off). Nothing is applied from a laptop.

## Prerequisites (operator machine)

- PowerShell 7, Azure CLI with the `bastion` extension (`az extension add -n bastion`), GitHub CLI signed in with workflow permission on this repository.
- `az login` to the tenant, then set the subscription only in your session, never on screen or in a file:

```powershell
$env:AZURE_SUBSCRIPTION_ID_ONLINE = '<online subscription id>'
```

## Scripts

| Script | Purpose |
|---|---|
| `scripts/start-online-runner.ps1` | Starts one execution of the ephemeral, VNet-integrated self-hosted runner (Container Apps Job, no managed identity). State is private-endpoint only, so every run needs it. |
| `scripts/Invoke-GatedRun.ps1` | Dispatches a workflow, waits until GitHub has registered the environment gate, approves it, confirms the approval took effect, waits for the result (status line about every 5 minutes), and prints the plan, apply, and proof lines plus a password-leak check. |
| `scripts/Test-OnlineSecurity.ps1` | 28 read-back checks of the Online cluster: SKU, identity, network, platform, state, negative tests from the internet, app HTTPS and redirect, policy summary. Prints the app URL. Exit 1 on any failure. |
| `scripts/Test-DemoVm.ps1` | 14 checks of the demo VM: Bastion tunnel and RDP handshake, NAT egress IP, GitHub, WinGet, and npm reachability, WinGet, PowerShell 7, Entra join, and a clean start (no Git, Copilot CLI, Squad, or demo clone in any profile). Exit 1 on any failure. |
| `scripts/Connect-DemoVm.ps1` | Opens a native RDP session through Bastion with Entra sign-in and MFA. |

`Invoke-GatedRun.ps1` approves on your behalf. Run it only for a change you have already reviewed.

## Change flow (plan, review, apply, prove)

The workflow runs plan, apply, app deploy, and proof in one gated job, so the gate sits before that run's plan. Use two runs:

```powershell
# 1. Plan only. Read the "Plan:" lines and the resource addresses in the output.
./scripts/Invoke-GatedRun.ps1 -Workflow deploy-online.yml -Inputs 'apply=false' -StartRunner
# 2. Apply the reviewed change. The run re-plans: stop it if its plan differs from step 1.
./scripts/Invoke-GatedRun.ps1 -Workflow deploy-online.yml -Inputs 'apply=true' -StartRunner
# 3. Independent read-back.
./scripts/Test-OnlineSecurity.ps1
```

The demo VM uses the same pattern with `-Workflow deploy-demo-vm.yml` and `-Inputs 'action=plan'`, `'action=apply'`, `'action=recreate-vm'`, or `'action=destroy'`, followed by `./scripts/Test-DemoVm.ps1`.

A healthy steady state is `No changes. Your infrastructure matches the configuration.` on a plan-only run.

## Demo VM

- **Connect:** `./scripts/Connect-DemoVm.ps1`. Members sign in with Entra ID (`DEMO_VM_ENTRA_ADMINS` environment variable grants Virtual Machine Administrator Login).
- **Guest presenters:** B2B guests cannot use Entra sign-in to VMs. They get Reader on the Bastion (`DEMO_VM_BASTION_USERS`) and a local account. The local admin password is generated per run and never stored, so Martin resets it out of band (`az vm user update`) and shares it privately. Never put it in a file, issue, or chat log.
- **Reset to clean:** `action=recreate-vm` replaces the VM, OS disk, and VM-scoped extensions, then proves the clean state. Allow 15-20 minutes: landing-zone DeployIfNotExists policies add the Azure Monitor agent, ChangeTracking, GuestAttestation, and Azure Policy extensions after creation, which keeps the VM in `Updating` for several minutes. The workflow retries and waits for a terminal state.
- **Auto-shutdown:** 19:00 W. Europe. Start it with `az vm start` before an evening rehearsal.
- **Clean-machine demo script:** see `docs/clean-machine-demo.md` in the session repository.

## Known races and how they are handled

| Race | Symptom | Handling |
|---|---|---|
| Gate approval right after dispatch | Approval API returns success but the run stays `waiting` | `Invoke-GatedRun.ps1` waits for the pending deployment, approves, and re-checks |
| Policy extensions after VM creation | Extension or run command fails with "another operation in progress" | Retries in the workflow; `ignore_changes = [identity]` for the platform-added identity |
| One-shot proof after apply | Proof reads a VM still `Updating` | Proof waits, bounded, for a terminal provisioning state |
| OIDC assertion lifetime | AKS calls fail after a long apply | Workflow re-runs `azure/login` before cluster calls |
| Defender NSG assessment lag | New subnets show "without NSG" for up to 24 hours | Not a defect; NSGs are attached in the same apply and enforced by policy |

## Teardown (complete by 2026-10-31)

1. `./scripts/Invoke-GatedRun.ps1 -Workflow deploy-demo-vm.yml -Inputs 'action=destroy' -StartRunner`
2. `deploy-online.yml` deliberately has no destroy input, so a mis-dispatched run cannot remove the cluster before the session. After 2026-10-14, add a gated `destroy` input in a pull request (mirroring `deploy-demo-vm.yml`), review its plan-only output, then run it through `Invoke-GatedRun.ps1`.
3. **Policy-created backup vault.** `Deploy-VM-Backup` creates a Recovery Services vault (`RSVault-swedencentral-*`) in `rg-demo-vm-online` and may enroll the VM. Terraform does not own it. If the VM was enrolled: `az backup protection disable --delete-backup-data true --yes`. Soft delete is enabled with enhanced security (14 days), so the vault can be deleted only after the soft-deleted items expire. **Start teardown by 2026-10-17** to finish by the 31st.
4. Remove role assignments and the `DEMO_VM_*` environment variables, then confirm both resource groups contain nothing billable.
