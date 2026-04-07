#!/usr/bin/env python3
"""
Nginx Proxy Manager automated configuration script
Automatically creates proxy hosts from environment variables
"""

import os
import sys
import time
import json
import requests
from typing import Dict, Optional

# Disable SSL warnings for self-signed certificates
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

NON_PUBLIC_TLDS = {'.local', '.test', '.localhost', '.internal', '.lan', '.home', '.corp', '.intranet'}

def is_public_domain(domain: str) -> bool:
    """Check whether a domain has a public TLD (Let's Encrypt only works on public domains)"""
    suffix = '.' + domain.rsplit('.', 1)[-1]
    return suffix not in NON_PUBLIC_TLDS


class NginxProxyManagerAPI:
    """Nginx Proxy Manager API client"""
    
    def __init__(self, base_url: str = "http://localhost:81"):
        self.base_url = base_url.rstrip('/')
        self.api_url = f"{self.base_url}/api"
        self.token = None
        self.session = requests.Session()
        
    def login(self, email: str, password: str) -> bool:
        """Connect to the NPM API"""
        try:
            response = self.session.post(
                f"{self.api_url}/tokens",
                json={
                    "identity": email,
                    "secret": password
                },
                verify=False
            )
            
            if response.status_code == 200:
                data = response.json()
                self.token = data.get("token")
                self.session.headers.update({
                    "Authorization": f"Bearer {self.token}"
                })
                print(f"✓ Connected to NPM successfully")
                return True
            else:
                print(f"✗ Login failed: {response.status_code}")
                print(f"  Response: {response.text}")
                return False
                
        except Exception as e:
            print(f"✗ Connection error: {e}")
            return False
    
    def get_proxy_hosts(self) -> list:
        """Retrieve the list of existing proxy hosts"""
        try:
            response = self.session.get(
                f"{self.api_url}/nginx/proxy-hosts",
                verify=False
            )
            
            if response.status_code == 200:
                return response.json()
            return []
            
        except Exception as e:
            print(f"✗ Error retrieving proxy hosts: {e}")
            return []
    
    def proxy_host_exists(self, domain: str) -> Optional[int]:
        """Check whether a proxy host already exists for this domain"""
        hosts = self.get_proxy_hosts()
        for host in hosts:
            if domain in host.get("domain_names", []):
                return host.get("id")
        return None
    
    def create_proxy_host(
        self,
        domain: str,
        forward_host: str,
        forward_port: int,
        enable_ssl: bool = False,
        ssl_email: str = None,
        websockets: bool = True
    ) -> bool:
        """Create a new proxy host"""
        
        # Check if already exists
        existing_id = self.proxy_host_exists(domain)
        if existing_id:
            print(f"  ⚠️  Proxy host for {domain} already exists (ID: {existing_id})")
            return True
        
        # Base data
        data = {
            "domain_names": [domain],
            "forward_scheme": "http",
            "forward_host": forward_host,
            "forward_port": forward_port,
            "access_list_id": 0,
            "certificate_id": 0,
            "ssl_forced": False,
            "caching_enabled": True,
            "block_exploits": True,
            "advanced_config": "",
            "meta": {
                "letsencrypt_agree": False,
                "dns_challenge": False
            },
            "allow_websocket_upgrade": websockets,
            "http2_support": True,
            "hsts_enabled": False,
            "hsts_subdomains": False
        }
        
        try:
            # Create the proxy host
            response = self.session.post(
                f"{self.api_url}/nginx/proxy-hosts",
                json=data,
                verify=False
            )
            
            if response.status_code in [200, 201]:
                host_data = response.json()
                host_id = host_data.get("id")
                print(f"  ✓ Proxy host created for {domain} (ID: {host_id})")
                
                # Configure SSL if requested
                if enable_ssl and ssl_email:
                    if is_public_domain(domain):
                        time.sleep(1)  # Wait briefly before configuring SSL
                        self.configure_ssl(host_id, domain, ssl_email)
                    else:
                        tld = '.' + domain.rsplit('.', 1)[-1]
                        print(f"    ⚠️  SSL skipped: '{tld}' is not a public TLD (Let's Encrypt requires a public domain)")
                
                return True
            else:
                print(f"  ✗ Failed to create proxy host: {response.status_code}")
                print(f"    Response: {response.text}")
                return False
                
        except Exception as e:
            print(f"  ✗ Error: {e}")
            return False
    
    def configure_ssl(self, host_id: int, domain: str, email: str) -> bool:
        """Configure Let's Encrypt SSL for a proxy host"""
        try:
            # Retrieve current host data
            response = self.session.get(
                f"{self.api_url}/nginx/proxy-hosts/{host_id}",
                verify=False
            )
            
            if response.status_code != 200:
                print(f"    ✗ Could not retrieve data for host {host_id}")
                return False
            
            host_data = response.json()
            
            # Update with SSL settings
            host_data.update({
                "certificate_id": "new",
                "ssl_forced": True,
                "http2_support": True,
                "hsts_enabled": True,
                "hsts_subdomains": False,
                "meta": {
                    "letsencrypt_agree": True,
                    "letsencrypt_email": email,
                    "dns_challenge": False
                }
            })
            
            # Apply the changes
            response = self.session.put(
                f"{self.api_url}/nginx/proxy-hosts/{host_id}",
                json=host_data,
                verify=False
            )
            
            if response.status_code == 200:
                print(f"    ✓ Let's Encrypt SSL configured for {domain}")
                return True
            else:
                print(f"    ✗ SSL configuration failed: {response.status_code}")
                return False
                
        except Exception as e:
            print(f"    ✗ SSL configuration error: {e}")
            return False


def load_env_file(filepath: str = ".env") -> Dict[str, str]:
    """Load environment variables from a .env file"""
    env_vars = {}
    
    if not os.path.exists(filepath):
        print(f"✗ File {filepath} not found")
        return env_vars
    
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, value = line.split('=', 1)
                # Resolve variable references (${VAR} syntax)
                value = value.strip('"').strip("'")
                while '${' in value:
                    start = value.index('${')
                    end = value.index('}', start)
                    var_name = value[start+2:end]
                    var_value = env_vars.get(var_name, '')
                    value = value[:start] + var_value + value[end+1:]
                env_vars[key.strip()] = value
    
    return env_vars


def wait_for_npm(base_url: str = "http://localhost:81", timeout: int = 60):
    """Wait until Nginx Proxy Manager is ready"""
    print("⏳ Waiting for Nginx Proxy Manager to start...")
    
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            response = requests.get(base_url, timeout=5, verify=False)
            if response.status_code in [200, 302, 401]:
                print("✓ Nginx Proxy Manager is ready")
                return True
        except:
            pass
        
        time.sleep(2)
        print("  ⏳ Waiting...")
    
    print("✗ Timeout: Nginx Proxy Manager is not responding")
    return False


def main():
    """Main function"""
    print("╔════════════════════════════════════════════════╗")
    print("║  Automated Nginx Proxy Manager Configuration  ║")
    print("╚════════════════════════════════════════════════╝")
    print()
    
    # Load environment variables
    print("📝 Loading environment variables...")
    _env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '.env')
    env = load_env_file(_env_path)
    
    if not env:
        print("✗ Failed to load the .env file")
        sys.exit(1)
    
    # Check for required variables
    required_vars = [
        'DOMAIN_JELLYFIN', 'DOMAIN_TRANSMISSION', 
        'DOMAIN_WORDPRESS', 'NPM_ADMIN_EMAIL', 'NPM_ADMIN_PASSWORD'
    ]
    
    missing_vars = [var for var in required_vars if var not in env]
    if missing_vars:
        print(f"✗ Missing variables in .env: {', '.join(missing_vars)}")
        sys.exit(1)
    
    print("✓ Environment variables loaded")
    print()
    
    # Configuration
    enable_ssl = env.get('ENABLE_SSL', 'false').lower() == 'true'
    ssl_email = env.get('LETSENCRYPT_EMAIL', '')
    
    services = [
        {
            "name": "Jellyfin",
            "domain": env['DOMAIN_JELLYFIN'],
            "host": "jellyfin",
            "port": 8096,
            "websockets": True
        },
        {
            "name": "Transmission",
            "domain": env['DOMAIN_TRANSMISSION'],
            "host": "transmission",
            "port": 9091,
            "websockets": True
        },
        {
            "name": "WordPress",
            "domain": env['DOMAIN_WORDPRESS'],
            "host": "wordpress",
            "port": 80,
            "websockets": False
        },
        {
            "name": "Nginx Proxy Manager",
            "domain": env.get('DOMAIN_NPM', ''),
            "host": "127.0.0.1",
            "port": 81,
            "websockets": True
        }
    ]
    # Exclude NPM service if DOMAIN_NPM is not defined
    services = [s for s in services if s["domain"]]
    
    # Wait for NPM
    if not wait_for_npm():
        print("✗ Nginx Proxy Manager is not reachable")
        print("  Make sure the containers are running: docker compose up -d")
        sys.exit(1)
    
    print()
    
    # Create the API client
    npm = NginxProxyManagerAPI()
    
    # Connect
    print("🔐 Logging in to Nginx Proxy Manager...")
    if not npm.login(env['NPM_ADMIN_EMAIL'], env['NPM_ADMIN_PASSWORD']):
        print("✗ Failed to connect to NPM")
        print()
        print("  📋 Resolution steps:")
        print("  1. Open http://localhost:81 in your browser")
        print("  2. Log in with the default credentials:")
        print("     - Email: admin@example.com")
        print("     - Password: changeme")
        print()
        print("  3. If the default credentials don't work:")
        print("     - You may have already changed the password")
        print("     - Use your custom credentials")
        print("     - Or reset NPM: bin/resets/reset-npm.sh")
        print()
        print("  4. Once logged in, update the credentials in .env:")
        print("     NPM_ADMIN_EMAIL=your_email")
        print("     NPM_ADMIN_PASSWORD=your_password")
        print()
        print("  5. Re-run this script: python3 bin/setups/auto-configure-npm.py")
        sys.exit(1)
    
    print()
    
    # Configure each service
    print("🔧 Configuring proxy hosts...")
    print()
    
    success_count = 0
    for service in services:
        print(f"Configuring {service['name']} ({service['domain']})...")
        
        if npm.create_proxy_host(
            domain=service['domain'],
            forward_host=service['host'],
            forward_port=service['port'],
            enable_ssl=enable_ssl,
            ssl_email=ssl_email,
            websockets=service['websockets']
        ):
            success_count += 1
        
        print()
    
    # Summary
    print("═" * 48)
    print(f"✓ Configuration complete: {success_count}/{len(services)} services configured")
    print()
    print("📋 Service access:")
    
    protocol = "https" if enable_ssl else "http"
    for service in services:
        print(f"  • {service['name']:15} {protocol}://{service['domain']}")
    
    print()
    print("🔧 Nginx Proxy Manager Admin: http://localhost:81")
    domain_npm = env.get('DOMAIN_NPM', '')
    if domain_npm:
        print(f"                               {protocol}://{domain_npm}")
    print()
    
    # SSL warnings
    if not enable_ssl:
        print("⚠️  SSL disabled. To enable Let's Encrypt:")
        print("   1. Set a public domain in .env (DOMAIN_BASE)")
        print("   2. Set ENABLE_SSL=true and LETSENCRYPT_EMAIL")
        print("   3. Re-run this script")
        print()
    elif not any(is_public_domain(s['domain']) for s in services):
        print("⚠️  ENABLE_SSL=true but all domains use a non-public TLD.")
        print(f"   Let's Encrypt cannot issue certificates for these domains.")
        print(f"   → Replace DOMAIN_BASE in .env with a real public domain (e.g. yourdomain.com)")
        print()
    
    # /etc/hosts entries for .local domains
    if any(s['domain'].endswith('.local') for s in services):
        print("💡 For .local domains, add to /etc/hosts:")
        print()
        for service in services:
            if service['domain'].endswith('.local'):
                print(f"   127.0.0.1    {service['domain']}")
        print()
        print("   Command: sudo nano /etc/hosts")
        print()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  Operation cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n✗ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
