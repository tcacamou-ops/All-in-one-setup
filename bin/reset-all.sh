#!/bin/bash
# Full project reset script
# Removes all data, configurations and Docker volumes

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}${BOLD}║                ⚠️  FULL RESET ⚠️                         ║${NC}"
echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${RED}This script will PERMANENTLY delete everything:${NC}"
echo ""
echo "   🎬  Jellyfin     — config, accounts, metadata, plugins, cache"
echo "   🔁  Transmission — config, torrents, stats, download queue"
echo "   🌐  Caddy        — Caddyfile, certificates, internal state"
echo "   🗄️   MySQL        — all databases"
echo "   📝  WordPress    — HTML files, plugins, themes, uploads"
echo "   🐳  Docker Volumes — all named volumes for this project"
echo ""
echo -e "${YELLOW}⚠️  Downloaded media files (MEDIA_PATH) will NOT be deleted.${NC}"
echo ""
echo -e "${BOLD}To confirm, type exactly: ${RED}RESET${NC}"
read -p "> " CONFIRMATION
if [[ "$CONFIRMATION" != "RESET" ]]; then
    echo "Cancelled. No data was deleted."
    exit 0
fi

echo ""
echo -e "${YELLOW}Last chance — are you absolutely sure? (y/n)${NC}"
read -p "> " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled. No data was deleted."
    exit 0
fi

echo ""
echo -e "${BOLD}🔄 Starting full reset...${NC}"
echo ""

# ─── 1. Stop and remove all containers + Docker volumes ─────────────────────
echo -e "${YELLOW}[1/5] Stopping and removing containers and Docker volumes...${NC}"
docker compose -f "$ROOT_DIR/docker-compose.yml" down --volumes --remove-orphans || true
echo -e "${GREEN}✓ Containers and Docker volumes removed${NC}"
echo ""

# ─── 2. Reset Jellyfin ───────────────────────────────────────────────────────
echo -e "${YELLOW}[2/5] Resetting Jellyfin...${NC}"
sudo rm -rf "$ROOT_DIR/jellyfin/config" "$ROOT_DIR/jellyfin/cache"
echo -e "${GREEN}✓ Jellyfin reset${NC}"
echo ""

# ─── 3. Reset Transmission ──────────────────────────────────────────────────
echo -e "${YELLOW}[3/5] Resetting Transmission...${NC}"
sudo rm -rf "$ROOT_DIR/transmission/config" "$ROOT_DIR/transmission/watch"
echo -e "${GREEN}✓ Transmission reset${NC}"
echo ""

# ─── 4. Reset Caddy ─────────────────────────────────────────────────────────
echo -e "${YELLOW}[4/5] Resetting Caddy...${NC}"
sudo rm -rf \
    "$ROOT_DIR/caddy/data" \
    "$ROOT_DIR/caddy/config" \
    "$ROOT_DIR/caddy/Caddyfile"
echo -e "${GREEN}✓ Caddy reset${NC}"
echo ""

# ─── 5. Reset MySQL + WordPress ─────────────────────────────────────────────
echo -e "${YELLOW}[5/5] Resetting MySQL and WordPress...${NC}"
sudo rm -rf "$ROOT_DIR/mysql/data"
sudo rm -rf \
    "$ROOT_DIR/wordpress/html" \
    "$ROOT_DIR/wordpress/plugins" \
    "$ROOT_DIR/wordpress/themes" \
    "$ROOT_DIR/wordpress/uploads"
echo -e "${GREEN}✓ MySQL and WordPress reset${NC}"
echo ""

# ─── Summary ────────────────────────────────────────────────────────────────
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║              ✅ Full reset complete!                     ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "The project has been restored to its initial state."
echo "To reconfigure everything, run:"
echo ""
echo -e "  ${BOLD}cd \"$ROOT_DIR\" && sudo bin/auto-setup.sh${NC}"
echo ""
