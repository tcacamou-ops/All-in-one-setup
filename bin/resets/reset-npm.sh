#!/bin/bash
# Script to reset Nginx Proxy Manager to default credentials

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")" 

echo "🔄 Resetting Nginx Proxy Manager..."

# Stop NPM container
echo "Stopping NPM container..."
docker compose -f "$ROOT_DIR/docker-compose.yml" stop nginx-proxy

# Remove database file
echo "Removing database (requires sudo)..."
sudo rm "$ROOT_DIR/nginx-proxy/data/database.sqlite"

# Start NPM container
echo "Starting NPM container..."
docker compose -f "$ROOT_DIR/docker-compose.yml" start nginx-proxy

# Wait for NPM to initialize
echo "Waiting for NPM to initialize (30 seconds)..."
sleep 30

echo "✅ NPM has been reset!"
echo ""
echo "Default credentials are now active:"
echo "  Email: admin@example.com"
echo "  Password: changeme"
echo ""
echo "You can now run: python3 bin/setups/auto-configure-npm.py"
