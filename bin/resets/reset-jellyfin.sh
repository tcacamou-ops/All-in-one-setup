#!/bin/bash
# Reset Jellyfin completely (config, database, metadata)

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo -e "${YELLOW}⚠️  This script will delete ALL Jellyfin configuration:${NC}"
echo "   • User accounts and passwords"
echo "   • Configured libraries"
echo "   • Metadata and images"
echo "   • Installed plugins"
echo "   • All settings"
echo ""
read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "🔄 Resetting Jellyfin..."

# Stop the container
echo "Stopping Jellyfin container..."
docker compose -f "$ROOT_DIR/docker-compose.yml" stop jellyfin

# Remove config data (users, DB, metadata, plugins)
echo "Deleting data (requires sudo)..."
sudo rm -rf "$ROOT_DIR/jellyfin/config/config" \
            "$ROOT_DIR/jellyfin/config/data" \
            "$ROOT_DIR/jellyfin/config/log" \
            "$ROOT_DIR/jellyfin/config/metadata" \
            "$ROOT_DIR/jellyfin/config/plugins" \
            "$ROOT_DIR/jellyfin/config/root" \
            "$ROOT_DIR/jellyfin/config/.jellyfin-data"

# Clear the transcode cache
sudo rm -rf "$ROOT_DIR/jellyfin/cache/transcodes"

echo -e "${GREEN}✓ Data deleted${NC}"

# Restart the container
echo "Restarting Jellyfin container..."
docker compose -f "$ROOT_DIR/docker-compose.yml" start jellyfin

echo ""
echo -e "${YELLOW}⏳ Waiting for initialization (30 seconds)...${NC}"
sleep 30

echo ""
echo -e "${GREEN}✅ Jellyfin has been reset!${NC}"
echo ""
echo "You can now run the automatic configuration:"
echo "  sudo bin/auto-setup.sh"
echo "  or"
echo "  bin/setups/setup-jellyfin.sh"
