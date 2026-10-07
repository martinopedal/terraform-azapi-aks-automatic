# =============================================================================
# Windows 11 demo VM: clean machine for installing Copilot CLI and Squad
# from zero (recorded clip and live fallback).
#
# Security posture:
#   - No public IP; RDP only through Bastion.
#   - Trusted Launch (Secure Boot + vTPM), OS patching AutomaticByOS.
#   - Microsoft Entra ID sign-in for tenant members (AADLoginForWindows);
#     local admin password is ephemeral and never stored (sensitive_body).
#   - Daily auto-shutdown; reset by re-creating the VM through the pipeline.
# Landing-zone DeployIfNotExists policies add monitoring agents, a
# platform user-assigned identity and VM backup after creation; identity is
# ignored after create so Terraform does not fight the platform.
# =============================================================================

resource "azapi_resource" "nic" {
  type      = "Microsoft.Network/networkInterfaces@2024-05-01"
  name      = "nic-${local.name}"
  location  = local.location
  parent_id = local.rg_id
  tags      = local.tags

  body = {
    properties = {
      ipConfigurations = [{
        name = "ipconfig1"
        properties = {
          privateIPAllocationMethod = "Dynamic"
          subnet                    = { id = azapi_resource.snet_vm.id }
        }
      }]
    }
  }
}

resource "azapi_resource" "vm" {
  type      = "Microsoft.Compute/virtualMachines@2024-11-01"
  name      = "vm-${local.name}"
  location  = local.location
  parent_id = local.rg_id
  tags      = local.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      # Windows 11 on Azure requires attesting an eligible license.
      licenseType = "Windows_Client"
      hardwareProfile = {
        vmSize = "Standard_D4s_v5"
      }
      storageProfile = {
        imageReference = {
          publisher = "MicrosoftWindowsDesktop"
          offer     = "windows-11"
          sku       = "win11-25h2-ent"
          version   = "latest"
        }
        osDisk = {
          name         = "osdisk-${local.name}"
          createOption = "FromImage"
          deleteOption = "Delete"
          caching      = "ReadWrite"
          managedDisk  = { storageAccountType = "StandardSSD_LRS" }
        }
      }
      osProfile = {
        computerName  = "democopilot"
        adminUsername = "demoadmin"
        windowsConfiguration = {
          provisionVMAgent       = true
          enableAutomaticUpdates = true
          patchSettings          = { patchMode = "AutomaticByOS" }
        }
        allowExtensionOperations = true
      }
      networkProfile = {
        networkInterfaces = [{
          id         = azapi_resource.nic.id
          properties = { primary = true, deleteOption = "Delete" }
        }]
      }
      securityProfile = {
        securityType = "TrustedLaunch"
        uefiSettings = { secureBootEnabled = true, vTpmEnabled = true }
      }
      diagnosticsProfile = {
        bootDiagnostics = { enabled = true }
      }
    }
  }

  # Write-only: merged into the create request, never stored in state.
  # The version map means it is sent once (on create), not on every apply.
  sensitive_body = {
    properties = {
      osProfile = {
        adminPassword = var.admin_password
      }
    }
  }
  sensitive_body_version = {
    "properties.osProfile.adminPassword" = "1"
  }

  response_export_values = ["properties.vmId"]

  lifecycle {
    # Landing-zone policies (Deploy-VM-Monitoring, Deploy-VM-ChangeTrack)
    # attach a platform user-assigned identity after creation.
    ignore_changes = [identity]

    precondition {
      condition     = var.admin_password != null
      error_message = "admin_password must be supplied by the workflow (ephemeral)."
    }
  }

  timeouts {
    create = "30m"
  }
}

resource "azapi_resource" "aad_login" {
  type      = "Microsoft.Compute/virtualMachines/extensions@2024-11-01"
  name      = "AADLoginForWindows"
  location  = local.location
  parent_id = azapi_resource.vm.id
  tags      = local.tags

  body = {
    properties = {
      publisher               = "Microsoft.Azure.ActiveDirectory"
      type                    = "AADLoginForWindows"
      typeHandlerVersion      = "2.0"
      autoUpgradeMinorVersion = true
    }
  }
}

resource "azapi_resource" "auto_shutdown" {
  type      = "Microsoft.DevTestLab/schedules@2018-09-15"
  name      = "shutdown-computevm-vm-${local.name}"
  location  = local.location
  parent_id = local.rg_id
  tags      = local.tags

  body = {
    properties = {
      status               = "Enabled"
      taskType             = "ComputeVmShutdownTask"
      dailyRecurrence      = { time = var.auto_shutdown_time }
      timeZoneId           = "W. Europe Standard Time"
      targetResourceId     = azapi_resource.vm.id
      notificationSettings = { status = "Disabled" }
    }
  }
}

# Access: members sign in with Entra ID; everyone connecting through Bastion
# needs Reader on the Bastion host, VM and NIC (resource group scope).
locals {
  vm_admin_login_role = "/subscriptions/${data.azapi_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/1c0163c0-47e6-4577-8991-ea5c82e286e4"
  reader_role         = "/subscriptions/${data.azapi_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
}

resource "azapi_resource" "ra_vm_admin_login" {
  for_each = toset(var.entra_admin_object_ids)

  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("dns", "${local.name}-vm-admin-login-${each.value}")
  parent_id = azapi_resource.vm.id

  body = {
    properties = {
      roleDefinitionId = local.vm_admin_login_role
      principalId      = each.value
      principalType    = "User"
    }
  }
}

resource "azapi_resource" "ra_reader" {
  for_each = toset(distinct(concat(var.entra_admin_object_ids, var.bastion_user_object_ids)))

  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("dns", "${local.name}-reader-${each.value}")
  parent_id = local.rg_id

  body = {
    properties = {
      roleDefinitionId = local.reader_role
      principalId      = each.value
      principalType    = "User"
    }
  }
}
