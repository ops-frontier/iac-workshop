# Ansible実行時のトラブルシューティング

## 問題: "No inventory was parsed, only implicit localhost is available"

### 症状

```
[WARNING]: No inventory was parsed, only implicit localhost is available
[WARNING]: provided hosts list is empty, only localhost is available
```

Playbookがスキップされ、何も実行されない。

### 原因

1. **インベントリファイルが空または正しく設定されていない**
2. **Ansibleがansible.cfgを無視している**（CodeSpaces環境）
3. **相対パスの問題**

### 解決方法

#### 1. インベントリファイルの確認

`ansible/inventory.ini`が正しく設定されているか確認：

```ini
[workspaces]
<IPアドレス> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa
```

例：
```ini
[workspaces]
133.125.84.224 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa
```

#### 2. 明示的にインベントリを指定して実行

CodeSpaces環境では、ディレクトリが世界書き込み可能なため、ansible.cfgが無視されます。
明示的にインベントリファイルを指定してください：

```bash
cd ansible
ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventory.ini playbook.yml
```

#### 3. ホストが認識されているか確認

```bash
cd ansible
ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventory.ini playbook.yml --list-hosts
```

期待される出力：
```
playbook: playbook.yml
  play #1 (all): Setup Workspaces Server TAGS: []
    pattern: ['all']
    hosts (1):
      133.125.84.224
```

## 問題: "Ansible is being run in a world writable directory"

### 症状

```
[WARNING]: Ansible is being run in a world writable directory (/workspaces/pseudo-work-spaces-sakura/ansible), 
ignoring it as an ansible.cfg source.
```

### 原因

GitHub CodeSpaces環境では、ワークスペースディレクトリが`777`（世界書き込み可能）になっており、
セキュリティ上の理由でAnsibleがansible.cfgを無視します。

### 解決方法

#### オプションA: 環境変数で明示的に指定（推奨）

```bash
ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventory.ini playbook.yml
```

#### オプションB: ディレクトリの権限を変更（ローカル環境のみ）

```bash
chmod 755 /workspaces/pseudo-work-spaces-sakura/ansible
```

**注意**: CodeSpaces環境では再起動後にリセットされるため、オプションAを推奨します。

#### オプションC: ホームディレクトリに設定をコピー

```bash
cp ansible.cfg ~/.ansible.cfg
```

## 問題: SSH接続エラー

### 症状

```
fatal: [133.125.84.224]: UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host via ssh"}
```

### 原因

1. SSH鍵が正しく設定されていない
2. サーバーが起動していない
3. ファイアウォールでSSHポートが閉じている

### 解決方法

#### 1. SSH接続テスト

```bash
ssh -i ~/.ssh/id_rsa ubuntu@133.125.84.224
```

成功する場合はAnsibleの設定問題、失敗する場合はSSHまたはネットワークの問題。

#### 2. SSH鍵の権限確認

```bash
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub
```

#### 3. サーバーの状態確認

さくらのクラウドのコントロールパネルでサーバーが起動中か確認。

#### 4. パケットフィルタの確認

SSHポート（22）が許可されているか確認。

## 問題: "Error reading config file"

### 症状

```
ERROR: Error reading config file (/workspaces/pseudo-work-spaces-sakura/ansible/ansible.cfg): 
File contains no section headers.
```

### 原因

ansible.cfgファイルが壊れているか、フォーマットが正しくない。

### 解決方法

ansible.cfgがINI形式であることを確認：

```ini
# コメント

[defaults]
inventory = inventory.ini
host_key_checking = False

[ssh_connection]
pipelining = True
```

**注意**: YAMLのヘッダー（`---`）は使用しないでください。

## デプロイスクリプト使用時

`scripts/deploy.sh`を使用する場合、これらの問題は自動的に処理されます：

```bash
./scripts/deploy.sh ansible
```

スクリプトは以下を自動実行します：
- インベントリファイルのチェック
- Ansibleコレクションのインストール
- 正しいパラメータでのplaybook実行

## 手動実行のベストプラクティス

```bash
cd ansible

# 1. インベントリの確認
cat inventory.ini

# 2. ホストの確認
ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventory.ini playbook.yml --list-hosts

# 3. ドライラン（実際には変更しない）
ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventory.ini playbook.yml --check

# 4. 実行
ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventory.ini playbook.yml

# 5. Verboseモード（詳細出力）
ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventory.ini playbook.yml -v
```

## 参考リンク

- [Ansible Configuration Settings](https://docs.ansible.com/ansible/latest/reference_appendices/config.html)
- [Ansible Inventory](https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html)
