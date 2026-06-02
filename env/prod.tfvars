location              = "swedencentral"
resource_group_name   = "rg-sreagt-dmo-swc-001"
create_resource_group = false
cluster_name          = "aks-sreagt-store-dmo-swc-001"
system_node_vm_size   = "Standard_D2s_v5"

enable_byo_vnet              = true
external_node_subnet_id      = "/subscriptions/147f910d-d9c8-40ca-8455-2ea5219765e5/resourceGroups/rg-demo-sre-agent-dnb-prod/providers/Microsoft.Network/virtualNetworks/vnet-sre-agent-dnb-prod/subnets/snet-aks-nodes"
external_apiserver_subnet_id = "/subscriptions/147f910d-d9c8-40ca-8455-2ea5219765e5/resourceGroups/rg-demo-sre-agent-dnb-prod/providers/Microsoft.Network/virtualNetworks/vnet-sre-agent-dnb-prod/subnets/snet-aks-apiserver"
external_pe_subnet_id        = "/subscriptions/147f910d-d9c8-40ca-8455-2ea5219765e5/resourceGroups/rg-demo-sre-agent-dnb-prod/providers/Microsoft.Network/virtualNetworks/vnet-sre-agent-dnb-prod/subnets/snet-private-endpoints"

enable_app_gateway_for_containers    = true
app_gateway_for_containers_subnet_id = "/subscriptions/147f910d-d9c8-40ca-8455-2ea5219765e5/resourceGroups/rg-demo-sre-agent-dnb-prod/providers/Microsoft.Network/virtualNetworks/vnet-sre-agent-dnb-prod/subnets/snet-agc"
enable_managed_nginx                 = false

egress_type         = "userDefinedRouting"
firewall_private_ip = "10.0.0.4"

pod_cidr       = "10.244.0.0/16"
service_cidr   = "10.245.0.0/16"
dns_service_ip = "10.245.0.10"

enable_private_cluster = true
private_dns_zone_id    = "/subscriptions/2be052bf-31b0-4693-8081-bf6556421934/resourceGroups/rg-hub-dns-swedencentral/providers/Microsoft.Network/privateDnsZones/privatelink.swedencentral.azmk8s.io"

create_acr      = false
create_keyvault = false

user_assigned_identity_id = "/subscriptions/147f910d-d9c8-40ca-8455-2ea5219765e5/resourceGroups/rg-sreagt-dmo-swc-001/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-sreagt-plugins-dmo-swc-001"
cluster_admin_object_ids  = ["1496c785-cd05-4d70-8166-2d66dd48f2b4"]

tags = {
  Environment        = "Demo"
  CostCenter         = "CC-SRE-001"
  Owner              = "martin.opedal@microsoft.com"
  DataClassification = "Internal"
  Compliance         = "DORA"
  Workload           = "AKS-Automatic-AGC"
  BusinessUnit       = "Azure-Specialist-Team"
  lifecycle          = "demo"
  purgeable          = "true"
  tier               = "B"
}
