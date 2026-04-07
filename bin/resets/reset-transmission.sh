#!/bin/bash
# Reset Transmission completely (config, torrents, stats)

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo -e "${YELLOW}⚠️  This script will delete ALL Transmission configuration:${NC}"
echo "   • Configuration settings"
echo "   • Active torrent list"
echo "   • Resume files"
echo "   • Statistics"
echo "   • Bandwidth groups"
echo "   • Watch folder"
echo ""
echo -e "${RED}⚠️  Downloaded files will NOT be deleted.${NC}"
echo ""
read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "🔄 Resetting Transmission..."

# Stop the container
echo "Stopping Transmission container..."
docker compose -f "$ROOT_DIR/docker-compose.yml" stop transmission

# Remove config data
echo "Deleting configuration data (requires sudo)..."
sudo rm -rf "$ROOT_DIR/transmission/config/settings.json" \
            "$ROOT_DIR/transmission/config/bandwidth-groups.json" \
            "$ROOT_DIR/transmission/config/queue.json" \
            "$ROOT_DIR/transmission/config/stats.json" \
            "$ROOT_DIR/transmission/config/resume" \
            "$ROOT_DIR/transmission/config/torrents" \
            "$ROOT_DIR/transmission/config/blocklists"

# Clear watch folder
echo "Clearing watch folder (requires sudo)..."
sudo rm -rf "$ROOT_DIR/transmission/watch"/*

echo -e "${GREEN}✓ Data deleted${NC}"

# Restart the container
echo "Restarting Transmission container..."
docker compose -f "$ROOT_DIR/docker-compose.yml" start transmission

echo ""
echo -e "${YELLOW}⏳ Waiting for initialization (15 seconds)...${NC}"
sleep 15

echo ""
echo -e "${GREEN}✅ Transmission has been reset!${NC}"
echo ""
echo "Default credentials are now active:"
echo "  URL:      http://localhost:9091"
echo "  User:     \${TRANSMISSION_USER:-admin}"
echo "  Password: \${TRANSMISSION_PASS:-admin}"
echo ""
echo "Re-configure your download folders if needed."
