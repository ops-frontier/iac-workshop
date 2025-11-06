# cloud-init設定の修正（最終版）

## 問題

1. さくらのクラウドの公式cloud-init Ubuntuイメージは`disk_edit_parameter`非対応
2. パケットフィルタでDHCP（67/UDP, 68/UDP）を許可しないとIPアドレスが付与されない
3. Ubuntu 24.04ではpipでのシステムワイドインストールが禁止（PEP 668）

## さくらのクラウドの制約

### 重要な制約

1. **cloud-init Ubuntuイメージは`disk_edit_parameter`非対応**
   - 公式ドキュメント: https://manual.sakura.ad.jp/cloud/storage/modifydisk/about.html
   - 「パブリックアーカイブとして提供しているUbuntuなどのcloud-imgは、cloud-init専用のアーカイブとなりますので、ディスク修正は非対応」
   - `user_data`を使用する必要がある

2. **パケットフィルタでDHCPの許可が必須**
   - cloud-initイメージではIPアドレスがDHCPで自動割り当て
   - パケットフィルタで67/UDP（bootps）と68/UDP（bootpc）を許可する必要がある
   - 参考: https://manual.sakura.ad.jp/cloud/network/packet-filter.html
   - 「DHCP機能によりIPアドレスが割り当てられます。この場合、サーバ側でDHCPの通信に使用する67/UDP および 68/UDP の疎通が必要」

3. **Ubuntu 24.04のPEP 668制限**
   - `pip3 install ansible`がエラーになる
   - `apt install ansible`を使用する必要がある

4. **ネットワーク設定**
   - cloud-initでネットワーク設定を明示すると逆に問題が発生
   - Ubuntuのデフォルトdhcp設定に任せるのが最適

## 最終的な解決策

### アーキテクチャ

```
Terraform templatefile() で変数展開
         ↓
user_data (展開済みのcloud-init YAML)
         ↓
パケットフィルタ（DHCP許可）+ iptables（多層防御）
         ↓
Server (cloud-init実行、IPアドレス正常付与)
```

### 実装

#### terraform/server.tf

```hcl
# Packet Filter - DHCPを許可してIPアドレス付与を可能にする
resource "sakuracloud_packet_filter" "main" {
  name        = "${var.server_name}-filter"
  description = "Packet filter for Pseudo CodeSpaces with DHCP support"

  # DHCP (重要: cloud-initイメージでIPアドレスを取得するために必須)
  expression {
    protocol         = "udp"
    destination_port = "67"
    allow            = true
    description      = "Allow DHCP (bootps)"
  }

  expression {
    protocol         = "udp"
    destination_port = "68"
    allow            = true
    description      = "Allow DHCP (bootpc)"
  }

  # その他のルール（ICMP, SSH, HTTP, HTTPS等）
  # ...

  expression {
    protocol    = "ip"
    allow       = false
    description = "Deny all other traffic"
  }
}

# Server
resource "sakuracloud_server" "main" {
  # ...
  
  # ✅ パケットフィルタを適用（DHCP許可でIPアドレス付与が可能）
  network_interface {
    upstream         = "shared"
    packet_filter_id = sakuracloud_packet_filter.main.id
  }

  # ✅ user_dataでcloud-initを設定
  user_data = templatefile("${path.module}/cloud-init.yaml", {
    domain               = var.domain
    github_client_id     = var.github_client_id
    github_client_secret = var.github_client_secret
    ssh_public_key       = var.ssh_public_key
  })
}
```

#### terraform/cloud-init.yaml

```yaml
#cloud-config
# ✅ ネットワーク設定は不要（Ubuntuのデフォルトdhcpに任せる）

users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, docker
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - ${ssh_public_key}

chpasswd:
  expire: false
  users:
    - name: ubuntu
      password: TempPassword123!
      type: text

ssh_pwauth: true
disable_root: false

package_update: true
package_upgrade: true

packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - git
  - openssh-server
  - ansible              # ✅ aptでインストール（pipは使わない）
  - iputils-ping
  - iptables
  - iptables-persistent  # ✅ iptablesルール永続化

write_files:
  - path: /etc/environment
    content: |
      DOMAIN="${domain}"
      GITHUB_CLIENT_ID="${github_client_id}"
      GITHUB_CLIENT_SECRET="${github_client_secret}"
    append: true

runcmd:
  # ネットワーク待機
  - sleep 10
  - timeout 60 bash -c 'until ping -c 1 8.8.8.8 >/dev/null 2>&1; do sleep 2; done'
  
  - systemctl restart sshd
  
  # ✅ iptablesでファイアウォール設定
  - iptables -F
  - iptables -X
  - iptables -A INPUT -i lo -j ACCEPT
  - iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
  - iptables -A INPUT -p icmp -j ACCEPT
  - iptables -A INPUT -p tcp --dport 22 -j ACCEPT
  - iptables -A INPUT -p tcp --dport 80 -j ACCEPT
  - iptables -A INPUT -p tcp --dport 443 -j ACCEPT
  - iptables -A INPUT -j DROP
  - netfilter-persistent save
  
  # Docker installation...
```

## 変数展開の仕組み

### ステップ1: Terraform apply時

```
cloud-init.yaml (template)
    ↓
templatefile() 関数が ${domain} などを展開
    ↓
sakuracloud_note.cloud_init.content (展開済みのYAML)
```

### ステップ2: サーバー作成時

```
sakuracloud_note (ID: 12345, content: 展開済み)
    ↓
disk_edit_parameter.note.id = 12345
    ↓
ディスク編集時にcloud-initスクリプトが適用される
    ↓
サーバー起動時にcloud-init実行
```

## デプロイ手順

### 完全な再構築（必須）

`disk_edit_parameter`の変更は既存サーバーに適用されないため、完全な再構築が必要です：

```bash
cd terraform

# 1. 既存インフラを完全削除
terraform destroy -auto-approve

# 2. 新規作成
terraform apply -auto-approve

# 3. サーバー起動とcloud-init完了を待つ（重要！）
echo "Waiting for server boot and cloud-init..."
sleep 180

# 4. IPアドレス取得
SERVER_IP=$(terraform output -raw server_ip)
echo "Server IP: $SERVER_IP"
```

## 確認方法

### 1. Terraform状態確認

```bash
cd terraform

# noteリソースが作成されているか
terraform state show sakuracloud_note.cloud_init

# サーバーのdisk_edit_parameterを確認
terraform state show sakuracloud_server.main | grep -A 20 disk_edit_parameter
```

### 2. サーバーログイン

```bash
# SSH接続（3-5分待ってから）
ssh ubuntu@<IPアドレス>
# パスワード: TempPassword123!
```

### 3. cloud-init確認

```bash
# cloud-init実行状態
sudo cloud-init status
# 期待: status: done

# cloud-initログ
sudo cat /var/log/cloud-init-output.log

# 環境変数が設定されているか
cat /etc/environment
# 期待:
# DOMAIN="your-domain.com"
# GITHUB_CLIENT_ID="Ov..."
# GITHUB_CLIENT_SECRET="..."

# パスワード認証が有効か
sudo grep "^ubuntu:" /etc/shadow
# 期待: ubuntu:$6$... (ハッシュ化されたパスワード)

# SSHサービス
sudo systemctl status sshd
# 期待: active (running)

# Docker
docker --version
sudo systemctl status docker
```

## トラブルシューティング

### cloud-initが実行されていない場合

```bash
# cloud-init を手動で再実行
sudo cloud-init clean
sudo cloud-init init
sudo cloud-init modules --mode=config
sudo cloud-init modules --mode=final
```

### パスワードログインできない場合

```bash
# パスワードが設定されているか確認
sudo grep "^ubuntu:" /etc/shadow

# パスワードを手動設定
sudo passwd ubuntu
```

### 環境変数が設定されていない場合

```bash
# cloud-initログで確認
sudo cat /var/log/cloud-init-output.log | grep -A 5 "write_files"

# 手動で設定
sudo tee -a /etc/environment <<EOF
DOMAIN="your-domain.com"
GITHUB_CLIENT_ID="your-client-id"
GITHUB_CLIENT_SECRET="your-client-secret"
EOF
```

## 重要なポイント

### ✅ 正しい構成

1. **`user_data`でcloud-init設定**
   - cloud-init Ubuntuイメージでは`disk_edit_parameter`非対応
   - `templatefile()`を使用してTerraform側で変数展開
   - SSH公開鍵もテンプレート変数として渡す

2. **パケットフィルタでDHCPを許可**
   - 67/UDP（bootps）と68/UDP（bootpc）を許可
   - これによりIPアドレスが正常に付与される
   - 参考: https://manual.sakura.ad.jp/cloud/network/packet-filter.html

3. **iptablesと組み合わせて多層防御**
   - パケットフィルタ: ネットワークレベルの第1防御層
   - iptables: サーバー内部の第2防御層
   - `iptables-persistent`で再起動後も維持

4. **パッケージはaptでインストール**
   - Ubuntu 24.04では`pip3 install ansible`が失敗（PEP 668）
   - `packages`セクションに`ansible`を追加

5. **ネットワーク設定は不要**
   - cloud-initでネットワーク設定を明示すると問題が発生
   - Ubuntuのデフォルトdhcp設定に任せる

### ❌ 避けるべき構成

1. **`disk_edit_parameter`の使用**
   ```hcl
   # ❌ cloud-init Ubuntuイメージでは非対応
   disk_edit_parameter {
     note { ... }
   }
   ```

2. **パケットフィルタでDHCPを許可しない**
   ```hcl
   # ❌ IPアドレスが付与されない
   # 67/UDP, 68/UDPの許可が必須
   expression {
     protocol         = "udp"
     destination_port = "67"
     allow            = false  # ❌
   }
   ```

3. **cloud-initでネットワーク設定**
   ```yaml
   # ❌ 逆に問題が発生する
   network:
     version: 2
     ethernets:
       ens3:
         dhcp4: true
   ```

4. **pipでAnsibleインストール**
   ```yaml
   # ❌ Ubuntu 24.04ではエラー
   runcmd:
     - pip3 install ansible
   ```

## まとめ

最終的な構成：
- ✅ `user_data`でcloud-init設定（`disk_edit_parameter`は使わない）
- ✅ `templatefile()`でcloud-initスクリプトの変数を展開
- ✅ パケットフィルタでDHCP（67/UDP, 68/UDP）を許可してIPアドレス付与
- ✅ iptablesと組み合わせて多層防御（パケットフィルタ + iptables）
- ✅ パッケージは`apt`でインストール（pipは使わない）
- ✅ ネットワーク設定はUbuntuのデフォルトdhcpに任せる
- ✅ SSH鍵はテンプレート変数として渡す

この構成により：
- cloud-initスクリプトが確実にサーバーに適用される
- IPアドレスが正常に付与される（DHCPが正しく動作）
- 環境変数が正しく展開される
- パスワードとSSH鍵の両方が機能する
- 2層のファイアウォールで堅牢なセキュリティを実現
- 再起動後も設定が維持される

## 参考リンク

- [さくらのクラウド - ディスク修正について](https://manual.sakura.ad.jp/cloud/storage/modifydisk/about.html)
- [さくらのクラウド - パケットフィルタ](https://manual.sakura.ad.jp/cloud/network/packet-filter.html)
- [Qiita - さくらのクラウドでcloud-initを使う](https://qiita.com/kamaya-yuki/items/d86f0d288fed16bb0840)
- [Terraform Sakura Cloud Provider - Server](https://registry.terraform.io/providers/sacloud/sakuracloud/latest/docs/resources/server)
- [cloud-init Documentation](https://cloudinit.readthedocs.io/)
- [PEP 668 – Marking Python base environments as "externally managed"](https://peps.python.org/pep-0668/)
