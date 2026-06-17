variable "region" {
  description = "OCI region where the Always Free resources will be created."
  type        = string
}

variable "compartment_id" {
  description = "OCID of the compartment that will contain the VM, networking, and budget."
  type        = string
}

variable "availability_domain" {
  description = "Availability domain for the VM. If null, the first availability domain in the tenancy is used."
  type        = string
  default     = null
}

variable "name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "always-free-arm"
}

variable "ssh_public_key" {
  description = "Public SSH key to install for the opc user."
  type        = string
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key used by cloud-init to join the tailnet. Prefer an ephemeral, pre-approved, reusable key scoped with tags. This value is stored in OpenTofu state."
  type        = string
  sensitive   = true
}

variable "tailscale_hostname" {
  description = "Hostname to register for this node in Tailscale."
  type        = string
  default     = null
}

variable "tailscale_enable_ssh" {
  description = "Enable Tailscale SSH when running tailscale up."
  type        = bool
  default     = true
}

variable "tailscale_udp_port" {
  description = "UDP port opened publicly for Tailscale direct WireGuard connections. Tailscale's default is 41641."
  type        = number
  default     = 41641
}

variable "create_admin_user" {
  description = "Whether cloud-init should create an additional sudo-capable default user."
  type        = bool
  default     = true
}

variable "default_user" {
  description = "Name of the sudo-capable user created by cloud-init when create_admin_user is true."
  type        = string
  default     = "admin"
}

variable "assign_public_ip" {
  description = "Whether to assign a public IPv4 address to the VM."
  type        = bool
  default     = true
}

variable "a1_ocpus" {
  description = "OCPUs for the VM.Standard.A1.Flex instance. Oracle's Always Free resources page currently lists 2 total A1 OCPUs for Always Free tenancies, so this module caps the value at 2."
  type        = number
  default     = 2

  validation {
    condition     = var.a1_ocpus == floor(var.a1_ocpus) && var.a1_ocpus >= 1 && var.a1_ocpus <= 2
    error_message = "a1_ocpus must be a whole number between 1 and 2 for this Always Free module."
  }
}

variable "a1_memory_in_gbs" {
  description = "Memory in GB for the VM.Standard.A1.Flex instance. Oracle's Always Free resources page currently lists 12 GB total A1 memory for Always Free tenancies, so this module caps the value at 12."
  type        = number
  default     = 12

  validation {
    condition     = var.a1_memory_in_gbs == floor(var.a1_memory_in_gbs) && var.a1_memory_in_gbs >= 1 && var.a1_memory_in_gbs <= 12
    error_message = "a1_memory_in_gbs must be a whole number between 1 and 12 for this Always Free module."
  }
}

variable "oracle_linux_version" {
  description = "Oracle Linux major version to use. OCI's newest matching image is selected."
  type        = string
  default     = "10"
}

variable "boot_volume_size_in_gbs" {
  description = "Boot volume size in GB. Always Free includes 200 GB total combined boot and block volume storage in the home region, so this defaults to the maximum free single boot disk for this one-VM module."
  type        = number
  default     = 200

  validation {
    condition     = var.boot_volume_size_in_gbs >= 50 && var.boot_volume_size_in_gbs <= 200
    error_message = "boot_volume_size_in_gbs must be between 50 and 200 GB for this Always Free module."
  }
}

variable "vcn_cidr" {
  description = "CIDR block for the VCN."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.0.0.0/24"
}

variable "enable_ipv6" {
  description = "Enable OCI-native IPv6 with an Oracle-allocated GUA prefix. VCN IPv6 support has no separate resource charge; internet egress still counts toward OCI outbound data transfer limits."
  type        = bool
  default     = true
}

variable "ipv6_subnet_index" {
  description = "Subnet index used to carve a /64 from the Oracle-allocated VCN /56 when enable_ipv6 is true. Valid range is 0-255."
  type        = number
  default     = 0

  validation {
    condition     = var.ipv6_subnet_index == floor(var.ipv6_subnet_index) && var.ipv6_subnet_index >= 0 && var.ipv6_subnet_index <= 255
    error_message = "ipv6_subnet_index must be a whole number between 0 and 255."
  }
}

variable "freeform_tags" {
  description = "Freeform tags to apply to created resources."
  type        = map(string)
  default     = {}
}

variable "budget_alert_email" {
  description = "Email address to receive budget alerts if any actual cost appears."
  type        = string
  default     = "example@gmail.com"
}

variable "budget_amount" {
  description = "Monthly budget amount in USD. The alert fires at the absolute threshold below."
  type        = number
  default     = 1
}

variable "budget_alert_threshold" {
  description = "Absolute USD actual-spend threshold for the budget alert. OCI budgets require a positive threshold, so 0.01 approximates 'any cost'."
  type        = number
  default     = 0.01
}

variable "disable_agent_plugin_names" {
  description = "Oracle Cloud Agent plugins to explicitly disable on the instance."
  type        = set(string)
  default = [
    "Bastion",
    "Block Volume Management",
    "Compute Instance Monitoring",
    "Compute Instance Run Command",
    "Custom Logs Monitoring",
    "Management Agent",
    "OS Management Service Agent",
    "Vulnerability Scanning"
  ]
}
