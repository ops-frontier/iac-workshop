#!/bin/bash
set -e

# Restore Server Script for Workspaces
# This script recreates the server using the existing disk
# This resumes billing for the server

echo "========================================="
echo "RESTORE SERVER - Workspaces"
echo "========================================="
echo ""

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Info message
echo -e "${YELLOW}This script will:${NC}"
echo "  - Recreate the server instance using the existing disk"
echo "  - Resume billing for compute resources"
echo "  - Restore all data and services from the disk"
echo "  - Keep all existing configurations"
echo ""

# Confirmation prompt
echo -e "${YELLOW}Do you want to continue? (y/N):${NC} "
read -n 1 -r CONFIRMATION
echo

if [ "$CONFIRMATION" != "y" ] && [ "$CONFIRMATION" != "Y" ]; then
    echo ""
    echo "Operation cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Restoring server...${NC}"
echo ""

# Check if terraform directory exists
if [ ! -d "terraform" ]; then
    echo -e "${RED}Error: terraform directory not found${NC}"
    echo "Please run this script from the project root directory"
    exit 1
fi

cd terraform

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    echo -e "${RED}Error: No terraform state found${NC}"
    echo "Please run the initial deployment first: ./scripts/deploy.sh"
    exit 1
fi

# Check if disk exists in state
echo -e "${YELLOW}Checking if disk exists...${NC}"
DISK_EXISTS=$(terraform state list 2>/dev/null | grep "sakuracloud_disk.main" || echo "")

if [ -z "$DISK_EXISTS" ]; then
    echo -e "${RED}Error: No disk found in terraform state${NC}"
    echo "The disk must exist before restoring the server"
    echo "Please check your infrastructure state"
    exit 1
fi

echo "Disk found: ${DISK_EXISTS}"

# Check if server already exists
SERVER_EXISTS=$(terraform state list 2>/dev/null | grep "sakuracloud_server.main" || echo "")

if [ -n "$SERVER_EXISTS" ]; then
    echo ""
    echo -e "${YELLOW}Server already exists in state. Checking if it needs to be created...${NC}"
fi

# Apply to create only the server resource
echo ""
echo -e "${YELLOW}Creating server resource (using existing disk)...${NC}"
terraform apply -target=sakuracloud_server.main -auto-approve

echo ""
echo -e "${YELLOW}Waiting for server to be fully ready...${NC}"
sleep 15

# Get the new server IP
echo ""
echo -e "${YELLOW}Getting server information...${NC}"
SERVER_IP=$(terraform output -raw server_ip 2>/dev/null || echo "")

if [ -n "$SERVER_IP" ]; then
    echo "Server IP: ${SERVER_IP}"
    
    # Wait for SSH to be available
    echo ""
    echo -e "${YELLOW}Waiting for SSH to be available...${NC}"
    MAX_ATTEMPTS=30
    ATTEMPT=0
    
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"${SERVER_IP}" "echo SSH is ready" 2>/dev/null; then
            echo -e "${GREEN}SSH is ready!${NC}"
            break
        fi
        
        ATTEMPT=$((ATTEMPT + 1))
        echo "Attempt ${ATTEMPT}/${MAX_ATTEMPTS}..."
        sleep 10
    done
    
    if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
        echo -e "${YELLOW}Warning: SSH connection timeout. The server may still be booting.${NC}"
        echo "Please wait a few more minutes and try connecting manually:"
        echo "  ssh ubuntu@${SERVER_IP}"
    fi
else
    echo -e "${YELLOW}Warning: Could not retrieve server IP${NC}"
fi

echo ""
echo "========================================="
echo -e "${GREEN}Server Restored Successfully${NC}"
echo "========================================="
echo ""

if [ -n "$SERVER_IP" ]; then
    echo "Server has been restored and is running."
    echo ""
    echo "Server IP: ${SERVER_IP}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Connect via SSH: ssh ubuntu@${SERVER_IP}"
    echo "  2. Check services: docker ps -a"
    echo "  3. Access the web interface: https://$(terraform output -raw domain 2>/dev/null || echo 'your-domain')"
else
    echo "Server has been restored."
    echo "Run 'cd terraform && terraform output' to get server details."
fi

echo ""
echo -e "${YELLOW}Note:${NC}"
echo "  - All data from the disk has been preserved"
echo "  - Services should start automatically"
echo "  - If services are not running, you may need to run: ./scripts/deploy.sh ansible"
echo ""
