# =============================================================================
# Azure Policy Exemptions
#
# This file contains policy exemptions required for AKS Automatic clusters
# deployed into Azure Landing Zones with the Microsoft Cloud Security
# Benchmark (MCSB) initiative assigned at the management group level.
#
# KNOWN ISSUE (estate-wide): The Deploy-MCSB2-Monitoring assignment at the
# alz management group includes the "allowed container images" policy
# (def febd0533-8e55-448f-b837-bd0e06f16469) with an empty regex pattern
# `^(.+){0}$` which matches nothing and therefore denies ALL images
# cluster-wide. This breaks every AKS cluster in the ALZ estate.
#
# CORRECTIVE ACTION: The regex should be fixed in the alz-prod governance
# baseline (alz mgmt group policy assignment). That is tracked in:
#   alz-avm-tf-demo/alz-prod - management group policy assignment update
#
# INTERIM WORKAROUND: This exemption allows the SRE Agent demo to deploy
# store-app manifests while the estate-wide fix is pending.
# =============================================================================

resource "azapi_resource" "policy_exemption_mcsb_k8s" {
  count     = var.enable_policy_exemption_mcsb_k8s ? 1 : 0
  type      = "Microsoft.Authorization/policyExemptions@2022-07-01-preview"
  name      = "exempt-mcsb-k8s-sreagt-store-demo"
  parent_id = local.rg_id

  body = {
    properties = {
      policyAssignmentId = "/providers/Microsoft.Management/managementGroups/alz/providers/Microsoft.Authorization/policyAssignments/Deploy-MCSB2-Monitoring"
      exemptionCategory  = "Waiver"
      displayName        = "MCSB K8s Container Image Policy - SRE Agent Demo Exemption"
      description        = <<-EOT
        Exempts the SRE Agent store-app demo from the Deploy-MCSB2-Monitoring
        policy assignment (Microsoft Cloud Security Benchmark) which includes
        the "allowed container images" policy with an empty regex ^(.+){0}$
        that denies ALL images cluster-wide.
        
        This exemption is scoped to this demo resource group only and expires
        in 30 days. The estate-wide root cause (deny-all regex at alz mgmt
        group) is being corrected in alz-avm-tf-demo/alz-prod governance
        baseline.
        
        Policy definition references exempted:
          - ensureAllowedContainerImagesInKubernetesCluster
          - kubernetesClustersShouldBeAccessibleOnlyOverHTTPSMonitoringEffect
          - allowedServicePortsInKubernetesCluster
      EOT
      expiresOn          = timeadd(timestamp(), "720h") # 30 days from apply

      policyDefinitionReferenceIds = [
        "ensureAllowedContainerImagesInKubernetesCluster",
        "kubernetesClustersShouldBeAccessibleOnlyOverHTTPSMonitoringEffect",
        "allowedServicePortsInKubernetesCluster"
      ]

      metadata = {
        createdBy   = "Terraform"
        requestedBy = "Martin Opedal (@martinopedal)"
        reason      = "Allow SRE Agent demo images while estate-wide MCSB regex is corrected"
        jira        = "N/A"
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.resource_group_name == "rg-sreagt-dmo-swc-001"
      error_message = "This policy exemption is demo-scoped and must only be applied to rg-sreagt-dmo-swc-001. For other resource groups, create a separate exemption resource."
    }
  }
}

# -----------------------------------------------------------------------------
# Policy Exemption: Deny-Priv-Esc-AKS (hostNetwork Workaround)
#
# The store-app deployment uses hostNetwork: true as a workaround for an AGC
# data-plane forwarding bug (BYO mode + Gateway API v1 + AKS Automatic + ALB
# controller 1.10.28). AGC cannot forward client HTTP traffic to Azure CNI
# Overlay pod IPs (10.244.x), even though health probes work. hostNetwork runs
# pods on node IPs (10.16.0.x), which are VNET-routable and work as backends.
#
# The Deny-Priv-Esc-AKS policy (Deny-PolicyPck-DINE assignment at alz MG)
# blocks pods with hostNetwork, privileged, or allowPrivilegeEscalation: true.
# This exemption permits the hostNetwork workaround for the SRE Agent demo only.
#
# Once Microsoft fixes the AGC forwarding bug, remove hostNetwork from the
# deployment and delete this exemption.
# -----------------------------------------------------------------------------

resource "azapi_resource" "policy_exemption_deny_priv_esc" {
  count     = var.enable_policy_exemption_deny_priv_esc ? 1 : 0
  type      = "Microsoft.Authorization/policyExemptions@2022-07-01-preview"
  name      = "exempt-denyprivesc-sreagt-store-demo"
  parent_id = local.rg_id

  body = {
    properties = {
      policyAssignmentId = "/providers/Microsoft.Management/managementGroups/alz/providers/Microsoft.Authorization/policyAssignments/Deny-PolicyPck-DINE"
      exemptionCategory  = "Waiver"
      displayName        = "Deny-Priv-Esc-AKS - SRE Agent Demo hostNetwork Workaround"
      description        = <<-EOT
        Exempts the SRE Agent store-app demo from the Deny-Priv-Esc-AKS policy
        which blocks pods with hostNetwork: true. The hostNetwork setting is a
        required workaround for an AGC data-plane forwarding bug where AGC
        cannot forward client HTTP traffic to Azure CNI Overlay pod IPs,
        despite health probes working correctly.
        
        This exemption is scoped to this demo resource group only and expires
        in 30 days. Once Microsoft resolves the AGC bug, the deployment will
        be updated to remove hostNetwork and this exemption will be deleted.
        
        Related: github.com/Azure/application-gateway-kubernetes-ingress/issues
        Policy: Deny-Priv-Esc-AKS (def c26596ff-4d70-4e6a-9a30-c2506bd2f80c)
      EOT
      expiresOn          = timeadd(timestamp(), "720h") # 30 days from apply

      policyDefinitionReferenceIds = [
        "denyprivescaks"
      ]

      metadata = {
        createdBy   = "Terraform"
        requestedBy = "Martin Opedal (@martinopedal)"
        reason      = "AGC data-plane bug workaround - hostNetwork required for VNET-routable backend IPs"
        jira        = "N/A"
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.resource_group_name == "rg-sreagt-dmo-swc-001"
      error_message = "This policy exemption is demo-scoped and must only be applied to rg-sreagt-dmo-swc-001. For other resource groups, create a separate exemption resource."
    }
  }
}
