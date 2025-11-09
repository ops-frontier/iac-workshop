# Sakura Cloud API credentials
variable "sakura_token" {
  description = "Sakura Cloud API Token"
  type        = string
  sensitive   = true
}

variable "sakura_secret" {
  description = "Sakura Cloud API Secret"
  type        = string
  sensitive   = true
}

variable "zone" {
  description = "Sakura Cloud Zone"
  type        = string
  default     = "is1a"
}

# SSH Key
variable "ssh_public_key" {
  description = "SSH Public Key for server access"
  type        = string
}

# Server configuration
variable "server_name" {
  description = "Server name"
  type        = string
  default     = "pseudo-codespaces"
}

variable "server_core" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "server_memory" {
  description = "Memory size in GB"
  type        = number
  default     = 4
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 100
}

# Domain configuration
variable "domain" {
  description = "Domain name for the service (FQDN)"
  type        = string
}

# GitHub OAuth configuration
variable "github_client_id" {
  description = "GitHub OAuth App Client ID"
  type        = string
  sensitive   = true
}

variable "github_client_secret" {
  description = "GitHub OAuth App Client Secret"
  type        = string
  sensitive   = true
}

# Network configuration
variable "network_cidr" {
  description = "Private network CIDR"
  type        = string
  default     = "192.168.0.0/24"
}
