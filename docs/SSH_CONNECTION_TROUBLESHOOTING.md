# さくらのクラウド SSH接続トラブルシューティング

## 問題: IPアドレスが付与されない、SSH接続タイムアウト

### 症状

```bash
ssh ubuntu@<IPアドレス>
# ssh: connect to host <IP> port 22: Connection timed out

ping <IPアドレス>
# Request timeout
```

- Webコンソールでログイン可能
- `ip a show` でIPv4アドレスが表示されない
- 名前解決ができない（`ping google.com` が失敗）

### 根本原因

**さくらのクラウドのcloud-init対応Ubuntuイメージでは、起動時にパケットフィルタが設定されている場合、DHCPの通信が必要**

重要な発見：
1. cloud-initイメージではIPアドレスがDHCPで自動割り当てされる
2. パケットフィルタでDHCP（67/UDP, 68/UDP）の通信を許可する必要がある
3. DHCPが許可されていないとIPアドレスが付与されない
4. 参考: https://manual.sakura.ad.jp/cloud/network/packet-filter.html

### 解決策

**パケットフィルタでDHCPを許可し、iptablesと組み合わせて多層防御**

1. **Terraform設定の修正** (`terraform/server.tf`)
   - パケットフィルタに67/UDP, 68/UDPを追加
   - パケットフィルタを`network_interface`に設定

2. **cloud-init設定** (`terraform/cloud-init.yaml`)
   - iptablesでも追加のフィルタリング（多層防御）
   - `iptables-persistent`で永続化

3. **その他の問題**
   - Ubuntu 24.04ではpipでのシステムワイドインストールが禁止（PEP 668）
   - Ansibleは`apt`でインストールする必要がある

## 解決手順（修正済みの設定を使用）

### 手順1: 完全な再デプロイ

DHCPを許可したパケットフィルタとiptablesの多層防御で再構築します：

```bash
# 完全再デプロイスクリプトを使用
./scripts/full-redeploy.sh
```

または手動で：

```bash
# 1. 既存のインフラを削除
cd terraform
terraform destroy -auto-approve

# 2. 再デプロイ（DHCP対応パケットフィルタ + iptables）
terraform apply -auto-approve

# 3. サーバー起動を待つ（5-10分）
# IPアドレスが正常に付与されるはず

# 4. SSH接続テスト
ssh ubuntu@$(terraform output -raw server_ip)
# パスワード: TempPassword123!
```

### 手順2: IPアドレスとファイアウォールの確認

SSH接続後、IPアドレスとファイアウォール設定を確認：

```bash
# IPv4アドレスが付与されているか確認
ip -4 a show ens3

# ルーティングテーブルの確認
ip route show

# 名前解決のテスト
ping -c 3 google.com

# iptablesルールの確認（内側の防御）
sudo iptables -L -n -v

# パケットフィルタの確認（外側の防御）
# Webコンソールで確認: https://secure.sakura.ad.jp/cloud/
```

### 手順3: 多層防御の確認

2つのファイアウォール層が動作していることを確認：

**第1層: さくらのクラウド パケットフィルタ**
- DHCP (67/UDP, 68/UDP): 許可
- ICMP: 許可
- SSH (22/TCP): 許可
- HTTP (80/TCP): 許可
- HTTPS (443/TCP): 許可
- その他: 拒否

**第2層: iptables（サーバー内）**
- ループバック: 許可
- 確立済み接続: 許可
- ICMP: 許可
- SSH (22/TCP): 許可
- HTTP (80/TCP): 許可
- HTTPS (443/TCP): 許可
- その他: 拒否

```bash
# iptablesルールを表示
sudo iptables -L INPUT -n -v

# 保存されたルールを確認
sudo cat /etc/iptables/rules.v4
```

### 手順4: SSH設定の確認

```bash
# SSH設定ファイルを確認
sudo cat /etc/ssh/sshd_config | grep -E "PermitRootLogin|PasswordAuthentication|PubkeyAuthentication"

# SSH鍵の確認
cat ~/.ssh/authorized_keys

# SSHサービスの再起動
sudo systemctl restart sshd
```

### 手順5: cloud-initのログ確認

```bash
# cloud-initのステータス
sudo cloud-init status

# cloud-initのログ
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log

# エラーがあるか確認
sudo journalctl -u cloud-init
```

## 恒久的な解決策

### 1. パケットフィルタでDHCPを許可（重要）

**さくらのクラウドのcloud-init Ubuntuイメージでは、DHCPの通信許可が必須です。**

理由：
- cloud-initイメージではIPアドレスがDHCPで自動割り当て
- パケットフィルタで67/UDP, 68/UDPを許可する必要がある
- 参考: https://manual.sakura.ad.jp/cloud/network/packet-filter.html

パケットフィルタ設定例：
```hcl
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
```

### 2. iptablesと組み合わせて多層防御

パケットフィルタとiptablesの両方を使用することで、より堅牢なセキュリティを実現：

**パケットフィルタ（外側の防御）:**
- さくらのクラウドのネットワークレベルで制御
- サーバーに到達する前にフィルタリング
- Webコンソールから管理可能

**iptables（内側の防御）:**
- サーバー内部で追加のフィルタリング
- きめ細かい制御が可能
- cloud-initで自動設定

### 3. cloud-init設定のベストプラクティス

1. **user_dataを使用**: `disk_edit_parameter`はcloud-initイメージで非対応
2. **ネットワーク設定は不要**: Ubuntuのデフォルトdhcpに任せる
3. **パッケージはaptで**: Ubuntu 24.04ではpipのシステムワイドインストール禁止
4. **多層防御**: パケットフィルタ + iptables

## 推奨される手順（新規デプロイ）

```bash
# 1. Terraform適用
cd terraform
terraform apply

# 2. 出力からIPアドレスを取得
terraform output server_ip

# 3. さくらのクラウドのコントロールパネルを開く
# https://secure.sakura.ad.jp/cloud/

# 4. サーバーが「停止中」の場合は「起動」をクリック

# 5. 2-3分待つ

# 6. SSH接続テスト
ssh ubuntu@<IPアドレス>
# 初回パスワード: TempPassword123!

# 7. ログイン後、パスワードを変更
passwd

# 8. SSH鍵が機能するか確認
exit
ssh -i ~/.ssh/id_rsa ubuntu@<IPアドレス>

# 9. Ansible実行
cd ../ansible
ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventory.ini playbook.yml
```

## よくある質問

### Q: なぜIPアドレスが付与されないのか？

A: **パケットフィルタでDHCP（67/UDP, 68/UDP）が許可されていないため**です。さくらのクラウドのcloud-init Ubuntuイメージでは、IPアドレスがDHCPで自動割り当てされます。解決策：
1. パケットフィルタに67/UDP, 68/UDPを追加
2. iptablesと組み合わせて多層防御

### Q: パケットフィルタとiptablesの両方が必要？

A: **推奨されます**。多層防御により：
1. パケットフィルタ: ネットワークレベルで不正アクセスをブロック
2. iptables: サーバー内部で追加のフィルタリング
3. より堅牢なセキュリティを実現

### Q: なぜpingが返ってこないのか？

A: 以下のいずれかの原因：
1. パケットフィルタでDHCPが許可されていない（IPアドレス未付与）
2. パケットフィルタまたはiptablesでICMPが拒否されている
3. Dev Container内からの外部pingは通らない（正常）

SSH接続で確認してください。

### Q: Ubuntu 24.04でpip install ansibleが失敗する

A: PEP 668により、システムワイドのpipインストールが禁止されています。解決策：
- `apt install ansible`を使用（推奨）
- または`pip3 install --break-system-packages ansible`（非推奨）

## 参考リンク

- [さくらのクラウド ドキュメント](https://manual.sakura.ad.jp/cloud/)
- [cloud-init ドキュメント](https://cloudinit.readthedocs.io/)
