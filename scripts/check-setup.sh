#!/bin/bash
# セットアップチェックスクリプト

echo "🔍 Workspaces セットアップチェック"
echo "=========================================="

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_passed=0
check_failed=0

# チェック関数
check_item() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅${NC} $2"
        ((check_passed++))
    else
        echo -e "${RED}❌${NC} $2"
        ((check_failed++))
    fi
}

check_warning() {
    echo -e "${YELLOW}⚠️${NC}  $1"
}

echo ""
echo "## 必要なツールの確認"

command -v terraform >/dev/null 2>&1
check_item $? "Terraform"

command -v ansible >/dev/null 2>&1
check_item $? "Ansible"

command -v git >/dev/null 2>&1
check_item $? "Git"

command -v docker >/dev/null 2>&1
check_item $? "Docker"

echo ""
echo "## 環境変数の確認"

[ -n "$TF_VAR_sakura_token" ]
check_item $? "TF_VAR_sakura_token"

[ -n "$TF_VAR_sakura_secret" ]
check_item $? "TF_VAR_sakura_secret"

[ -n "$TF_VAR_ssh_public_key" ]
check_item $? "TF_VAR_ssh_public_key"

[ -n "$TF_VAR_domain" ]
check_item $? "TF_VAR_domain"

[ -n "$TF_VAR_dns_service_id" ]
check_item $? "TF_VAR_dns_service_id"

[ -n "$WS_GITHUB_CLIENT_ID" ]
check_item $? "WS_GITHUB_CLIENT_ID"

[ -n "$WS_GITHUB_CLIENT_SECRET" ]
check_item $? "WS_GITHUB_CLIENT_SECRET"

[ -n "$DOCS_GITHUB_CLIENT_ID" ]
check_item $? "DOCS_GITHUB_CLIENT_ID"

[ -n "$DOCS_GITHUB_CLIENT_SECRET" ]
check_item $? "DOCS_GITHUB_CLIENT_SECRET"

[ -n "$TARGET_ORGANIZATION" ]
check_item $? "TARGET_ORGANIZATION"

echo ""
echo "## プロジェクトファイルの確認"

[ -f "terraform/main.tf" ]
check_item $? "terraform/main.tf"

[ -f "ansible/playbook.yml" ]
check_item $? "ansible/playbook.yml"

[ -f "app/server.js" ]
check_item $? "app/server.js"

[ -f "docker/docker-compose.yml" ]
check_item $? "docker/docker-compose.yml"

[ -f "nginx/nginx.conf" ]
check_item $? "nginx/nginx.conf"

echo ""
echo "## GitHub OAuth App の設定確認"

if [ -n "$TF_VAR_domain" ]; then
    echo "GitHub OAuth App の設定を確認してください:"
    echo ""
    echo "1. Workspaces用 (ws.$TF_VAR_domain)"
    echo "   Homepage URL: https://ws.$TF_VAR_domain"
    echo "   Callback URL: https://ws.$TF_VAR_domain/auth/github/callback"
    echo ""
    echo "2. Docs用 (docs.$TF_VAR_domain)"
    echo "   Homepage URL: https://docs.$TF_VAR_domain"
    echo "   Callback URL: https://docs.$TF_VAR_domain/auth/github/callback"
fi

echo ""
echo "=========================================="
echo "チェック結果: ${GREEN}✅ $check_passed${NC} / ${RED}❌ $check_failed${NC}"

if [ $check_failed -eq 0 ]; then
    echo -e "${GREEN}全てのチェックに合格しました！${NC}"
    echo ""
    echo "次のステップ:"
    echo "  1. ./scripts/deploy.sh を実行してデプロイを開始"
    echo "  または"
    echo "  2. cd terraform && terraform init && terraform apply"
    exit 0
else
    echo -e "${RED}いくつかのチェックに失敗しました。${NC}"
    echo "README.mdを参照して設定を確認してください。"
    exit 1
fi
