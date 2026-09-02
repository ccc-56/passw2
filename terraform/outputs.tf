output "public_ip" {
  description = "Static IPv4 address of the node."
  value       = aws_lightsail_static_ip.node.ip_address
}

output "users" {
  description = "Device name -> VLESS UUID."
  value       = { for u in var.users : u => random_uuid.user[u].result }
}

output "hysteria_passwords" {
  description = "Device name -> Hysteria2 password."
  value       = { for u in var.users : u => random_password.hysteria[u].result }
  sensitive   = true
}

output "hysteria_cert_pem" {
  description = "Self-signed certificate Hysteria2 serves; clients pin its SHA-256."
  value       = tls_self_signed_cert.hysteria.cert_pem
}

output "hysteria_port" {
  value = var.hysteria_port
}

output "reality_private_key" {
  description = "REALITY X25519 private key (base64url, no padding)."
  value       = local.reality_private_key
  sensitive   = true
}

output "reality_short_id" {
  description = "REALITY shortId."
  # random_bytes marks all of its attributes sensitive; a shortId is part of the
  # public share link, so unwrap it to keep the output printable.
  value = nonsensitive(random_bytes.short_id.hex)
}

output "reality_dest" {
  value = var.reality_dest
}

output "reality_server_name" {
  value = var.reality_server_names[0]
}

output "proxy_port" {
  value = var.proxy_port
}

output "ssh_private_key" {
  description = "Private key for ubuntu@public_ip."
  value       = aws_lightsail_key_pair.node.private_key
  sensitive   = true
}
