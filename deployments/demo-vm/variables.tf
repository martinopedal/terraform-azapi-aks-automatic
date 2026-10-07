variable "admin_password" {
  description = "Local administrator password, generated per run by the workflow. Ephemeral: never written to the plan file or state. Sent only on VM creation."
  type        = string
  sensitive   = true
  ephemeral   = true
  default     = null
}

variable "entra_admin_object_ids" {
  description = "Object IDs of tenant MEMBER users who sign in to the VM with Microsoft Entra ID (Virtual Machine Administrator Login). B2B guests cannot use Entra sign-in to VMs. Set from the GitHub environment, never committed."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "bastion_user_object_ids" {
  description = "Object IDs of users (members or guests) who may connect through Bastion (Reader on the resource group). Set from the GitHub environment, never committed."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "auto_shutdown_time" {
  description = "Daily auto-shutdown time (HHmm, W. Europe Standard Time) to cap cost."
  type        = string
  default     = "1900"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3])[0-5][0-9]$", var.auto_shutdown_time))
    error_message = "auto_shutdown_time must be HHmm, for example 1900."
  }
}
