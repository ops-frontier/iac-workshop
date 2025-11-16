# Get the latest Ubuntu 24.04 image (standard image)
data "sakuracloud_archive" "ubuntu" {
  os_type = "ubuntu2404"
}

# SSH Key resource
resource "sakuracloud_ssh_key" "main" {
  name       = "${var.server_name}-key"
  public_key = var.ssh_public_key
}

# Startup script (Note) for initial configuration
resource "sakuracloud_note" "startup" {
  name = "${var.server_name}-startup-script"
  
  content = templatefile("${path.module}/startup-script.sh", {
    domain               = var.domain
    github_client_id     = var.github_client_id
    github_client_secret = var.github_client_secret
  })
}

# Packet Filter (Firewall)
resource "sakuracloud_packet_filter" "main" {
  name        = "${var.server_name}-filter"
  description = "Packet filter for Workspaces"

  # Fragment packets (重要: フラグメント化されたパケットの通信のために必須)
  # 参考: https://manual.sakura.ad.jp/cloud/network/packet-filter.html
  expression {
    protocol    = "fragment"
    allow       = true
    description = "Allow all fragment packets"
  }

  # Inbound rules
  # ICMP (ping)
  expression {
    protocol    = "icmp"
    allow       = true
    description = "Allow ICMP (ping)"
  }

  # SSH (inbound)
  expression {
    protocol         = "tcp"
    destination_port = "22"
    allow            = true
    description      = "Allow SSH inbound"
  }

  # SSH (outbound - 返信パケット用)
  # ステートレスファイアウォールのため、返信パケットを明示的に許可する必要がある
  expression {
    protocol    = "tcp"
    source_port = "22"
    allow       = true
    description      = "Allow SSH outbound (reply packets)"
  }

  # HTTP (inbound)
  expression {
    protocol         = "tcp"
    destination_port = "80"
    allow            = true
    description      = "Allow HTTP inbound"
  }

  # HTTP (outbound - 返信パケット用)
  expression {
    protocol    = "tcp"
    source_port = "80"
    allow       = true
    description = "Allow HTTP outbound (reply packets)"
  }

  # HTTPS (inbound)
  expression {
    protocol         = "tcp"
    destination_port = "443"
    allow            = true
    description      = "Allow HTTPS inbound"
  }

  # HTTPS (outbound - 返信パケット用)
  expression {
    protocol    = "tcp"
    source_port = "443"
    allow       = true
    description = "Allow HTTPS outbound (reply packets)"
  }

  # Outbound rules (required for service to work)
  # HTTP outbound (for apt, wget, etc.)
  expression {
    protocol         = "tcp"
    destination_port = "80"
    allow            = true
    description      = "Allow HTTP outbound for package downloads"
  }

  # HTTPS outbound (for apt, wget, etc.)
  expression {
    protocol         = "tcp"
    destination_port = "443"
    allow            = true
    description      = "Allow HTTPS outbound for package downloads"
  }

  # DNS UDP (outbound)
  expression {
    protocol         = "udp"
    destination_port = "53"
    allow            = true
    description      = "Allow DNS UDP outbound"
  }

  # DNS UDP (inbound - 返信パケット用)
  expression {
    protocol    = "udp"
    source_port = "53"
    allow       = true
    description = "Allow DNS UDP inbound (reply packets)"
  }

  # DNS TCP (outbound)
  expression {
    protocol         = "tcp"
    destination_port = "53"
    allow            = true
    description      = "Allow DNS TCP outbound"
  }

  # DNS TCP (inbound - 返信パケット用)
  expression {
    protocol    = "tcp"
    source_port = "53"
    allow       = true
    description = "Allow DNS TCP inbound (reply packets)"
  }

  # NTP (outbound)
  expression {
    protocol         = "udp"
    destination_port = "123"
    allow            = true
    description      = "Allow NTP outbound"
  }

  # NTP (inbound - 返信パケット用)
  expression {
    protocol    = "udp"
    source_port = "123"
    allow       = true
    description = "Allow NTP inbound (reply packets)"
  }

  # Deny all other traffic
  expression {
    protocol    = "ip"
    allow       = false
    description = "Deny all other traffic"
  }
}

# Disk - 通常のアーカイブを使用
resource "sakuracloud_disk" "main" {
  name              = "${var.server_name}-disk"
  source_archive_id = data.sakuracloud_archive.ubuntu.id
  size              = var.disk_size
}

# Server
resource "sakuracloud_server" "main" {
  name        = var.server_name
  core        = var.server_core
  memory      = var.server_memory
  description = "Workspaces Server"

  disks = [sakuracloud_disk.main.id]

  # パケットフィルタを適用
  # iptablesと組み合わせて多層防御
  network_interface {
    upstream         = "shared"
    packet_filter_id = sakuracloud_packet_filter.main.id
  }

  # 通常イメージの場合、disk_edit_parameterを使用してディスクを編集
  disk_edit_parameter {
    disable_pw_auth = true
    password = var.server_password
    
    ssh_key_ids = [sakuracloud_ssh_key.main.id]
    
    # ホスト名の設定
    hostname = var.server_name
    
    # 起動時スクリプト（初期設定）
    note {
      id = sakuracloud_note.startup.id
    }
  }
}
