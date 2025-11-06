#!/bin/bash
# Quick cleanup script - removes everything without confirmation
# Usage: ./scripts/quick-cleanup.sh [username]

set -e

REMOTE_HOST="ubuntu@133.125.84.224"
USERNAME="${1:-mit0223}"

echo "🧹 Quick Cleanup for user: ${USERNAME}"
echo "========================================="

# Remove containers
echo "🗑️  Removing workspace containers..."
ssh ${REMOTE_HOST} "docker ps -a --filter 'label=pseudo-codespaces.username=${USERNAME}' -q | xargs -r docker rm -f" 2>/dev/null || true

# Remove directories
echo "🗑️  Removing workspace directories..."
ssh ${REMOTE_HOST} "sudo rm -rf /home/${USERNAME}/workspaces/*" 2>/dev/null || true

# Remove Nginx configs
echo "🗑️  Removing Nginx configurations..."
ssh ${REMOTE_HOST} "sudo rm -f /opt/pseudo-codespaces/nginx/conf.d/workspace-${USERNAME}-*.conf" 2>/dev/null || true
ssh ${REMOTE_HOST} "docker exec nginx nginx -s reload" 2>/dev/null || true

# Clean database
echo "🗑️  Cleaning database..."
ssh ${REMOTE_HOST} "docker exec pseudo-codespaces-app node -e \"const Database = require('better-sqlite3'); const db = new Database('./data/database.db'); db.prepare('DELETE FROM workspaces WHERE user_id IN (SELECT id FROM users WHERE username = ?)').run('${USERNAME}'); db.close();\"" 2>/dev/null || true

echo ""
echo "✅ Quick cleanup completed!"
echo ""
echo "You can now retry your workspace creation."
