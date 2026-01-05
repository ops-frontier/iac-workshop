#!/bin/bash
set -e

echo "Installing system packages..."
sudo apt-get update && sudo apt-get install -y netcat-traditional iputils-ping

echo "Installing Ansible..."
pip install --user ansible ansible-lint

echo "Installing Ansible collections..."
cd /workspaces/iac-workshop/ansible
ansible-galaxy collection install -r requirements.yml
cd -

echo "Verifying installations..."
terraform --version
ansible --version
git --version
git lfs --version
node --version
npm --version
docker --version
docker compose version

echo "Setting up Git configuration..."
git config --global core.autocrlf input

echo "Setting up SSH private key..."
if [ -n "$SSH_PRIVATE_KEY" ]; then
  mkdir -p ~/.ssh
  echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_rsa
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/id_rsa
  echo "SSH private key saved to ~/.ssh/id_rsa"
else
  echo "SSH_PRIVATE_KEY environment variable not set, skipping SSH key setup"
fi

echo "Post-create setup completed successfully!"
