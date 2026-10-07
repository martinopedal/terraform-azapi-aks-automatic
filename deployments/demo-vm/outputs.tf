output "vm_id" {
  value = azapi_resource.vm.id
}

output "bastion_name" {
  value = azapi_resource.bastion.name
}

output "connect_command" {
  description = "Native-client RDP through Bastion with Microsoft Entra ID (tenant members)."
  value       = "az network bastion rdp --name ${azapi_resource.bastion.name} --resource-group rg-demo-vm-online --target-resource-id ${azapi_resource.vm.id} --enable-mfa"
}

output "egress_ip" {
  value = azapi_resource.pip_nat.output.properties.ipAddress
}
