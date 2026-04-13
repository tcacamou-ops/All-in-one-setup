#!/bin/bash
# WordPress initialization script
# Uses WP-CLI to install and configure WordPress (always latest version via wordpress:latest image)

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   WordPress Setup                              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

# Check .env exists
if [ ! -f "$ROOT_DIR/.env" ]; then
    echo -e "${RED}✗ .env file not found${NC}"
    exit 1
fi

source "$ROOT_DIR/.env"

# Validate required variables
WP_ADMIN_USER="${WP_ADMIN_USER:-admin}"
WP_ADMIN_EMAIL="${WP_ADMIN_EMAIL:-admin@example.com}"
WP_SITE_TITLE="${WP_SITE_TITLE:-My WordPress Site}"

if [ -z "${WP_ADMIN_PASSWORD:-}" ]; then
    echo -e "${RED}✗ WP_ADMIN_PASSWORD is not set in .env${NC}"
    echo -e "${YELLOW}Add WP_ADMIN_PASSWORD=yourpassword to your .env file${NC}"
    exit 1
fi

# Build site URL
protocol="http"
if [ "${ENABLE_SSL:-false}" = "true" ]; then
    protocol="https"
fi
SITE_URL="${protocol}://${DOMAIN_WORDPRESS}"

# Check WordPress container is running
echo -e "${YELLOW}🔍 Checking WordPress container...${NC}"
if ! docker compose -f "$ROOT_DIR/docker-compose.yml" ps wordpress 2>/dev/null | grep -q "Up"; then
    echo -e "${YELLOW}Starting MySQL and WordPress containers...${NC}"
    docker compose -f "$ROOT_DIR/docker-compose.yml" up -d mysql wordpress
    echo -e "${GREEN}✓ Containers started${NC}"
else
    echo -e "${GREEN}✓ Container is running${NC}"
fi
echo ""

# Wait for WordPress to be fully initialized (wp-config.php is written only once
# the container has successfully connected to MySQL)
echo -e "${YELLOW}⏳ Waiting for WordPress to be ready (MySQL + entrypoint)...${NC}"
MAX_TRIES=60
TRIES=0
while [ $TRIES -lt $MAX_TRIES ]; do
    if docker exec wordpress-app test -f /var/www/html/wp-config.php 2>/dev/null; then
        break
    fi
    TRIES=$((TRIES + 1))
    if [ $TRIES -ge $MAX_TRIES ]; then
        echo ""
        echo -e "${RED}✗ WordPress container did not initialize in time${NC}"
        echo -e "${YELLOW}Check logs with: docker logs wordpress-app${NC}"
        exit 1
    fi
    echo -n "."
    sleep 3
done
echo ""
echo -e "${GREEN}✓ WordPress is ready${NC}"
echo ""

# Install WP-CLI inside the container (download only if not already present)
echo -e "${BLUE}📦 Installing WP-CLI...${NC}"
docker exec wordpress-app bash -c "
    if ! command -v wp > /dev/null 2>&1; then
        curl -sSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
            -o /usr/local/bin/wp && chmod +x /usr/local/bin/wp
    fi
"
echo -e "${GREEN}✓ WP-CLI ready${NC}"
echo ""

# Check if WordPress is already installed
if docker exec -u www-data wordpress-app wp core is-installed --path=/var/www/html 2>/dev/null; then
    echo -e "${GREEN}✓ WordPress already installed, skipping core install${NC}"
else
    echo -e "${BLUE}🚀 Installing WordPress core...${NC}"
    docker exec -u www-data wordpress-app wp core install \
        --path=/var/www/html \
        --url="$SITE_URL" \
        --title="$WP_SITE_TITLE" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_password="$WP_ADMIN_PASSWORD" \
        --admin_email="$WP_ADMIN_EMAIL" \
        --skip-email
    echo -e "${GREEN}✓ WordPress installed successfully${NC}"
fi
echo ""

# Ensure WordPress core is at the latest version
# (wordpress:latest image tracks the latest release, but an update may be available
#  if the image was pulled some time ago)
echo -e "${BLUE}🔄 Checking for WordPress core updates...${NC}"
WP_UPDATE_OUTPUT=$(docker exec -u www-data wordpress-app wp core update --path=/var/www/html 2>&1 || true)
if echo "$WP_UPDATE_OUTPUT" | grep -q "Success: WordPress is up to date"; then
    echo -e "${GREEN}✓ WordPress is already up to date${NC}"
elif echo "$WP_UPDATE_OUTPUT" | grep -q "Success:"; then
    echo -e "${GREEN}✓ WordPress core updated to latest version${NC}"
    docker exec -u www-data wordpress-app wp core update-db --path=/var/www/html 2>/dev/null || true
else
    echo -e "${YELLOW}⚠️  Core update check: $WP_UPDATE_OUTPUT${NC}"
fi
echo ""

# Install / update all-in-one-download plugin (latest GitHub release)
echo -e "${BLUE}🔌 Installing all-in-one-download plugin...${NC}"
PLUGIN_ZIP_URL=$(curl -sSL "https://api.github.com/repos/tcacamou-ops/all-in-one-download/releases/latest" \
    | grep -oP '"browser_download_url":\s*"\K[^"]+\.zip')
if [ -z "$PLUGIN_ZIP_URL" ]; then
    echo -e "${YELLOW}⚠️  Could not fetch all-in-one-download release URL, skipping${NC}"
else
    # Ensure the log directory exists before activating the plugin
    docker exec wordpress-app mkdir -p /var/www/html/wp-content/uploads/alli1d/logs
    docker exec wordpress-app chown -R www-data:www-data /var/www/html/wp-content/uploads/alli1d

    docker exec -u www-data wordpress-app wp plugin install "$PLUGIN_ZIP_URL" \
        --path=/var/www/html \
        --activate \
        --force 2>&1 | tail -3
    echo -e "${GREEN}✓ Plugin all-in-one-download installed and activated${NC}"
fi

# Configure all-in-one-download directory options
echo -e "${BLUE}📁 Configuring all-in-one-download directories...${NC}"
AIO_MOVIE_DIRECTORY="${AIO_MOVIE_DIRECTORY:-}"
AIO_TV_SHOW_DIRECTORY="${AIO_TV_SHOW_DIRECTORY:-}"
if [ -n "$AIO_MOVIE_DIRECTORY" ]; then
    docker exec -u www-data wordpress-app wp option update movie_directory "$AIO_MOVIE_DIRECTORY" \
        --path=/var/www/html
    echo -e "${GREEN}✓ movie_directory → $AIO_MOVIE_DIRECTORY${NC}"
else
    echo -e "${YELLOW}⚠️  AIO_MOVIE_DIRECTORY not set, skipping${NC}"
fi
if [ -n "$AIO_TV_SHOW_DIRECTORY" ]; then
    docker exec -u www-data wordpress-app wp option update tv_show_directory "$AIO_TV_SHOW_DIRECTORY" \
        --path=/var/www/html
    echo -e "${GREEN}✓ tv_show_directory → $AIO_TV_SHOW_DIRECTORY${NC}"
else
    echo -e "${YELLOW}⚠️  AIO_TV_SHOW_DIRECTORY not set, skipping${NC}"
fi
echo ""

# Install / update all-in-one-download-rottentomatoes plugin (latest GitHub release)
echo -e "${BLUE}🔌 Installing all-in-one-download-rottentomatoes plugin...${NC}"
PLUGIN_RT_ZIP_URL=$(curl -sSL "https://api.github.com/repos/tcacamou-ops/All-in-one-Download-Rottentomatoes/releases/latest" \
    | grep -oP '"browser_download_url":\s*"\K[^"]+\.zip')
if [ -z "$PLUGIN_RT_ZIP_URL" ]; then
    echo -e "${YELLOW}⚠️  Could not fetch all-in-one-download-rottentomatoes release URL, skipping${NC}"
else
    docker exec -u www-data wordpress-app wp plugin install "$PLUGIN_RT_ZIP_URL" \
        --path=/var/www/html \
        --activate \
        --force 2>&1 | tail -3
    echo -e "${GREEN}✓ Plugin all-in-one-download-rottentomatoes installed and activated${NC}"
fi
echo ""

# Install / update all-in-one-download-transmission plugin (latest GitHub release)
echo -e "${BLUE}🔌 Installing all-in-one-download-transmission plugin...${NC}"
PLUGIN_TR_ZIP_URL=$(curl -sSL "https://api.github.com/repos/tcacamou-ops/All-in-one-Download-Transmission/releases/latest" \
    | grep -oP '"browser_download_url":\s*"\K[^"]+\.zip')
if [ -z "$PLUGIN_TR_ZIP_URL" ]; then
    echo -e "${YELLOW}⚠️  Could not fetch all-in-one-download-transmission release URL, skipping${NC}"
else
    docker exec -u www-data wordpress-app wp plugin install "$PLUGIN_TR_ZIP_URL" \
        --path=/var/www/html \
        --activate \
        --force 2>&1 | tail -3
    echo -e "${GREEN}✓ Plugin all-in-one-download-transmission installed and activated${NC}"
fi

# Configure all-in-one-download-transmission credentials
echo -e "${BLUE}🔑 Configuring all-in-one-download-transmission credentials...${NC}"
# Always use the internal Docker service name to avoid hairpin NAT issues
TRANSMISSION_TR_URL="http://transmission:9091/transmission/rpc"
if [ -n "$TRANSMISSION_TR_URL" ]; then
    docker exec -u www-data wordpress-app wp option update alli1d_transmission_url "$TRANSMISSION_TR_URL" \
        --path=/var/www/html
    echo -e "${GREEN}✓ alli1d_transmission_url → $TRANSMISSION_TR_URL${NC}"
else
    echo -e "${YELLOW}⚠️  TRANSMISSION_URL / DOMAIN_TRANSMISSION not set, skipping${NC}"
fi
if [ -n "${TRANSMISSION_USER:-}" ]; then
    docker exec -u www-data wordpress-app wp option update alli1d_transmission_login "$TRANSMISSION_USER" \
        --path=/var/www/html
    echo -e "${GREEN}✓ alli1d_transmission_login set${NC}"
else
    echo -e "${YELLOW}⚠️  TRANSMISSION_USER not set, skipping${NC}"
fi
if [ -n "${TRANSMISSION_PASS:-}" ]; then
    docker exec -u www-data wordpress-app wp option update alli1d_transmission_pwd "$TRANSMISSION_PASS" \
        --path=/var/www/html
    echo -e "${GREEN}✓ alli1d_transmission_pwd set${NC}"
else
    echo -e "${YELLOW}⚠️  TRANSMISSION_PASS not set, skipping${NC}"
fi
echo ""

# Install / update all-in-one-download-torr9 plugin (latest GitHub release)
echo -e "${BLUE}🔌 Installing all-in-one-download-torr9 plugin...${NC}"
PLUGIN_T9_ZIP_URL=$(curl -sSL "https://api.github.com/repos/tcacamou-ops/All-in-one-Download-torr9/releases/latest" \
    | grep -oP '"browser_download_url":\s*"\K[^"]+\.zip')
if [ -z "$PLUGIN_T9_ZIP_URL" ]; then
    echo -e "${YELLOW}⚠️  Could not fetch all-in-one-download-torr9 release URL, skipping${NC}"
else
    docker exec -u www-data wordpress-app wp plugin install "$PLUGIN_T9_ZIP_URL" \
        --path=/var/www/html \
        --activate \
        --force 2>&1 | tail -3
    echo -e "${GREEN}✓ Plugin all-in-one-download-torr9 installed and activated${NC}"
fi

# Configure all-in-one-download-torr9 credentials
echo -e "${BLUE}🔑 Configuring all-in-one-download-torr9 credentials...${NC}"
TORR9_API_KEY="${TORR9_API_KEY:-}"
TORR9_FULL_TOKEN="${TORR9_FULL_TOKEN:-}"
if [ -n "$TORR9_API_KEY" ]; then
    docker exec -u www-data wordpress-app wp option update alli1d_torr9_api_key "$TORR9_API_KEY" \
        --path=/var/www/html
    echo -e "${GREEN}✓ alli1d_torr9_api_key set${NC}"
else
    echo -e "${YELLOW}⚠️  TORR9_API_KEY not set, skipping${NC}"
fi
if [ -n "$TORR9_FULL_TOKEN" ]; then
    docker exec -u www-data wordpress-app wp option update alli1d_torr9_full_token "$TORR9_FULL_TOKEN" \
        --path=/var/www/html
    echo -e "${GREEN}✓ alli1d_torr9_full_token set${NC}"
else
    echo -e "${YELLOW}⚠️  TORR9_FULL_TOKEN not set, skipping${NC}"
fi
echo ""

# Install / update all-in-one-download-c411 plugin (latest GitHub release)
echo -e "${BLUE}🔌 Installing all-in-one-download-c411 plugin...${NC}"
PLUGIN_C411_ZIP_URL=$(curl -sSL "https://api.github.com/repos/tcacamou-ops/All-in-one-Download-c411/releases/latest" \
    | grep -oP '"browser_download_url":\s*"\K[^"]+\.zip')
if [ -z "$PLUGIN_C411_ZIP_URL" ]; then
    echo -e "${YELLOW}⚠️  Could not fetch all-in-one-download-c411 release URL, skipping${NC}"
else
    docker exec -u www-data wordpress-app wp plugin install "$PLUGIN_C411_ZIP_URL" \
        --path=/var/www/html \
        --activate \
        --force 2>&1 | tail -3
    echo -e "${GREEN}✓ Plugin all-in-one-download-c411 installed and activated${NC}"
fi

# Configure all-in-one-download-c411 API key
echo -e "${BLUE}🔑 Configuring all-in-one-download-c411 credentials...${NC}"
C411_API_KEY="${C411_API_KEY:-}"
if [ -n "$C411_API_KEY" ]; then
    docker exec -u www-data wordpress-app wp option update alli1d_c411_api_key "$C411_API_KEY" \
        --path=/var/www/html
    echo -e "${GREEN}✓ alli1d_c411_api_key set${NC}"
else
    echo -e "${YELLOW}⚠️  C411_API_KEY not set, skipping${NC}"
fi
echo ""

# Install / update crontroll plugin (WordPress.org)
echo -e "${BLUE}🔌 Installing crontroll plugin...${NC}"
docker exec -u www-data wordpress-app wp plugin install crontroll \
    --path=/var/www/html \
    --activate \
    --force 2>&1 | tail -3
echo -e "${GREEN}✓ Plugin crontroll installed and activated${NC}"
echo ""

# Disable built-in WP-Cron — Ofelia handles it via job-exec every 5 minutes
echo -e "${BLUE}⏰ Configuring WP-Cron (delegated to Ofelia)...${NC}"
docker exec -u www-data wordpress-app wp config set DISABLE_WP_CRON true --raw \
    --path=/var/www/html 2>/dev/null || true
echo -e "${GREEN}✓ Built-in WP-Cron disabled (Ofelia will trigger wp-cron.php every 5 min)${NC}"
echo ""

echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✓ WordPress setup complete!                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo "  • Site URL:    $SITE_URL"
echo "  • Admin:       $SITE_URL/wp-admin"
echo "  • Admin user:  $WP_ADMIN_USER"
echo ""
