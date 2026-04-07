# All-in-One Docker Setup

A complete Docker Compose stack for a personal media and web server.

## Included Services

| Service | Description | Port |
|---------|-------------|------|
| **Jellyfin** | Media server (movies, TV shows) | 8096 |
| **Transmission** | BitTorrent client | 9091 |
| **WordPress** | CMS with MySQL database | 8080 |
| **Nginx Proxy Manager** | Reverse proxy + Let's Encrypt SSL | 80 / 443 / 81 |
| **Ofelia** | Docker cron job manager | — |

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
DOMAIN_NPM=npm.${DOMAIN_BASE}

# SSL (requires a public domain)
ENABLE_SSL=false
LETSENCRYPT_EMAIL=contact@yourdomain.com

# Nginx Proxy Manager admin
NPM_ADMIN_EMAIL=admin@example.com
NPM_ADMIN_PASSWORD=changeme

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
- ✓ Creates the media folders with correct permissions
- ✓ Starts all Docker containers
- ✓ Configures `/etc/hosts` for local domains
- ✓ Creates proxy hosts in Nginx Proxy Manager
- ✓ Performs the initial Jellyfin setup (admin account + libraries)
- ✓ Enables Let's Encrypt if `ENABLE_SSL=true`

## Accessing Services

### Local development (`DOMAIN_BASE=local`)

- **Jellyfin**: http://jellyfin.local
- **Transmission**: http://transmission.local
- **WordPress**: http://wordpress.local
- **Nginx Proxy Manager**: http://localhost:81

### Production (`DOMAIN_BASE=yourdomain.com`)

- **Jellyfin**: https://jellyfin.yourdomain.com
- **Transmission**: https://transmission.yourdomain.com
- **WordPress**: https://wordpress.yourdomain.com
- **Nginx Proxy Manager**: http://npm.yourdomain.com

> Default Nginx Proxy Manager credentials: `admin@example.com` / `changeme` — change them on first login.

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

### `bin/setups/auto-configure-npm.py` — Reconfigure Nginx Proxy Manager only

```bash
python3 bin/setups/auto-configure-npm.py
```

### `bin/setups/auto-configure-jellyfin.py` — Reconfigure Jellyfin only (Python)

```bash
python3 bin/setups/auto-configure-jellyfin.py
```

### `bin/setups/setup-domains.sh` — Interactive manual configuration

```bash
bin/setups/setup-domains.sh
```

Interactive menu: local/production setup, service health check, self-signed certificates.

### Reset scripts

| Script | Action |
|--------|--------|
| `bin/reset-all.sh` | **Full** reset (removes everything) |
| `bin/resets/reset-jellyfin.sh` | Reset Jellyfin only |
| `bin/resets/reset-npm.sh` | Reset Nginx Proxy Manager only |
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
tar -czf backup-$(date +%Y%m%d).tar.gz jellyfin/config transmission/config wordpress/ mysql/ nginx-proxy/
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
├── QUICKSTART.md
├── bin/
│   ├── auto-setup.sh       ← main script
│   ├── reset-all.sh
│   ├── resets/
│   │   ├── reset-jellyfin.sh
│   │   ├── reset-npm.sh
│   │   └── reset-transmission.sh
│   └── setups/
│       ├── auto-configure-jellyfin.py
│       ├── auto-configure-npm.py
│       ├── setup-domains.sh
│       └── setup-jellyfin.sh
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
├── mysql/
│   └── data/
└── nginx-proxy/
    ├── data/
    └── letsencrypt/
```

## Network Architecture

Two Docker networks are created:
- `media-network`: Jellyfin, Transmission, Nginx Proxy Manager
- `wordpress-network`: WordPress, MySQL, Nginx Proxy Manager

This separation isolates WordPress from the media network while allowing the proxy to reach all services.

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

### NPM not responding

```bash
docker compose ps nginx-proxy
docker compose restart nginx-proxy
# Wait ~30 seconds then re-run bin/auto-setup.sh
```

### View container logs

```bash
docker compose logs --tail=50 [jellyfin|transmission|nginx-proxy|wordpress|mysql]
```

## Security Recommendations

1. Change all default passwords in `.env`
2. Never expose service ports directly — use Nginx Proxy Manager instead
3. Enable SSL (`ENABLE_SSL=true`) with a public domain
4. Update images regularly: `docker compose pull && docker compose up -d`
5. Back up your data regularly using the backup command above

## Support

For issues specific to each service:
- Jellyfin: https://jellyfin.org/docs/
- Transmission: https://transmissionbt.com/
- WordPress: https://wordpress.org/support/
- Nginx Proxy Manager: https://nginxproxymanager.com/
- Ofelia: https://github.com/mcuadros/ofelia
