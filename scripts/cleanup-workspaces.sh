#!/bin/bash
# Cleanup script for failed workspace tests
# Usage: ./scripts/cleanup-workspaces.sh [username]

set -e

REMOTE_HOST="ubuntu@133.125.84.224"
USERNAME="${1:-mit0223}"

echo "🧹 Pseudo CodeSpaces Cleanup Script"
echo "===================================="
echo ""
echo "Target user: ${USERNAME}"
echo ""

# Function to confirm
confirm() {
    read -p "$1 (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# 1. List workspace containers
echo "📦 Step 1: Checking workspace containers..."
ssh ${REMOTE_HOST} "docker ps -a --filter 'label=pseudo-codespaces.username=${USERNAME}' --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}'"
echo ""

if confirm "Remove all workspace containers for ${USERNAME}?"; then
    echo "Removing containers..."
    ssh ${REMOTE_HOST} "docker ps -a --filter 'label=pseudo-codespaces.username=${USERNAME}' -q | xargs -r docker rm -f"
    echo "✅ Containers removed"
else
    echo "⏭️  Skipped container removal"
fi
echo ""

# 2. List workspace directories
echo "📁 Step 2: Checking workspace directories..."
ssh ${REMOTE_HOST} "ls -la /home/${USERNAME}/workspaces/ 2>/dev/null || echo 'No workspace directory found'"
echo ""

if confirm "Remove all workspace directories for ${USERNAME}?"; then
    echo "Removing directories..."
    ssh ${REMOTE_HOST} "sudo rm -rf /home/${USERNAME}/workspaces/*"
    echo "✅ Directories removed"
else
    echo "⏭️  Skipped directory removal"
fi
echo ""

# 3. List Nginx configurations
echo "🔧 Step 3: Checking Nginx workspace configurations..."
ssh ${REMOTE_HOST} "ls -la /opt/pseudo-codespaces/nginx/conf.d/workspace-${USERNAME}-*.conf 2>/dev/null || echo 'No workspace configs found'"
echo ""

if confirm "Remove all Nginx workspace configurations for ${USERNAME}?"; then
    echo "Removing Nginx configs..."
    ssh ${REMOTE_HOST} "sudo rm -f /opt/pseudo-codespaces/nginx/conf.d/workspace-${USERNAME}-*.conf"
    echo "Reloading Nginx..."
    ssh ${REMOTE_HOST} "docker exec nginx nginx -s reload" || echo "⚠️  Nginx reload failed (might be okay if no configs were removed)"
    echo "✅ Nginx configs removed"
else
    echo "⏭️  Skipped Nginx config removal"
fi
echo ""

# 4. Database cleanup
echo "🗄️  Step 4: Checking database workspaces..."
ssh ${REMOTE_HOST} "docker exec pseudo-codespaces-app node -e \"const Database = require('better-sqlite3'); const db = new Database('./data/database.db'); const workspaces = db.prepare('SELECT id, name, status FROM workspaces WHERE user_id IN (SELECT id FROM users WHERE username = ?)').all('${USERNAME}'); console.log(workspaces.map(w => \\\`\\\${w.id}|\\\${w.name}|\\\${w.status}\\\`).join('\\\\n')); db.close();\""
echo ""

if confirm "Remove all database workspace entries for ${USERNAME}?"; then
    echo "Removing from database..."
    ssh ${REMOTE_HOST} "docker exec pseudo-codespaces-app node -e \"const Database = require('better-sqlite3'); const db = new Database('./data/database.db'); db.prepare('DELETE FROM workspaces WHERE user_id IN (SELECT id FROM users WHERE username = ?)').run('${USERNAME}'); db.close();\""
    echo "✅ Database entries removed"
else
    echo "⏭️  Skipped database cleanup"
fi
echo ""

# 5. Summary
echo "📊 Summary:"
echo "---------------------------------------"
echo "Remaining containers:"
ssh ${REMOTE_HOST} "docker ps -a --filter 'label=pseudo-codespaces.username=${USERNAME}' --format '{{.Names}}' | wc -l" | xargs echo -n
echo " containers"

echo "Remaining directories:"
ssh ${REMOTE_HOST} "ls /home/${USERNAME}/workspaces/ 2>/dev/null | wc -l" | xargs echo -n
echo " directories"

echo "Remaining Nginx configs:"
ssh ${REMOTE_HOST} "ls /opt/pseudo-codespaces/nginx/conf.d/workspace-${USERNAME}-*.conf 2>/dev/null | wc -l" | xargs echo -n
echo " config files"

echo "Remaining DB entries:"
ssh ${REMOTE_HOST} "docker exec pseudo-codespaces-app node -e \"const Database = require('better-sqlite3'); const db = new Database('./data/database.db'); const count = db.prepare('SELECT COUNT(*) as count FROM workspaces WHERE user_id IN (SELECT id FROM users WHERE username = ?)').get('${USERNAME}'); console.log(count.count); db.close();\""

echo ""
echo "✅ Cleanup completed!"
