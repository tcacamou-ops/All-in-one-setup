#!/bin/bash

# Helper script for domain and HTTPS configuration
# Usage: ./setup-domains.sh

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Domain and HTTPS Configuration              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

# Check Docker Compose
if ! command -v docker compose &> /dev/null; then
    echo -e "${RED}❌ Docker Compose is not installed${NC}"
    exit 1
fi

# Check containers are running
echo -e "${YELLOW}🔍 Checking container status...${NC}"
if ! docker compose ps | grep -q "Up"; then
    echo -e "${YELLOW}⚠️  Not all containers are running${NC}"
    read -p "Start them now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker compose up -d
        echo -e "${GREEN}✓ Containers started${NC}"
        sleep 5
    else
        echo -e "${RED}❌ Please start the containers with: docker compose up -d${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Containers are running${NC}"
fi

# Main menu
echo ""
echo -e "${BLUE}What would you like to do?${NC}"
echo "1) Local development setup (using .local domains)"
echo "2) Production setup (with a public domain)"
echo "3) Check service status"
echo "4) Generate a self-signed certificate"
echo "5) Show access information"
echo "6) Quit"
echo ""
read -p "Your choice (1-6): " choice

case $choice in
    1)
        echo ""
        echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║   Local Development Setup                    ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
        echo ""

        # Add to /etc/hosts
        echo -e "${YELLOW}📝 Configuring /etc/hosts${NC}"
        echo ""
        echo "The following entries need to be added to /etc/hosts:"
        echo ""
        echo "127.0.0.1    jellyfin.local"
        echo "127.0.0.1    transmission.local"
        echo "127.0.0.1    wordpress.local"
        echo "127.0.0.1    npm.local"
        echo ""

        read -p "Add them automatically (requires sudo)? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if ! grep -q "jellyfin.local" /etc/hosts; then
                echo "127.0.0.1    jellyfin.local" | sudo tee -a /etc/hosts > /dev/null
                echo "127.0.0.1    transmission.local" | sudo tee -a /etc/hosts > /dev/null
                echo "127.0.0.1    wordpress.local" | sudo tee -a /etc/hosts > /dev/null
                echo "127.0.0.1    npm.local" | sudo tee -a /etc/hosts > /dev/null
                echo -e "${GREEN}✓ Entries added to /etc/hosts${NC}"
            else
                echo -e "${YELLOW}⚠️  Entries already exist in /etc/hosts${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  Manually add these lines to /etc/hosts with: sudo nano /etc/hosts${NC}"
        fi

        echo ""
        echo -e "${GREEN}✓ Local setup complete${NC}"
        echo ""
        echo -e "${BLUE}📋 Next steps:${NC}"
        echo "1. Open Nginx Proxy Manager: http://localhost:81"
        echo "2. Default credentials: admin@example.com / changeme"
        echo "3. Re-run auto-setup.sh to regenerate the Caddyfile"
        echo ""
        ;;

    2)
        echo ""
        echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║   Production Setup                            ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
        echo ""

        read -p "Enter your domain name (e.g. example.com): " domain

        if [ -z "$domain" ]; then
            echo -e "${RED}❌ Domain name required${NC}"
            exit 1
        fi

        echo ""
        echo -e "${YELLOW}📝 Required DNS configuration${NC}"
        echo ""
        echo "Add these DNS records at your registrar:"
        echo ""
        echo "Type    Name                    Target"
        echo "A       jellyfin.$domain        $(curl -s ifconfig.me)"
        echo "A       transmission.$domain    $(curl -s ifconfig.me)"
        echo "A       wordpress.$domain       $(curl -s ifconfig.me)"
        echo ""
        echo "Or use a wildcard:"
        echo "A       *.$domain               $(curl -s ifconfig.me)"
        echo ""

        echo -e "${BLUE}📋 Security checklist:${NC}"
        echo "□ Ports 80 and 443 open in firewall"
        echo "□ Ports 80/443 forwarded in router"
        echo "□ DNS propagated (may take 24-48h)"
        echo ""

        read -p "Press Enter once DNS is configured..."

        echo ""
        echo -e "${GREEN}✓ Production setup initiated${NC}"
        echo ""
        echo -e "${BLUE}📋 Next steps:${NC}"
        echo "1. Wait for DNS propagation (check with: nslookup jellyfin.$domain)"
        echo "2. Run: ./bin/auto-setup.sh (will regenerate Caddyfile and configure Jellyfin)"
        echo ""
        ;;

    3)
        echo ""
        echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║   Service Status                               ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
        echo ""

        docker compose ps

        echo ""
        echo -e "${BLUE}Connectivity test...${NC}"

        if curl -s -o /dev/null -w "%{http_code}" http://localhost:8096 | grep -q "200\|302"; then
            echo -e "${GREEN}✓ Jellyfin: OK${NC}"
        else
            echo -e "${RED}✗ Jellyfin: unreachable${NC}"
        fi

        if curl -s -o /dev/null -w "%{http_code}" http://localhost:9091 | grep -q "200\|401\|301"; then
            echo -e "${GREEN}✓ Transmission: OK${NC}"
        else
            echo -e "${RED}✗ Transmission: unreachable${NC}"
        fi

        if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200\|302\|301"; then
            echo -e "${GREEN}✓ WordPress: OK${NC}"
        else
            echo -e "${RED}✗ WordPress: unreachable${NC}"
        fi

        if curl -s -o /dev/null -w "%{http_code}" http://localhost:81 | grep -q "200\|302\|301"; then
            echo -e "${GREEN}✓ Nginx Proxy Manager: OK${NC}"
        else
            echo -e "${RED}✗ Nginx Proxy Manager: unreachable${NC}"
        fi
        echo ""
        ;;

    4)
        echo ""
        echo -e "${YELLOW}⚠️  Self-signed certificates are no longer needed.${NC}"
        echo -e "Caddy handles HTTPS automatically via Let's Encrypt."
        echo -e "Set ENABLE_SSL=true and a public domain in .env, then run: ./bin/auto-setup.sh"
        echo ""
        ;;

    5)
        echo ""
        echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║   Access Information                           ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
        echo ""

        IP=$(curl -s ifconfig.me)

        echo -e "${BLUE}🌐 Direct access (no domain):${NC}"
        echo "• Jellyfin:        http://localhost:8096"
        echo "• Transmission:    http://localhost:9091"
        echo ""

        echo -e "${BLUE}🔑 Default credentials:${NC}"
        echo ""
        echo "Nginx Proxy Manager:"
        echo "  Email:    admin@example.com"
        echo "  Password: changeme"
        echo "  (Change on first login)"
        echo ""

        if [ -f "$ROOT_DIR/.env" ]; then
            echo "Transmission:"
            echo "  User:     $(grep TRANSMISSION_USER "$ROOT_DIR/.env" | cut -d'=' -f2)"
            echo "  Password: $(grep TRANSMISSION_PASS "$ROOT_DIR/.env" | cut -d'=' -f2)"
            echo ""
        fi

        echo -e "${BLUE}📚 Documentation:${NC}"
        echo "• README.md"
        echo "• QUICKSTART.md"
        echo ""
        ;;

    6)
        echo -e "${BLUE}Goodbye!${NC}"
        exit 0
        ;;

    *)
        echo -e "${RED}❌ Invalid choice${NC}"
        exit 1
        ;;
esac

echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo ""
