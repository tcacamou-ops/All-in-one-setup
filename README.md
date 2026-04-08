# All-in-One Docker Setup

A complete Docker Compose stack for a personal media and web server.

## Included Services

| Service | Description | Port |
|---------|-------------|------|
| **Jellyfin** | Media server (movies, TV shows) | 8096 |
| **Transmission** | BitTorrent client | 9091 |
| **WordPress** | CMS with MySQL database | — (commented) |
| **Caddy** | Reverse proxy + automatic HTTPS (Let's Encrypt) | 80 / 443 |
| **Ofelia** | Docker cron job manager | — (commented) |

## Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- Python 3 + `requests` module: `pip3 install -r requirements.txt`
- Sufficient disk space for media files

## Quick Start

### 1. Configure the environment

```bash
cp .env.example .env
nano .env
```

Key variables to set:

```bash
# User/group IDs (from `id -u` and `id -g`)
PUID=1000
PGID=1000
TZ=Europe/Paris

# Absolute path to your media folder
MEDIA_PATH=/datadisk/Media

# Transmission credentials
TRANSMISSION_USER=admin
TRANSMISSION_PASS=change_this_password

# WordPress database
MYSQL_ROOT_PASSWORD=secure_root_password_here
MYSQL_PASSWORD=secure_wordpress_password_here

# Domains
DOMAIN_BASE=local                              # or yourdomain.com in production
DOMAIN_JELLYFIN=jellyfin.${DOMAIN_BASE}
DOMAIN_TRANSMISSION=transmission.${DOMAIN_BASE}
DOMAIN_WORDPRESS=wordpress.${DOMAIN_BASE}

# SSL (requires a public domain)
# Set to false for local development — Caddy will disable HTTPS automatically
ENABLE_SSL=false
LETSENCRYPT_EMAIL=contact@yourdomain.com

# Jellyfin admin
JELLYFIN_ADMIN_USER=admin
JELLYFIN_ADMIN_PASSWORD=

# Jellyfin libraries (format: Name:type:SubFolder)
# Available types: movies, tvshows, music, books, photos
JELLYFIN_LIBRARIES="Movies:movies:Movies,TV Shows:tvshows:TvShows,Kids Movies:movies:KidsMovies,Kids Shows:tvshows:KidsTvShows"
```

### 2. Run the automated setup

```bash
chmod +x bin/auto-setup.sh
sudo bin/auto-setup.sh
```

`bin/auto-setup.sh` automatically:
- ✓ Generates `caddy/Caddyfile` from `.env` (HTTP or HTTPS depending on `ENABLE_SSL`)
- ✓ Creates the media folders with correct permissions
- ✓ Configures `/etc/hosts` for local domains
- ✓ Starts all Docker containers (`docker compose up -d`)
- ✓ Performs the initial Jellyfin setup (admin account + libraries)

## Accessing Services

### Local development (`DOMAIN_BASE=local`)

- **Jellyfin**: http://jellyfin.local
- **Transmission**: http://transmission.local
- **WordPress**: http://wordpress.local

### Production (`DOMAIN_BASE=yourdomain.com`)

- **Jellyfin**: https://jellyfin.yourdomain.com
- **Transmission**: https://transmission.yourdomain.com
- **WordPress**: https://wordpress.yourdomain.com

> HTTPS certificates are managed automatically by Caddy (Let's Encrypt). No manual configuration required.

## Shared Folders

Jellyfin and Transmission share the same `MEDIA_PATH`:

| Folder | Jellyfin path | Transmission path |
|--------|---------------|-------------------|
| Movies | `/media/Movies` | `/downloads/Movies` |
| TV Shows | `/media/TvShows` | `/downloads/TvShows` |
| Kids Movies | `/media/KidsMovies` | `/downloads/KidsMovies` |
| Kids Shows | `/media/KidsTvShows` | `/downloads/KidsTvShows` |
| Downloading | — | `/downloads/incomplete` |
| Completed | — | `/downloads/complete` |

## Scripts

All scripts are located in the `bin/` folder.

### `bin/auto-setup.sh` — Full setup

```bash
sudo bin/auto-setup.sh
```

Main script that orchestrates the entire configuration. Re-run after any `.env` change.

### `bin/setups/setup-jellyfin.sh` — Reconfigure Jellyfin only

```bash
bin/setups/setup-jellyfin.sh
```

### `bin/setups/setup-caddy.sh` — Regenerate Caddyfile only

```bash
bash bin/setups/setup-caddy.sh
```

Generates `caddy/Caddyfile` from `.env`. Run this if you change domains or SSL settings without running the full setup.

### `bin/setups/auto-configure-jellyfin.py` — Reconfigure Jellyfin only (Python)

```bash
python3 bin/setups/auto-configure-jellyfin.py
```

### `bin/setups/setup-domains.sh` — Interactive manual configuration

```bash
bash bin/setups/setup-domains.sh
```

Interactive menu: local/production setup, DNS instructions, service health check.

### Reset scripts

| Script | Action |
|--------|--------|
| `bin/reset-all.sh` | **Full** reset (removes everything) |
| `bin/resets/reset-jellyfin.sh` | Reset Jellyfin only |
| `bin/resets/reset-transmission.sh` | Reset Transmission only |

> ⚠️ Reset scripts are irreversible. Files in `MEDIA_PATH` are never deleted.

## Cron Jobs (Ofelia)

Edit `cron/config.ini` to add scheduled tasks:

```ini
# WordPress cron (every 5 minutes — enabled by default)
[job-exec "wordpress-cron"]
schedule = @every 5m
container = wordpress-app
command = php /var/www/html/wp-cron.php

# Clean old torrents (daily at 3 AM — disabled)
# [job-exec "clean-torrents"]
# schedule = 0 0 3 * * *
# container = transmission
# command = find /downloads -type f -mtime +30 -delete
```

After editing:

```bash
docker compose restart cron
```

## Useful Commands

```bash
# Start / stop all services
docker compose up -d
docker compose down

# View logs for a service
docker compose logs -f jellyfin

# Restart a service
docker compose restart transmission

# Update all images
docker compose pull && docker compose up -d

# Backup data (excluding media files)
docker compose down
tar -czf backup-$(date +%Y%m%d).tar.gz jellyfin/config transmission/config wordpress/ mysql/ caddy/
docker compose up -d
```

## Project Structure

```
All-in-one-setup/
├── docker-compose.yml
├── .env                    ← create from .env.example
├── .env.example
├── requirements.txt
├── README.md
├── bin/
│   ├── auto-setup.sh       ← main script
│   ├── reset-all.sh
│   ├── resets/
│   │   ├── reset-jellyfin.sh
│   │   └── reset-transmission.sh
│   └── setups/
│       ├── auto-configure-jellyfin.py
│       ├── setup-caddy.sh      ← generates caddy/Caddyfile
│       ├── setup-domains.sh
│       └── setup-jellyfin.sh
├── caddy/
│   ├── Caddyfile           ← generated (git-ignored)
│   ├── data/               ← certificates (git-ignored)
│   └── config/             ← caddy internal state (git-ignored)
├── cron/
│   └── config.ini
├── jellyfin/
│   ├── config/
│   └── cache/
├── transmission/
│   ├── config/
│   └── watch/
├── wordpress/
│   ├── html/
│   ├── plugins/
│   ├── themes/
│   └── uploads/
└── mysql/
    └── data/
```

## Network Architecture

Two Docker networks are created:
- `media-network`: Jellyfin, Transmission, Caddy
- `wordpress-network`: WordPress, MySQL, Caddy

This separation isolates WordPress from the media network while allowing Caddy to reach all services.

## Troubleshooting

### Volume permission issues

```bash
id -u   # → value for PUID
id -g   # → value for PGID
# Update .env then:
docker compose down && docker compose up -d
```

### Port conflict

Change the host port in `docker-compose.yml`:

```yaml
ports:
  - "8097:8096"  # changed host port
```

### Missing Python `requests` module

```bash
pip3 install -r requirements.txt
```

### HTTP 308 redirect loop (local mode)

In local mode (`ENABLE_SSL=false`), Caddy may redirect HTTP → HTTPS if its internal state cache retains a previous HTTPS session. The generated Caddyfile uses an explicit `http://` prefix to prevent this. If the issue persists:

```bash
# Clear Caddy's internal state and restart
docker compose stop caddy
sudo rm -rf caddy/data caddy/config
docker compose up -d caddy
```

Also clear the browser cache or do a hard refresh (`Ctrl+Shift+R`) to purge any HSTS entry stored by the browser.

### Caddyfile not generated

```bash
bash bin/setups/setup-caddy.sh
# Then reload Caddy:
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

### Caddy not responding or certificate error

```bash
docker compose ps caddy
docker compose logs --tail=50 caddy
# Wait a few seconds for Let's Encrypt — then check again
```

### View container logs

```bash
docker compose logs --tail=50 [jellyfin|transmission|caddy|wordpress|mysql]
```

## Security Recommendations

1. Change all default passwords in `.env`
2. Never expose service ports directly — use Caddy instead
3. Enable SSL (`ENABLE_SSL=true`) with a public domain (Caddy handles Let's Encrypt automatically)
4. Update images regularly: `docker compose pull && docker compose up -d`
5. Back up your data regularly using the backup command above

## Support

For issues specific to each service:
- Jellyfin: https://jellyfin.org/docs/
- Transmission: https://transmissionbt.com/
- WordPress: https://wordpress.org/support/
- Caddy: https://caddyserver.com/docs/
- Ofelia: https://github.com/mcuadros/ofelia
