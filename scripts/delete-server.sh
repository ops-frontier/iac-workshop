#!/bin/bash
set -e

# Delete Server Script for Workspaces
# This script deletes only the server instance while keeping the disk
# This stops billing for the server but keeps all data on the disk

echo "========================================="
echo "DELETE SERVER - Workspaces"
echo "========================================="
echo ""

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Info message
echo -e "${YELLOW}This script will:${NC}"
echo "  - Delete the server instance (stops billing for compute)"
echo "  - Keep the disk with all data intact (disk billing continues)"
echo "  - Keep packet filter (firewall) rules"
echo "  - Keep SSH keys"
echo ""
echo -e "${GREEN}Data is preserved and can be restored with restore-server.sh${NC}"
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
echo -e "${YELLOW}Deleting server...${NC}"
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
    echo "There is no infrastructure to delete"
    exit 1
fi

# Get server IP before deleting
echo -e "${YELLOW}Getting server information...${NC}"
SERVER_IP=$(terraform output -raw server_ip 2>/dev/null || echo "")

if [ -n "$SERVER_IP" ]; then
    echo "Server IP: ${SERVER_IP}"
fi

# Delete only the server resource using -target
echo ""
echo -e "${YELLOW}Destroying server resource (keeping disk)...${NC}"
terraform destroy -target=sakuracloud_server.main -auto-approve

echo ""
echo -e "${YELLOW}Waiting for server to be fully deleted...${NC}"
sleep 10

# Remove SSH known host entry
if [ -n "$SERVER_IP" ]; then
    echo ""
    echo -e "${YELLOW}Removing SSH known host entry for ${SERVER_IP}...${NC}"
    ssh-keygen -R "$SERVER_IP" 2>/dev/null || echo "No SSH host key found for ${SERVER_IP}"
fi

echo ""
echo "========================================="
echo -e "${GREEN}Server Deleted Successfully${NC}"
echo "========================================="
echo ""
echo "The server has been deleted and billing for compute has stopped."
echo "The disk with all your data is preserved."
echo ""
echo -e "${YELLOW}Important:${NC}"
echo "  - Disk billing continues (disk storage cost)"
echo "  - To restore the server, run: ./scripts/restore-server.sh"
echo "  - To completely destroy everything, run: ./scripts/destroy.sh"
echo ""
