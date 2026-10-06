variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the public API server. Set from the GitHub environment (TF_VAR_api_server_authorized_ip_ranges), never committed. Must include the deployment runner's egress IP."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.api_server_authorized_ip_ranges) > 0 && alltrue([for c in var.api_server_authorized_ip_ranges : can(cidrhost(c, 0))])
    error_message = "Provide at least one valid CIDR; an empty list would leave the public API server open to the internet."
  }
}
