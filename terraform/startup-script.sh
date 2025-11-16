#!/bin/bash
# Startup script for Workspaces server
# This script runs once during the first boot

set -e

# Set environment variables
cat >> /etc/environment << 'EOF'
DOMAIN="${domain}"
GITHUB_CLIENT_ID="${github_client_id}"
GITHUB_CLIENT_SECRET="${github_client_secret}"
EOF

# Change ubuntu user UID/GID to 1001
# Stop any processes running as ubuntu user
pkill -u ubuntu || true
# Change GID first
groupmod -g 1001 ubuntu
# Change UID and update home directory ownership
usermod -u 1001 ubuntu
chown -R ubuntu:ubuntu /home/ubuntu

# Configure passwordless sudo for ubuntu user
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu
chmod 0440 /etc/sudoers.d/ubuntu

# Create application directory
mkdir -p /opt/workspaces
chown ubuntu:ubuntu /opt/workspaces

echo "Startup script completed. System is ready for Ansible provisioning."
