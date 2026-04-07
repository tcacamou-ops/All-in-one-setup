#!/bin/bash
# Full automated setup script
# Automatically configures Nginx Proxy Manager and /etc/hosts

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Automated Environment Setup            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

# Check that .env exists
if [ ! -f "$ROOT_DIR/.env" ]; then
    echo -e "${RED}✗ .env file not found${NC}"
    echo -e "${YELLOW}Copy .env.example to .env and configure it${NC}"
    echo -e "  cp .env.example .env"
    echo -e "  nano .env"
    exit 1
fi

# Load environment variables
source "$ROOT_DIR/.env"

echo -e "${BLUE}📋 Detected configuration:${NC}"
echo "  • Jellyfin:      ${DOMAIN_JELLYFIN}"
echo "  • Transmission:  ${DOMAIN_TRANSMISSION}"
echo "  • WordPress:     ${DOMAIN_WORDPRESS}"
echo "  • NPM Admin:     ${DOMAIN_NPM}"
echo "  • SSL:           ${ENABLE_SSL}"
echo ""

# Check Docker Compose
if ! command -v docker compose &> /dev/null; then
    echo -e "${RED}✗ Docker Compose is not installed${NC}"
    exit 1
fi

# Check Python 3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ Python 3 is not installed${NC}"
    exit 1
fi

# Check requests module
if ! python3 -c "import requests" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Python module 'requests' is missing${NC}"
    read -p "Install now (pip3 install requests)? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pip3 install requests
    else
        echo -e "${RED}✗ requests module required. Install it with: pip3 install requests${NC}"
        exit 1
    fi
fi

# Create media folders with correct permissions
echo -e "${BLUE}📁 Creating media folders...${NC}"

# Base folders always present
MEDIA_DIRS=("$MEDIA_PATH" "$MEDIA_PATH/complete" "$MEDIA_PATH/incomplete")

# Add subfolders defined in JELLYFIN_LIBRARIES (format: Name:type:SubFolder,...)
if [ -n "${JELLYFIN_LIBRARIES:-}" ]; then
    IFS=',' read -ra LIB_ENTRIES <<< "$JELLYFIN_LIBRARIES"
    for entry in "${LIB_ENTRIES[@]}"; do
        subfolder="$(echo "$entry" | cut -d: -f3 | xargs)"
        if [ -n "$subfolder" ]; then
            MEDIA_DIRS+=("$MEDIA_PATH/$subfolder")
        fi
    done
fi

for dir in "${MEDIA_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        echo "  + Created: $dir"
    fi
done
echo "Setting ownership ${PUID}:${PGID} and permissions 775 on $MEDIA_PATH..."
chown -R "${PUID}:${PGID}" "$MEDIA_PATH"
chmod -R 775 "$MEDIA_PATH"
echo -e "${GREEN}✓ Media folders ready${NC}"
echo ""

# Start Docker containers
echo -e "${YELLOW}🐳 Checking Docker containers...${NC}"
if ! docker compose ps | grep -q "Up"; then
    echo -e "${YELLOW}Starting containers...${NC}"
    docker compose up -d
    echo -e "${GREEN}✓ Containers started${NC}"
    echo -e "${YELLOW}Waiting 10 seconds for initialization...${NC}"
    sleep 10
else
    echo -e "${GREEN}✓ Containers are running${NC}"
fi

echo ""

# Configure /etc/hosts for .local domains
if [[ "${DOMAIN_BASE}" == "local" ]] || [[ "${DOMAIN_JELLYFIN}" == *".local" ]]; then
    echo -e "${BLUE}🌐 Configuring /etc/hosts for local domains${NC}"
    echo ""

    HOSTS_ENTRIES=(
        "127.0.0.1    ${DOMAIN_JELLYFIN}"
        "127.0.0.1    ${DOMAIN_TRANSMISSION}"
        "127.0.0.1    ${DOMAIN_WORDPRESS}"
        "127.0.0.1    ${DOMAIN_NPM}"
    )

    NEEDS_UPDATE=false
    for entry in "${HOSTS_ENTRIES[@]}"; do
        domain=$(echo "$entry" | awk '{print $2}')
        if ! grep -q "$domain" /etc/hosts 2>/dev/null; then
            NEEDS_UPDATE=true
            break
        fi
    done

    if [ "$NEEDS_UPDATE" = true ]; then
        echo "The following entries will be added to /etc/hosts:"
        for entry in "${HOSTS_ENTRIES[@]}"; do
            echo "  $entry"
        done
        echo ""

        read -p "Add automatically (requires sudo)? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for entry in "${HOSTS_ENTRIES[@]}"; do
                domain=$(echo "$entry" | awk '{print $2}')
                if ! grep -q "$domain" /etc/hosts 2>/dev/null; then
                    echo "$entry" | sudo tee -a /etc/hosts > /dev/null
                fi
            done
            echo -e "${GREEN}✓ /etc/hosts updated${NC}"
        else
            echo -e "${YELLOW}⚠️  Manually add these lines to /etc/hosts with: sudo nano /etc/hosts${NC}"
        fi
    else
        echo -e "${GREEN}✓ /etc/hosts already configured${NC}"
    fi

    echo ""
fi

# Run NPM configuration script
echo -e "${BLUE}🔧 Configuring Nginx Proxy Manager...${NC}"
echo ""

python3 "$SCRIPT_DIR/setups/auto-configure-npm.py"

NPM_EXIT_CODE=$?

echo ""

# Run Jellyfin configuration script
if [ $NPM_EXIT_CODE -eq 0 ]; then
    echo -e "${BLUE}🎬 Configuring Jellyfin...${NC}"
    echo ""

    python3 "$SCRIPT_DIR/setups/auto-configure-jellyfin.py"

    JELLYFIN_EXIT_CODE=$?
    echo ""
else
    JELLYFIN_EXIT_CODE=1
fi

if [ $NPM_EXIT_CODE -eq 0 ] && [ $JELLYFIN_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      ✓ Setup completed successfully!          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}📚 Next steps:${NC}"
    echo ""

    protocol="http"
    if [ "${ENABLE_SSL}" = "true" ]; then
        protocol="https"
    fi

    echo "1. Access your services:"
    echo "   • Jellyfin:      ${protocol}://${DOMAIN_JELLYFIN}"
    echo "   • Transmission:  ${protocol}://${DOMAIN_TRANSMISSION}"
    echo "   • WordPress:     ${protocol}://${DOMAIN_WORDPRESS}"
    echo ""
    echo "2. Manage your proxy at:"
    echo "   • NPM Admin:     http://localhost:81"
    echo ""

    if [ "${ENABLE_SSL}" = "false" ]; then
        echo -e "${YELLOW}💡 To enable HTTPS with Let's Encrypt:${NC}"
        echo "   1. Set a public domain in .env"
        echo "   2. Set ENABLE_SSL=true"
        echo "   3. Set LETSENCRYPT_EMAIL"
        echo "   4. Re-run this script"
        echo ""
    fi

else
    echo -e "${RED}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║         ✗ Setup encountered an error          ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Check the output above for details${NC}"
    exit 1
fi

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Automated Environment Configuration       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

# Check that the .env file exists
if [ ! -f "$ROOT_DIR/.env" ]; then
    echo -e "${RED}✗ .env file not found${NC}"
    echo -e "${YELLOW}Copy .env.example to .env and configure it${NC}"
    echo -e "  cp .env.example .env"
    echo -e "  nano .env"
    exit 1
fi

# Charger les variables d'environnement
source "$ROOT_DIR/.env"

echo -e "${BLUE}📋 Detected configuration:${NC}"
echo "  • Jellyfin:      ${DOMAIN_JELLYFIN}"
echo "  • Transmission:  ${DOMAIN_TRANSMISSION}"
echo "  • WordPress:     ${DOMAIN_WORDPRESS}"
echo "  • NPM Admin:     ${DOMAIN_NPM}"
echo "  • SSL:           ${ENABLE_SSL}"
echo ""

# Check Docker Compose is installed
if ! command -v docker compose &> /dev/null; then
    echo -e "${RED}✗ Docker Compose is not installed${NC}"
    exit 1
fi

# Check Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ Python 3 is not installed${NC}"
    exit 1
fi

# Check the requests module is installed
if ! python3 -c "import requests" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Python module 'requests' is missing${NC}"
    read -p "Install now (pip3 install requests)? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pip3 install requests
    else
        echo -e "${RED}✗ Module requests required. Install it with: pip3 install requests${NC}"
        exit 1
    fi
fi

# Create media directories with correct permissions
echo -e "${BLUE}📁 Creating media directories...${NC}"

# Base directories always present
MEDIA_DIRS=("$MEDIA_PATH" "$MEDIA_PATH/complete" "$MEDIA_PATH/incomplete")

# Add sub-directories defined in JELLYFIN_LIBRARIES (format: Name:type:SubFolder,...)
if [ -n "${JELLYFIN_LIBRARIES:-}" ]; then
    IFS=',' read -ra LIB_ENTRIES <<< "$JELLYFIN_LIBRARIES"
    for entry in "${LIB_ENTRIES[@]}"; do
        subfolder="$(echo "$entry" | cut -d: -f3 | xargs)"
        if [ -n "$subfolder" ]; then
            MEDIA_DIRS+=("$MEDIA_PATH/$subfolder")
        fi
    done
fi

for dir in "${MEDIA_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        echo "  + Created: $dir"
    fi
done
echo "Applying ownership ${PUID}:${PGID} and permissions 775 to $MEDIA_PATH..."
chown -R "${PUID}:${PGID}" "$MEDIA_PATH"
chmod -R 775 "$MEDIA_PATH"
echo -e "${GREEN}✓ Media directories ready${NC}"
echo ""

# Start Docker containers
echo -e "${YELLOW}🐳 Checking Docker containers...${NC}"
if ! docker compose ps | grep -q "Up"; then
    echo -e "${YELLOW}Starting containers...${NC}"
    docker compose up -d
    echo -e "${GREEN}✓ Containers started${NC}"
    echo -e "${YELLOW}Waiting 10 seconds for initialization...${NC}"
    sleep 10
else
    echo -e "${GREEN}✓ Containers are running${NC}"
fi

echo ""

# Configuration de /etc/hosts pour domaines .local
if [[ "${DOMAIN_BASE}" == "local" ]] || [[ "${DOMAIN_JELLYFIN}" == *".local" ]]; then
    echo -e "${BLUE}🌐 Configuration /etc/hosts pour domaines locaux${NC}"
    echo ""
    
    HOSTS_ENTRIES=(
        "127.0.0.1    ${DOMAIN_JELLYFIN}"
        "127.0.0.1    ${DOMAIN_TRANSMISSION}"
        "127.0.0.1    ${DOMAIN_WORDPRESS}"
        "127.0.0.1    ${DOMAIN_NPM}"
    )
    
    NEEDS_UPDATE=false
    for entry in "${HOSTS_ENTRIES[@]}"; do
        domain=$(echo "$entry" | awk '{print $2}')
        if ! grep -q "$domain" /etc/hosts 2>/dev/null; then
            NEEDS_UPDATE=true
            break
        fi
    done
    
    if [ "$NEEDS_UPDATE" = true ]; then
        echo "The following entries will be added to /etc/hosts:"
        for entry in "${HOSTS_ENTRIES[@]}"; do
            echo "  $entry"
        done
        echo ""
        
        read -p "Add automatically (requires sudo)? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for entry in "${HOSTS_ENTRIES[@]}"; do
                domain=$(echo "$entry" | awk '{print $2}')
                if ! grep -q "$domain" /etc/hosts 2>/dev/null; then
                    echo "$entry" | sudo tee -a /etc/hosts > /dev/null
                fi
            done
            echo -e "${GREEN}✓ /etc/hosts updated${NC}"
        else
            echo -e "${YELLOW}⚠️  Add these lines manually to /etc/hosts with: sudo nano /etc/hosts${NC}"
        fi
    else
        echo -e "${GREEN}✓ /etc/hosts already configured${NC}"
    fi
    
    echo ""
fi

# Lancer le script Python de configuration NPM
echo -e "${BLUE}🔧 Configuration de Nginx Proxy Manager...${NC}"
echo ""

python3 "$SCRIPT_DIR/setups/auto-configure-npm.py"

NPM_EXIT_CODE=$?

echo ""

# Lancer le script Python de configuration Jellyfin
if [ $NPM_EXIT_CODE -eq 0 ]; then
    echo -e "${BLUE}🎬 Configuration de Jellyfin...${NC}"
    echo ""
    
    python3 "$SCRIPT_DIR/setups/auto-configure-jellyfin.py"
    
    JELLYFIN_EXIT_CODE=$?
    echo ""
else
    JELLYFIN_EXIT_CODE=1
fi

if [ $NPM_EXIT_CODE -eq 0 ] && [ $JELLYFIN_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✓ Setup completed successfully!              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}📚 Next steps:${NC}"
    echo ""
    
    protocol="http"
    if [ "${ENABLE_SSL}" = "true" ]; then
        protocol="https"
    fi
    
    echo "1. Access your services:"
    echo "   • Jellyfin:      ${protocol}://${DOMAIN_JELLYFIN}"
    echo "   • Transmission:  ${protocol}://${DOMAIN_TRANSMISSION}"
    echo "   • WordPress:     ${protocol}://${DOMAIN_WORDPRESS}"
    echo ""
    echo "2. Manage your reverse proxy at:"
    echo "   • NPM Admin:     http://localhost:81"
    echo ""
    
    if [ "${ENABLE_SSL}" = "false" ]; then
        echo -e "${YELLOW}💡 To enable HTTPS with Let's Encrypt:${NC}"
        echo "   1. Set a public domain in .env"
        echo "   2. Set ENABLE_SSL=true"
        echo "   3. Set LETSENCRYPT_EMAIL"
        echo "   4. Re-run this script"
        echo ""
    fi
    
else
    echo -e "${RED}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║   ✗ Configuration error                      ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Check the logs above for details${NC}"
    exit 1
fi
