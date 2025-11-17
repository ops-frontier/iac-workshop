#!/bin/bash
# デプロイ用ヘルパースクリプト

set -e

echo "🚀 Workspaces デプロイスクリプト"
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
    
    if [ -z "$TF_VAR_dns_service_id" ]; then
        echo "❌ TF_VAR_dns_service_id が設定されていません"
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
        
        # サーバー接続確認（段階的チェック）
        echo "⏳ サーバーの接続確認を開始します..."
        echo ""
        
        # ステップ1: SSHポートの確認（ncコマンド）
        echo "🔍 ステップ1: SSHポート（22番）の確認中..."
        MAX_PORT_ATTEMPTS=12  # 1分間（5秒間隔で12回）
        PORT_ATTEMPT=0
        PORT_OPEN=false
        
        while [ $PORT_ATTEMPT -lt $MAX_PORT_ATTEMPTS ]; do
            PORT_ATTEMPT=$((PORT_ATTEMPT + 1))
            ELAPSED=$((PORT_ATTEMPT * 5))
            
            # 進捗表示
            printf "\r   経過時間: %d秒 / 60秒 - ポート試行 %d/%d..." $ELAPSED $PORT_ATTEMPT $MAX_PORT_ATTEMPTS
            
            # ncコマンドでポート22の確認（タイムアウト3秒）
            if nc -z -w 3 "$SERVER_IP" 22 2>/dev/null; then
                echo ""
                echo "✅ SSHポートが開いています！（${ELAPSED}秒後）"
                PORT_OPEN=true
                break
            fi
            
            sleep 5
        done
        
        echo ""
        
        if [ "$PORT_OPEN" = false ]; then
            echo "❌ エラー: 1分経ってもSSHポートが開きません"
            echo ""
            echo "Webコンソールで確認してください:"
            echo "  https://secure.sakura.ad.jp/cloud/"
            echo ""
            echo "考えられる原因:"
            echo "  - サーバーがまだ起動処理中"
            echo "  - ネットワーク設定の問題"
            echo "  - SSHサービスが起動していない"
            echo ""
            echo "Webコンソールからログイン:"
            echo "  ユーザー名: ubuntu"
            echo "  パスワード: TempPassword123!"
            echo ""
            echo "確認コマンド:"
            echo "  sudo systemctl status sshd"
            echo "  ip a show ens3"
            exit 1
        fi
        sleep 3 # 待機時間を追加してSSHポートの安定を待つ
        
        echo ""
        echo "✅ サーバーの接続確認が完了しました"
        
        # DNSレコードの登録確認
        echo ""
        echo "📡 DNSレコードの登録を確認中..."
        HOSTNAME=$(terraform output -raw hostname)
        echo "ホスト名: $HOSTNAME"
        
        MAX_DNS_ATTEMPTS=30  # 5分間（10秒間隔で30回）
        DNS_ATTEMPT=0
        DNS_RESOLVED=false
        
        while [ $DNS_ATTEMPT -lt $MAX_DNS_ATTEMPTS ]; do
            DNS_ATTEMPT=$((DNS_ATTEMPT + 1))
            ELAPSED=$((DNS_ATTEMPT * 10))
            
            printf "\r   経過時間: %d秒 / 300秒 - DNS確認 %d/%d..." $ELAPSED $DNS_ATTEMPT $MAX_DNS_ATTEMPTS
            
            # digコマンドでAレコードを確認
            DNS_IP=$(dig +short "$HOSTNAME" A | head -n 1)
            
            if [ -n "$DNS_IP" ] && [ "$DNS_IP" = "$SERVER_IP" ]; then
                echo ""
                echo "✅ DNSレコードが正しく登録されています！（${ELAPSED}秒後）"
                echo "   $HOSTNAME -> $DNS_IP"
                DNS_RESOLVED=true
                break
            elif [ -n "$DNS_IP" ]; then
                echo ""
                echo "⚠️  DNS応答がありますが、IPアドレスが一致しません"
                echo "   期待: $SERVER_IP"
                echo "   実際: $DNS_IP"
            fi
            
            sleep 10
        done
        
        echo ""
        
        if [ "$DNS_RESOLVED" = false ]; then
            echo "⚠️  警告: 5分経ってもDNSレコードが確認できません"
            echo ""
            echo "DNSの伝播には時間がかかる場合があります。"
            echo "さくらのクラウドのコントロールパネルでDNSレコードを確認してください。"
            echo ""
            echo "Ansibleデプロイは続行できますが、SSL証明書の取得に失敗する可能性があります。"
            echo ""
            read -p "Ansibleデプロイを続行しますか? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "デプロイを中断しました"
                echo "後で続行する場合: ./scripts/deploy.sh ansible"
                exit 0
            fi
        fi
        
        echo ""
        echo "次のステップ:"
        echo "1. Ansibleを実行してください: ./scripts/deploy.sh ansible"
        echo "   (inventory.ini は自動生成されます）"
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
    
    # Terraformからサーバー情報を取得してinventory.iniを生成
    echo "📝 inventory.ini を生成中..."
    cd ../terraform
    SERVER_IP=$(terraform output -raw server_ip 2>/dev/null || echo "")
    cd ../ansible
    
    if [ -z "$SERVER_IP" ]; then
        echo "❌ エラー: TerraformからサーバーIPアドレスを取得できませんでした"
        echo "先に Terraform デプロイを実行してください: ./scripts/deploy.sh terraform"
        exit 1
    fi
    
    # inventory.ini を生成
    cat > inventory.ini << EOF
[workspaces]
${SERVER_IP} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa

[workspaces:vars]
ansible_python_interpreter=/usr/bin/python3
EOF
    
    echo "✅ inventory.ini を生成しました (IP: $SERVER_IP)"
    
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
    echo "https://ws.$TF_VAR_domain にアクセスしてください"
    
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
            deploy_ansible
            ;;
        *)
            echo "使用方法: $0 [terraform|ansible|all]"
            exit 1
            ;;
    esac
}

main "$@"
