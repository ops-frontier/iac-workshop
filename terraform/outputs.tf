output "server_ip" {
  description = "Server IP address"
  value       = sakuracloud_server.main.ip_address
}

output "internal_switch_name" {
  description = "Internal switch name"
  value       = var.internal_switch_name
}

output "internal_nic_ip" {
  description = "Internal NIC IP address in CIDR format"
  value       = var.internal_nic_ip
}

output "server_id" {
  description = "Server ID"
  value       = sakuracloud_server.main.id
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh ubuntu@${sakuracloud_server.main.ip_address}"
}

output "service_url" {
  description = "Service URL"
  value       = "https://ws.${var.domain}"
}

output "docs_url" {
  description = "Documentation URL"
  value       = "https://docs.${var.domain}"
}

output "hostname" {
  description = "Service hostname"
  value       = "ws.${var.domain}"
}

output "docs_hostname" {
  description = "Documentation hostname"
  value       = "docs.${var.domain}"
}

output "ansible_inventory" {
  description = "Ansible inventory entry"
  value       = <<-EOT
    [workspaces]
    ${sakuracloud_server.main.ip_address} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa
  EOT
}
