locals {
  # Xray wants raw 32-byte X25519 keys in base64url without padding.
  reality_private_key = trimsuffix(replace(replace(random_bytes.reality_key.base64, "+", "-"), "/", "_"), "=")

  reality_host = split(":", var.reality_dest)[0]

  # Any 32 random bytes are a valid X25519 scalar, so the keypair can live in
  # Terraform state instead of being regenerated on every rebuild. The matching
  # public key is derived from it by scripts/links.sh, which keeps client share
  # links stable across destroy/apply cycles. The same goes for the per-device
  # UUIDs, Hysteria2 passwords and the self-signed Hysteria2 certificate.
  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    xray_clients = [
      for u in var.users : { id = random_uuid.user[u].result, flow = "xtls-rprx-vision", email = u }
    ]
    hysteria_users      = { for u in var.users : u => random_password.hysteria[u].result }
    hysteria_port       = var.hysteria_port
    hysteria_cert_pem   = tls_self_signed_cert.hysteria.cert_pem
    hysteria_key_pem    = tls_private_key.hysteria.private_key_pem
    hysteria_masquerade = "https://${local.reality_host}/"
    reality_private_key = local.reality_private_key
    reality_short_id    = random_bytes.short_id.hex
    reality_dest        = var.reality_dest
    reality_server_name = var.reality_server_names[0]
    server_names        = var.reality_server_names
    proxy_port          = var.proxy_port
  })
}

resource "random_bytes" "reality_key" {
  length = 32
}

resource "random_bytes" "short_id" {
  length = 4
}

resource "random_uuid" "user" {
  for_each = toset(var.users)
}

resource "random_password" "hysteria" {
  for_each = toset(var.users)
  length   = 24
  special  = false
}

# Hysteria2 needs a TLS certificate but the node has no domain, so a long-lived
# self-signed cert is generated here and pinned by clients via pinSHA256.
# Keeping it in state means a rebuilt node presents the same cert and existing
# client entries keep working.
resource "tls_private_key" "hysteria" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "hysteria" {
  private_key_pem = tls_private_key.hysteria.private_key_pem

  subject {
    common_name = var.reality_server_names[0]
  }
  dns_names             = var.reality_server_names
  validity_period_hours = 24 * 365 * 10
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}

resource "aws_lightsail_key_pair" "node" {
  name = "${var.name}-key"
  tags = var.tags
}

resource "aws_lightsail_static_ip" "node" {
  name = "${var.name}-ip"
}

resource "aws_lightsail_instance" "node" {
  name              = var.name
  availability_zone = var.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id
  key_pair_name     = aws_lightsail_key_pair.node.name
  user_data         = local.user_data
  ip_address_type   = "dualstack"
  tags              = var.tags
}

resource "aws_lightsail_static_ip_attachment" "node" {
  static_ip_name = aws_lightsail_static_ip.node.name
  instance_name  = aws_lightsail_instance.node.name

  # Both this attachment and the firewall below only reference the instance
  # *name*, which is stable, so replacing the instance (any user_data change
  # does that) would otherwise leave the new one detached from the static IP
  # and running Lightsail's default 22+80 firewall.
  lifecycle {
    replace_triggered_by = [aws_lightsail_instance.node]
  }
}

resource "aws_lightsail_instance_public_ports" "node" {
  instance_name = aws_lightsail_instance.node.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidrs     = var.ssh_allowed_cidrs
  }

  port_info {
    protocol  = "tcp"
    from_port = var.proxy_port
    to_port   = var.proxy_port
    cidrs     = ["0.0.0.0/0"]
  }

  port_info {
    protocol  = "udp"
    from_port = var.hysteria_port
    to_port   = var.hysteria_port
    cidrs     = ["0.0.0.0/0"]
  }

  lifecycle {
    replace_triggered_by = [aws_lightsail_instance.node]
  }
}
