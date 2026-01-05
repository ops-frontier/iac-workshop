# Workspaces on Sakura Cloud - Project Overview

## プロジェクト完成

さくらのクラウド上でGitHub CodeSpaces風のサービスを構築するための完全なIaCプロジェクトです。

## 実装された機能

### ✅ インフラストラクチャ (Terraform)
- さくらのクラウドでのUbuntu 24.04サーバー起動
- パケットフィルタ（ファイアウォール）の設定
  - SSH, HTTP, HTTPS のインバウンド許可
  - HTTP, HTTPS, DNS, NTP のアウトバウンド許可
- SSH公開鍵認証
- Cloud-initによる初期セットアップ
- 環境変数からの設定読み込み（CodeSpaces Secretsサポート）

### ✅ サーバー構築 (Ansible)
- Dockerのインストールと設定
- Let's EncryptによるSSL証明書の自動取得
- Nginxリバースプロキシの設定
- アプリケーションのデプロイ
- 自動SSL証明書更新（cron設定）

### ✅ Webサービス (Node.js + Express)
- **GitHub OAuth認証**
  - PKCEによるセキュリティ強化
  - stateパラメータによるCSRF対策
- **ワークスペース管理**
  - ワークスペースの作成、起動、停止、削除
  - Gitリポジトリの自動clone
  - 環境変数の設定
  - devcontainer.jsonのサポート
- **SQLite3データベース**
  - ユーザー情報の管理
  - ワークスペース情報の永続化
- **Docker統合**
  - code-serverコンテナの動的起動
  - Nginxリバースプロキシの動的設定

### ✅ フロントエンド
- モダンなUI/UX
- レスポンシブデザイン
- ワークスペース一覧表示
- ワークスペース作成フォーム
- ワークスペース操作（開く、起動、停止、削除）

### ✅ コンテナ化
- Nginxコンテナ（最新版）
- Node.jsアプリケーションコンテナ
- code-serverワークスペースコンテナ（動的生成）
- Docker Composeによる管理

### ✅ セキュリティ
- SSL/TLS暗号化（Let's Encrypt）
- セキュアなセッション管理
- Rate Limiting
- Helmet.jsによるセキュリティヘッダー
- パケットフィルタによるネットワーク制御

### ✅ 開発環境
- Dev Container設定
- 必要なツールの自動インストール
  - Terraform
  - Ansible
  - Git, Git LFS
  - Node.js
  - Docker
- VS Code拡張機能の自動インストール

### ✅ ドキュメントファイル
- README.md: 詳細なセットアップガイド
- QUICKSTART.md: クイックスタートガイド
- CONTRIBUTING.md: 貢献ガイド
- LICENSE: MITライセンス
- .env.example: 環境変数サンプル

### ✅ ユーティリティスクリプト
- `scripts/deploy.sh`: 自動デプロイスクリプト
- `scripts/check-setup.sh`: セットアップチェックスクリプト

## ファイル構成

```
.
├── .devcontainer/
│   ├── devcontainer.json       # Dev Container設定
│   └── post-create.sh          # セットアップスクリプト
├── terraform/
│   ├── main.tf                 # プロバイダ設定
│   ├── variables.tf            # 変数定義
│   ├── server.tf               # サーバーリソース
│   ├── outputs.tf              # 出力定義
│   └── cloud-init.yaml         # Cloud-init設定
├── ansible/
│   ├── playbook.yml            # メインPlaybook
│   ├── ansible.cfg             # Ansible設定
│   ├── inventory.ini           # インベントリ
│   └── templates/
│       └── env.j2              # 環境変数テンプレート
├── app/
│   ├── server.js               # Expressサーバー
│   ├── database.js             # SQLiteデータベース
│   ├── workspace-manager.js    # ワークスペース管理
│   ├── package.json            # Node.js依存関係
│   ├── data/                   # データディレクトリ
│   └── public/
│       ├── index.html          # ランディングページ
│       └── dashboard.html      # ダッシュボード
├── docker/
│   ├── docker-compose.yml      # Docker Compose設定
│   └── app/
│       └── Dockerfile          # アプリDockerfile
├── nginx/
│   ├── nginx.conf              # Nginxメイン設定
│   └── conf.d/                 # 動的設定ディレクトリ
├── scripts/
│   ├── deploy.sh               # デプロイスクリプト
│   └── check-setup.sh          # セットアップチェック
├── .env.example                # 環境変数サンプル
├── .gitignore                  # Git除外設定
├── README.md                   # メインドキュメント
├── QUICKSTART.md               # クイックスタート
├── CONTRIBUTING.md             # 貢献ガイド
└── LICENSE                     # MITライセンス
```

## 使用技術

### Infrastructure as Code
- **Terraform**: さくらのクラウドのインフラ管理
- **Ansible**: サーバー構成管理

### Backend
- **Node.js**: ランタイム
- **Express**: Webフレームワーク
- **Passport.js**: OAuth認証
- **better-sqlite3**: データベース
- **Dockerode**: Docker API操作
- **simple-git**: Git操作

### Frontend
- **HTML/CSS/JavaScript**: バニラJS（フレームワークレス）
- **レスポンシブデザイン**

### Infrastructure
- **さくらのクラウド**: クラウドプロバイダー
- **Ubuntu 24.04**: OS
- **Docker & Docker Compose**: コンテナ化
- **Nginx**: リバースプロキシ & Webサーバー
- **Let's Encrypt**: SSL/TLS証明書

### Development Tools
- **GitHub CodeSpaces**: クラウド開発環境
- **VS Code Dev Container**: ローカル開発環境
- **Git**: バージョン管理

## デプロイフロー

1. **環境変数設定**: GitHub Secretsまたはローカル環境変数
2. **Terraform**: さくらのクラウドにサーバーを作成
3. **DNS設定**: ドメインをサーバーIPに向ける
4. **Ansible**: サーバーにアプリケーションをデプロイ
5. **アクセス**: https://your-domain.com

## 使用フロー

1. **ログイン**: GitHub OAuthで認証
2. **ワークスペース作成**: Gitリポジトリを指定
3. **自動セットアップ**: 
   - Gitリポジトリのclone
   - devcontainer.jsonの検出
   - code-serverコンテナの起動
   - Nginxプロキシの設定
4. **開発**: ブラウザでVS Codeを使用

## 必要な環境変数

```bash
TF_VAR_sakura_token         # さくらのクラウドAPIトークン
TF_VAR_sakura_secret        # さくらのクラウドAPIシークレット
TF_VAR_ssh_public_key       # SSH公開鍵
TF_VAR_domain               # ドメイン名
TF_VAR_github_client_id     # GitHub OAuth Client ID
TF_VAR_github_client_secret # GitHub OAuth Client Secret
```

## セキュリティ機能

1. **認証・認可**
   - GitHub OAuth 2.0
   - PKCE (Proof Key for Code Exchange)
   - State parameter for CSRF protection

2. **通信の暗号化**
   - Let's Encrypt SSL/TLS証明書
   - HTTPS強制
   - HSTS (HTTP Strict Transport Security)

3. **アプリケーションセキュリティ**
   - Helmet.js (セキュリティヘッダー)
   - Rate Limiting
   - Secure & HttpOnly cookies
   - XSS Protection
   - CORS設定

4. **インフラセキュリティ**
   - パケットフィルタ (ファイアウォール)
   - SSH公開鍵認証のみ
   - 最小権限の原則

## 今後の拡張可能性

- [ ] マルチノードサポート
- [ ] ワークスペースのバックアップ機能
- [ ] リソース使用量の監視
- [ ] コンテナのリソース制限
- [ ] ユーザーごとのクォータ設定
- [ ] Webhookによる自動デプロイ
- [ ] カスタムドメインサポート
- [ ] チーム機能
- [ ] ワークスペース共有機能

## ライセンス

MIT License

## サポート

問題が発生した場合は、GitHubのIssuesで報告してください。

---

**Status**: ✅ Production Ready
**Version**: 1.0.0
**Last Updated**: 2025-11-04
