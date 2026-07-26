# All-in-One Docker Setup

A fully automated Docker Compose stack for a personal media and download server. A single command bootstraps everything: reverse proxy, media folders, Jellyfin configuration, WordPress installation, and all plugins.

## Included Services

| Service | Image | Description | Exposed port |
|---------|-------|-------------|--------------|
| **Jellyfin** | `jellyfin/jellyfin:latest` | Media server (movies, TV shows) | `127.0.0.1:8096` (local only) |
| **Transmission** | `linuxserver/transmission:latest` | BitTorrent client | `51413` (peers), UI via Caddy |
| **WordPress** | `wordpress:latest` | Download portal (latest WP) | via Caddy |
| **MySQL** | `mysql:8.0` | WordPress database | internal |
| **Caddy** | `caddy:latest` | Reverse proxy + automatic HTTPS | `80`, `443`, `443/udp` (HTTP/3) |
| **Ofelia** | `mcuadros/ofelia:latest` | Docker cron job manager | internal |
| **docker-socket-proxy** | `tecnativa/docker-socket-proxy:latest` | Secure minimal Docker socket exposure for Ofelia | internal |

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
TRANSMISSION_USER=download
TRANSMISSION_PASS=change_this_password

# WordPress database
MYSQL_ROOT_PASSWORD=secure_root_password
MYSQL_DATABASE=wordpress
MYSQL_USER=wpUser
MYSQL_PASSWORD=secure_wp_db_password

# Domains (use .local for dev, real domain for production)
DOMAIN_BASE=local
DOMAIN_JELLYFIN=jellyfin.${DOMAIN_BASE}
DOMAIN_TRANSMISSION=transmission.${DOMAIN_BASE}
DOMAIN_WORDPRESS=downloads.${DOMAIN_BASE}

# SSL (requires a public domain pointing to this server)
ENABLE_SSL=false
LETSENCRYPT_EMAIL=contact@yourdomain.com

# Jellyfin admin
JELLYFIN_ADMIN_USER=admin
JELLYFIN_ADMIN_PASSWORD=change_this_password

# Jellyfin libraries (format: DisplayName:type:SubFolder, comma-separated)
# Available types: movies, tvshows, music, books, photos
JELLYFIN_LIBRARIES="Movies:movies:Movies,TV Shows:tvshows:TvShows,Kids Movies:movies:KidsMovies,Kids Shows:tvshows:KidsTvShows"

# WordPress admin
WP_ADMIN_USER=admin
WP_ADMIN_PASSWORD=change_this_password
WP_ADMIN_EMAIL=admin@example.com
WP_SITE_TITLE="My Download Site"

# WordPress HTTP Basic Auth (optional — leave empty to disable)
WP_HTTP_AUTH_USER=
WP_HTTP_AUTH_PASSWORD=

# WordPress debug mode (optional — leave false for production)
WORDPRESS_DEBUG=false
WORDPRESS_CONFIG_EXTRA="define('WP_DEBUG_LOG', true); define('WP_DEBUG_DISPLAY', false); define('SCRIPT_DEBUG', true);"

# All-in-one-download plugin — paths relative to $MEDIA_PATH inside the container
AIO_MOVIE_DIRECTORY=downloads/Movies
AIO_TV_SHOW_DIRECTORY=downloads/TvShows

# Plugin credentials (optional — leave empty to skip)
TR4KER_API_KEY=
TR4KER_FULL_TOKEN=
C411_API_KEY=
GEMINI_TRACKER_API_KEY=
```

### 2. Run the automated setup

```bash
chmod +x bin/auto-setup.sh
sudo bin/auto-setup.sh
```

`bin/auto-setup.sh` automatically:
- ✓ Validates `.env` and checks dependencies
- ✓ Generates `caddy/Caddyfile` from `.env` (HTTP or HTTPS depending on `ENABLE_SSL`)
- ✓ Creates media sub-folders with correct `PUID:PGID` ownership and `775` permissions
- ✓ Adds `.local` domains to `/etc/hosts` (only when `DOMAIN_BASE=local`)
- ✓ Starts all Docker containers (`docker compose up -d`)
- ✓ Configures Jellyfin via REST API (admin account + libraries)
- ✓ Installs and configures WordPress + all plugins via WP-CLI

## Accessing Services

### Local development (`DOMAIN_BASE=local`)

- **Jellyfin**: http://jellyfin.local
- **Transmission**: http://transmission.local
- **WordPress**: http://downloads.local

### Production (`DOMAIN_BASE=yourdomain.com`)

- **Jellyfin**: https://jellyfin.yourdomain.com
- **Transmission**: https://transmission.yourdomain.com
- **WordPress**: https://downloads.yourdomain.com

> HTTPS certificates are managed automatically by Caddy (Let's Encrypt). No manual configuration required.

## WordPress Plugins

The setup script installs and activates the following plugins automatically:

| Plugin | Source | Description |
|--------|--------|-------------|
| `all-in-one-download` | GitHub (`tcacamou-ops`) | Core download portal |
| `all-in-one-download-rottentomatoes` | GitHub (`tcacamou-ops`) | Rotten Tomatoes metadata add-on |
| `all-in-one-download-transmission` | GitHub (`tcacamou-ops`) | Transmission integration |
| `all-in-one-download-torr9` | GitHub (`tcacamou-ops`) | Tr4ker torrent source add-on |
| `all-in-one-download-c411` | GitHub (`tcacamou-ops`) | C411 torrent source add-on |
| `all-in-one-download-gemini-tracker` | GitHub (`tcacamou-ops`) | Gemini Tracker torrent source add-on |
| `crontroll` | WordPress.org | WP-Cron management UI |

Plugin credentials (`TR4KER_API_KEY`, `TR4KER_FULL_TOKEN`, `C411_API_KEY`, `GEMINI_TRACKER_API_KEY`) are set automatically as WordPress options if provided in `.env`.

> WP-Cron is disabled in `wp-config.php`. Ofelia triggers `wp-cron.php` every 5 minutes instead.

## Shared Folders

Jellyfin and Transmission share the same `MEDIA_PATH` on the host:

| Host folder | Jellyfin path | Transmission path |
|-------------|---------------|-------------------|
| `$MEDIA_PATH/Movies` | `/media/Movies` | `/downloads/Movies` |
| `$MEDIA_PATH/TvShows` | `/media/TvShows` | `/downloads/TvShows` |
| `$MEDIA_PATH/KidsMovies` | `/media/KidsMovies` | `/downloads/KidsMovies` |
| `$MEDIA_PATH/KidsTvShows` | `/media/KidsTvShows` | `/downloads/KidsTvShows` |
| `$MEDIA_PATH/complete` | — | `/downloads/complete` |
| `$MEDIA_PATH/incomplete` | — | `/downloads/incomplete` |

## Scripts

All scripts are located in the `bin/` folder.

### `bin/auto-setup.sh` — Full setup (entry point)

```bash
sudo bin/auto-setup.sh
```

Orchestrates the entire bootstrap. Re-run after any `.env` change.

### `bin/setups/setup-caddy.sh` — Regenerate Caddyfile only

```bash
bash bin/setups/setup-caddy.sh
```

Generates `caddy/Caddyfile` from `.env`. Run this if you change domains, SSL settings, or HTTP Basic Auth without running the full setup. If `WP_HTTP_AUTH_USER` and `WP_HTTP_AUTH_PASSWORD` are set, a bcrypt hash is generated via Caddy and injected as a `basicauth` directive in front of WordPress.

### `bin/setups/setup-jellyfin.sh` — Reconfigure Jellyfin only

```bash
bash bin/setups/setup-jellyfin.sh
```

### `bin/setups/auto-configure-jellyfin.py` — Jellyfin REST API configuration

```bash
python3 bin/setups/auto-configure-jellyfin.py
```

### `bin/setups/setup-wordpress.sh` — WordPress install + plugin setup only

```bash
bash bin/setups/setup-wordpress.sh
```

Installs/updates WordPress core and all plugins via WP-CLI. Safe to re-run.

### `bin/setups/setup-domains.sh` — /etc/hosts helper

```bash
bash bin/setups/setup-domains.sh
```

Adds or removes `.local` domain entries in `/etc/hosts`.

### Reset scripts

| Script | Action |
|--------|--------|
| `bin/reset-all.sh` | **Full** reset — stops containers, removes all mounted data folders |
| `bin/resets/reset-jellyfin.sh` | Reset Jellyfin only |
| `bin/resets/reset-transmission.sh` | Reset Transmission only |

> ⚠️ Reset scripts are irreversible. Files in `MEDIA_PATH` are never deleted.

## Cron Jobs (Ofelia)

Edit `cron/config.ini` to add scheduled tasks. Ofelia uses the Docker socket via `docker-socket-proxy` — only `CONTAINERS`, `EXEC`, `EVENTS`, and `POST` capabilities are exposed.

```ini
# WordPress cron (every 5 minutes — enabled by default)
[job-exec "wordpress-cron"]
schedule = @every 5m
container = wordpress-app
command = php /var/www/html/wp-cron.php
```

After editing:

```bash
docker compose restart cron
```

## Updating the Stack

### What is never lost

All persistent data lives on **bind mounts** (local folders, not Docker volumes). `docker compose down`, `docker compose pull`, and image recreation never touch them:

| Service | Data location | What is preserved |
|---------|--------------|-------------------|
| **WordPress** | `mysql/data/` | Full database (posts, options, users, plugin settings) |
| **WordPress** | `wordpress/uploads/` | Uploaded media files |
| **Transmission** | `transmission/config/` | Active torrents, resume files, `settings.json` |
| **Jellyfin** | `jellyfin/config/` | Library metadata, users, watch history, plugins |
| **Caddy** | `caddy/data/` | Let's Encrypt certificates |

### Standard update procedure

Run these steps from the `All-in-one-setup/` directory each time you pull new code:

**Step 1 — Pull the latest scripts and compose file**

```bash
git -C .. pull   # from All-in-one-setup/; adjusts to your repo layout
# or from the repo root:
# git pull
```

**Step 2 — Pull the latest Docker images**

```bash
docker compose pull
```

This downloads new versions of `wordpress:latest`, `jellyfin/jellyfin:latest`, `mysql:8.0`, etc. Containers are not restarted yet.

**Step 3 — Reload Caddy config (if `setup-caddy.sh` changed)**

```bash
bash bin/setups/setup-caddy.sh
docker exec caddy caddy reload --config /etc/caddy/Caddyfile
```

Caddy reloads hot — no downtime, no certificate loss.

**Step 4 — Recreate containers with new images**

```bash
docker compose up -d
```

Docker Compose only recreates the containers whose image or config changed. The others are left running. Data bind mounts are reattached automatically.

**Step 5 — Update WordPress core and all plugins**

```bash
sudo bash bin/setups/setup-wordpress.sh
```

The script detects that WordPress is already installed and skips `core install`. It then:
- Checks for a WordPress core update (`wp core update`)
- Reinstalls each plugin from the latest GitHub release with `wp plugin install --force`
- Re-applies all credentials from `.env`

Safe to re-run at any time. The WordPress database is never reset.

### Full one-liner (when no `.env` changes)

```bash
docker compose pull && \
bash bin/setups/setup-caddy.sh && \
docker compose up -d && \
docker exec caddy caddy reload --config /etc/caddy/Caddyfile && \
sudo bash bin/setups/setup-wordpress.sh
```

### Verify after update

```bash
# All containers running
docker compose ps

# Check Caddy received new config (look for "config loaded" or no error)
docker compose logs --tail=20 caddy

# Check WordPress plugins are at latest version
docker exec -u www-data wordpress-app wp plugin list --path=/var/www/html

# Check Transmission still has its torrents
docker exec transmission ls /config/torrents/

# Spot-check Jellyfin library is intact
docker compose logs --tail=20 jellyfin
```

### When `.env` variables changed

If you edited `.env` (new domain, SSL toggle, credentials, media path):

```bash
sudo bash bin/auto-setup.sh
```

`auto-setup.sh` re-runs the full bootstrap — it is idempotent: WordPress is not reinstalled, Jellyfin is not reset, existing data is untouched.

---

## Useful Commands

```bash
# Start / stop all services
docker compose up -d
docker compose down

# View logs for a service
docker compose logs -f jellyfin
docker compose logs -f wordpress-app

# Restart a service
docker compose restart wordpress

# Pull latest images and recreate containers
docker compose pull && docker compose up -d --force-recreate

# Run WP-CLI manually
docker exec -u www-data wordpress-app wp --path=/var/www/html <command>

# Re-run WordPress setup only
bash bin/setups/setup-wordpress.sh

# Re-run Jellyfin setup only
bash bin/setups/setup-jellyfin.sh

# Backup data (excluding media files)
docker compose down
tar -czf backup-$(date +%Y%m%d).tar.gz jellyfin/config transmission/config wordpress/ mysql/ caddy/
docker compose up -d
```

## Project Structure

```
All-in-one-setup/
├── docker-compose.yml
├── .env                        ← create from .env.example
├── .env.example
├── requirements.txt
├── README.md
├── AGENTS.md                   ← project knowledge base (self-updating)
├── bin/
│   ├── auto-setup.sh           ← main entry point
│   ├── reset-all.sh            ← full reset (removes all mounted data)
│   ├── resets/
│   │   ├── reset-jellyfin.sh
│   │   └── reset-transmission.sh
│   └── setups/
│       ├── auto-configure-jellyfin.py  ← Jellyfin REST API setup
│       ├── setup-caddy.sh              ← generates caddy/Caddyfile
│       ├── setup-domains.sh            ← /etc/hosts helper
│       ├── setup-jellyfin.sh
│       └── setup-wordpress.sh          ← WP-CLI install + plugins
├── caddy/
│   ├── Caddyfile               ← generated by setup-caddy.sh (do not edit manually)
│   ├── data/                   ← Let's Encrypt certificates (persistent)
│   └── config/                 ← Caddy runtime state (persistent)
├── cron/
│   └── config.ini              ← Ofelia job definitions
├── jellyfin/
│   ├── config/                 ← Jellyfin config, data, metadata, plugins
│   └── cache/                  ← transcodes, image cache
├── transmission/
│   ├── config/                 ← settings, torrents, resume files
│   └── watch/                  ← drop .torrent files here to auto-add
├── wordpress/
│   ├── html/                   ← WordPress core files
│   ├── plugins/                ← bind-mounted to wp-content/plugins
│   ├── themes/                 ← bind-mounted to wp-content/themes
│   └── uploads/                ← bind-mounted to wp-content/uploads
└── mysql/
    └── data/                   ← MySQL data directory
```

## Network Architecture

Three Docker networks are created:

| Network | Services | Notes |
|---------|----------|-------|
| `media-network` | Jellyfin, Transmission, Caddy, Ofelia | Standard bridge |
| `wordpress-network` | WordPress, MySQL, Caddy, Ofelia | Standard bridge |
| `socket-proxy-network` | Ofelia ↔ docker-socket-proxy | Internal only (no Internet) |

Caddy bridges `media-network` and `wordpress-network` to reach all services. Ofelia connects to the Docker daemon through `docker-socket-proxy` over TCP instead of mounting `/var/run/docker.sock` directly.

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

### Enable WordPress debug mode

Set in `.env`:

```bash
WORDPRESS_DEBUG=true
WORDPRESS_CONFIG_EXTRA="define('WP_DEBUG_LOG', true); define('WP_DEBUG_DISPLAY', false); define('SCRIPT_DEBUG', true);"
```

These are container environment variables (read by `wordpress/html/wp-config.php`), not WP-CLI options, so `setup-wordpress.sh` won't pick up the change — recreate the container instead:

```bash
docker compose up -d --force-recreate wordpress
```

PHP errors/notices/warnings are then written to `wordpress/html/wp-content/debug.log` (nothing is displayed on screen thanks to `WP_DEBUG_DISPLAY=false`):

```bash
tail -f wordpress/html/wp-content/debug.log
```

Set `WORDPRESS_DEBUG=false` and clear `WORDPRESS_CONFIG_EXTRA` (or remove them) and re-run the command above to turn debug mode back off before going back to production use.

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
