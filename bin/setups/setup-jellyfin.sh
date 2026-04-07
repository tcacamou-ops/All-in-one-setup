#!/bin/bash
# Quick script to configure Jellyfin only

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Jellyfin Setup                              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

# Check .env exists
if [ ! -f "$ROOT_DIR/.env" ]; then
    echo -e "${RED}✗ .env file not found${NC}"
    exit 1
fi

# Load environment variables
source "$ROOT_DIR/.env"

# Check Python 3 and requests
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ Python 3 is not installed${NC}"
    exit 1
fi

if ! python3 -c "import requests" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Python module 'requests' is missing${NC}"
    echo -e "Install with: pip3 install requests"
    exit 1
fi

# Check that Jellyfin is running
echo -e "${YELLOW}🔍 Checking Jellyfin container...${NC}"
if ! docker compose -f "$ROOT_DIR/docker-compose.yml" ps jellyfin | grep -q "Up"; then
    echo -e "${YELLOW}Starting Jellyfin container...${NC}"
    docker compose -f "$ROOT_DIR/docker-compose.yml" up -d jellyfin
    echo -e "${GREEN}✓ Container started${NC}"
    echo -e "${YELLOW}Waiting 30 seconds for initialization...${NC}"
    sleep 30
else
    echo -e "${GREEN}✓ Container is running${NC}"
fi

echo ""

# Run configuration
python3 "$SCRIPT_DIR/auto-configure-jellyfin.py"

EXIT_CODE=$?

echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✓ Jellyfin setup complete!                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
else
    echo -e "${RED}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║   ✗ Setup encountered an error                ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════╝${NC}"
    exit 1
fi
