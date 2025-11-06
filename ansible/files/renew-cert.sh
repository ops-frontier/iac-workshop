#!/bin/bash
# SSL証明書自動更新スクリプト
# Certbotで証明書を更新し、成功したらNginxに新しい証明書をコピーしてリロード

set -e

DOMAIN="${1:-}"
APP_DIR="/opt/pseudo-codespaces"
LOG_FILE="/var/log/certbot-renewal.log"

if [ -z "$DOMAIN" ]; then
    echo "Error: DOMAIN not specified" | tee -a "$LOG_FILE"
    exit 1
fi

echo "$(date): Starting certificate renewal for $DOMAIN" | tee -a "$LOG_FILE"

# Certbotで証明書を更新（必要な場合のみ）
if certbot renew --quiet --deploy-hook "echo 'Certificate renewed successfully'"; then
    echo "$(date): Certbot renewal check completed" | tee -a "$LOG_FILE"
    
    # 証明書が更新された場合、アプリディレクトリにコピー
    if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        echo "$(date): Copying certificates to app directory" | tee -a "$LOG_FILE"
        cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$APP_DIR/ssl/fullchain.pem"
        cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$APP_DIR/ssl/privkey.pem"
        chown ubuntu:ubuntu "$APP_DIR/ssl/fullchain.pem" "$APP_DIR/ssl/privkey.pem"
        
        # Nginxコンテナをリロード
        echo "$(date): Reloading nginx" | tee -a "$LOG_FILE"
        docker exec nginx nginx -s reload
        
        echo "$(date): Certificate renewal completed successfully" | tee -a "$LOG_FILE"
    fi
else
    echo "$(date): Certificate renewal failed" | tee -a "$LOG_FILE"
    exit 1
fi
