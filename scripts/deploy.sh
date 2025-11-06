#!/bin/bash
# デプロイ用ヘルパースクリプト

set -e

echo "🚀 Pseudo CodeSpaces デプロイスクリプト"
echo "========================================"

# 環境変数チェック
check_env_vars() {
    local missing=0
    
    echo "環境変数をチェック中..."
    
    if [ -z "$TF_VAR_sakura_token" ]; then
        echo "❌ TF_VAR_sakura_token が設定されていません"
        missing=1
    fi
    
    if [ -z "$TF_VAR_sakura_secret" ]; then
        echo "❌ TF_VAR_sakura_secret が設定されていません"
        missing=1
    fi
    
    if [ -z "$TF_VAR_ssh_public_key" ]; then
        echo "❌ TF_VAR_ssh_public_key が設定されていません"
        missing=1
    fi
    
    if [ -z "$TF_VAR_domain" ]; then
        echo "❌ TF_VAR_domain が設定されていません"
        missing=1
    fi
    
    if [ -z "$TF_VAR_github_client_id" ]; then
        echo "❌ TF_VAR_github_client_id が設定されていません"
        missing=1
    fi
    
    if [ -z "$TF_VAR_github_client_secret" ]; then
        echo "❌ TF_VAR_github_client_secret が設定されていません"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        echo ""
        echo "必要な環境変数が設定されていません。"
        echo "README.mdを参照して環境変数を設定してください。"
        exit 1
    fi
    
    echo "✅ 全ての環境変数が設定されています"
}

# Terraformデプロイ
deploy_terraform() {
    echo ""
    echo "📦 Terraformでインフラをデプロイ中..."
    
    cd terraform
    
    terraform init
    
    if ! terraform plan; then
        echo ""
        echo "❌ Terraform planに失敗しました"
        echo ""
        echo "よくあるエラー:"
        echo "  - Ubuntuイメージが見つからない → docs/SAKURA_UBUNTU_IMAGE.md を参照"
        echo "  - APIキーが無効 → TF_VAR_sakura_token と TF_VAR_sakura_secret を確認"
        echo "  - SSHキーの形式が無効 → TF_VAR_ssh_public_key を確認"
        exit 1
    fi
    
    read -p "デプロイを続行しますか? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform apply -auto-approve
        
        echo ""
        echo "✅ Terraformデプロイ完了"
        echo ""
        
        # サーバーIPアドレス取得
        SERVER_IP=$(terraform output -raw server_ip)
        echo "サーバーIPアドレス: $SERVER_IP"
        echo ""
        
        # サーバー起動待機（SSHで確認しながら）
        echo "⏳ サーバーの起動を待っています..."
        echo "   SSH接続で確認中（最大10分間）..."
        echo ""
        
        MAX_ATTEMPTS=120  # 10分間（5秒間隔で120回）
        ATTEMPT=0
        SERVER_UP=false
        
        while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
            ATTEMPT=$((ATTEMPT + 1))
            ELAPSED=$((ATTEMPT * 5))
            
            # 進捗表示
            printf "\r   経過時間: %d秒 / 600秒 - SSH試行 %d/%d..." $ELAPSED $ATTEMPT $MAX_ATTEMPTS
            
            # SSHテスト（タイムアウト5秒）
            if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes ubuntu@"$SERVER_IP" exit 2>/dev/null; then
                echo ""
                echo "✅ サーバーが起動しました！（${ELAPSED}秒後）"
                SERVER_UP=true
                break
            fi
            
            sleep 5
        done
        
        echo ""
        
        if [ "$SERVER_UP" = false ]; then
            echo "⚠️  タイムアウト: 10分経ってもサーバーが応答しません"
            echo ""
            echo "Webコンソールで確認してください:"
            echo "  https://secure.sakura.ad.jp/cloud/"
            echo ""
            echo "考えられる原因:"
            echo "  - サーバーがまだ起動処理中（cloud-initに時間がかかる）"
            echo "  - SSH鍵認証の問題"
            echo "  - ネットワーク設定の問題"
            echo ""
            echo "Webコンソールからログイン:"
            echo "  ユーザー名: ubuntu"
            echo "  パスワード: TempPassword123!"
            echo ""
            echo "確認コマンド:"
            echo "  sudo cloud-init status"
            echo "  ip a show ens3"
            echo "  sudo systemctl status sshd"
        else
            # サーバーが起動したら、cloud-init完了を少し待つ
            echo "⏳ cloud-initの完了を待っています（30秒）..."
            sleep 30
        fi
        
        echo ""
        
        # 接続テスト
        echo "🔍 接続テスト中..."
        if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$SERVER_IP" "echo 'SSH connection test'" 2>&1 | grep -q "SSH connection test"; then
            echo "✅ SSH接続成功"
            
            # cloud-init状態確認
            echo ""
            echo "cloud-init状態確認中..."
            ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$SERVER_IP" "sudo cloud-init status" 2>&1 || echo "⚠️  cloud-init状態を確認できませんでした"
        else
            echo "⚠️  SSH接続失敗"
            echo ""
            echo "まだサーバーが起動中の可能性があります。"
            echo "Webコンソールから確認できます:"
            echo "  ユーザー名: ubuntu"
            echo "  パスワード: TempPassword123!"
            echo ""
            echo "ログイン後、必ずパスワードを変更してください:"
            echo "  sudo passwd ubuntu"
        fi
        
        echo ""
        echo "次のステップ:"
        echo "1. 上記のIPアドレスをドメインのAレコードに設定してください"
        echo "2. DNSの伝播を待ってください（数分〜数時間）"
        echo "3. ansible/inventory.ini が自動更新されました"
        echo "4. Ansibleを実行してください: ./scripts/deploy.sh ansible"
        
        # Ansibleインベントリの自動更新
        cd ../ansible
        cat > inventory.ini << EOF
[pseudo_codespaces]
${SERVER_IP} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa

[pseudo_codespaces:vars]
ansible_python_interpreter=/usr/bin/python3
EOF
        echo ""
        echo "✅ Ansible inventory.ini を更新しました"
        cd ../terraform
    else
        echo "デプロイをキャンセルしました"
        exit 0
    fi
    
    cd ..
}

# Ansibleデプロイ
deploy_ansible() {
    echo ""
    echo "🔧 Ansibleでサーバーを構築中..."
    
    cd ansible
    
    # インベントリファイルのチェック
    if ! grep -q "ansible_user=ubuntu" inventory.ini; then
        echo "⚠️  inventory.ini にサーバー情報が設定されていないようです"
        echo "terraform outputからIPアドレスをコピーしてinventory.iniを編集してください"
        exit 1
    fi
    
    # Ansibleコレクションのインストール
    echo "Ansibleコレクションをインストール中..."
    ansible-galaxy collection install -r requirements.yml
    
    # Ansibleの実行（明示的にインベントリと設定ファイルを指定）
    echo "Ansibleを実行中..."
    ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventory.ini playbook.yml
    
    echo ""
    echo "✅ Ansibleデプロイ完了"
    echo ""
    echo "サービスが起動しました！"
    echo "https://$TF_VAR_domain にアクセスしてください"
    
    cd ..
}

# メイン処理
main() {
    check_env_vars
    
    case "${1:-all}" in
        terraform)
            deploy_terraform
            ;;
        ansible)
            deploy_ansible
            ;;
        all)
            deploy_terraform
            echo ""
            read -p "Ansibleデプロイを続行しますか? DNSの伝播を待ってください。(y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                deploy_ansible
            fi
            ;;
        *)
            echo "使用方法: $0 [terraform|ansible|all]"
            exit 1
            ;;
    esac
}

main "$@"
