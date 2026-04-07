#!/usr/bin/env python3
"""
Jellyfin automated configuration script
Automatically configures Jellyfin on first installation
"""

import os
import sys
import time
import json
import requests
from typing import Dict, Optional, List

# Disable SSL warnings
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class JellyfinAPI:
    """Jellyfin API client"""
    
    def __init__(self, base_url: str = "http://localhost:8096"):
        self.base_url = base_url.rstrip('/')
        self.api_key = None
        self.user_id = None
        self.session = requests.Session()
        # Required by Jellyfin even for unauthenticated startup endpoints
        self.session.headers.update({
            "Authorization": 'MediaBrowser Client="Jellyfin Python", Device="AutoConfigure", DeviceId="auto-configure-script", Version="10.0.0"',
            "Content-Type": "application/json"
        })
        
    def is_configured(self) -> bool:
        """Check whether Jellyfin is already configured"""
        try:
            response = self.session.get(
                f"{self.base_url}/Startup/Configuration",
                timeout=5
            )
            # A 404 or redirect means Jellyfin is already configured
            if response.status_code == 404:
                return True
            return False
        except:
            return False
    
    def wait_for_startup(self, timeout: int = 60) -> bool:
        """Wait for Jellyfin to be ready"""
        print("⏳ Waiting for Jellyfin to start...")
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                response = self.session.get(
                    f"{self.base_url}/System/Info/Public",
                    timeout=5
                )
                if response.status_code == 200:
                    print("✓ Jellyfin is ready")
                    return True
            except:
                pass
            
            time.sleep(3)
            print("  ⏳ Waiting...")
        
        return False
    
    def get_startup_user(self) -> Optional[str]:
        """Retrieve the username for the initial configuration"""
        try:
            response = self.session.get(f"{self.base_url}/Startup/User")
            if response.status_code == 200:
                data = response.json()
                return data.get("Name", "")
            return None
        except:
            return None
    
    def wait_for_user_init(self, timeout: int = 30) -> bool:
        """Wait for Jellyfin to initialize the first user in the database"""
        start = time.time()
        while time.time() - start < timeout:
            try:
                response = self.session.get(f"{self.base_url}/Startup/User", timeout=5)
                if response.status_code == 200:
                    name = response.json().get("Name", "")
                    if name:  # default user is ready
                        return True
            except Exception:
                pass
            time.sleep(1)
        return False

    def create_initial_user(self, username: str, password: str = "") -> bool:
        """Create the initial administrator account"""
        try:
            data = {
                "Name": username,
                "Password": password
            }
            
            response = self.session.post(
                f"{self.base_url}/Startup/User",
                json=data
            )
            
            if response.status_code == 204:
                print(f"✓ Administrator account '{username}' created")
                return True
            else:
                print(f"✗ Failed to create user: {response.status_code}")
                if response.text:
                    print(f"  Response: {response.text}")
                return False
                
        except Exception as e:
            print(f"✗ Erreur: {e}")
            return False
    
    def configure_startup_locale(self) -> bool:
        """Wizard step 1: configure culture/localization"""
        try:
            response = self.session.post(
                f"{self.base_url}/Startup/Configuration",
                json={
                    "UICulture": "fr-FR",
                    "MetadataCountryCode": "FR",
                    "PreferredMetadataLanguage": "fr"
                }
            )
            if response.status_code not in [200, 204]:
                print(f"  ⚠️  Locale configuration: {response.status_code}")
            return True
        except Exception as e:
            print(f"✗ Locale configuration error: {e}")
            return False

    def complete_startup(self) -> bool:
        """Complete the startup wizard (Remote Access + Complete)"""
        try:
            # Step 3: Remote Access
            response = self.session.post(
                f"{self.base_url}/Startup/RemoteAccess",
                json={"EnableRemoteAccess": True, "EnableAutomaticPortMapping": False}
            )
            
            if response.status_code not in [200, 204]:
                print(f"  ⚠️  Remote access configuration: {response.status_code}")
            
            # Step 4: Complete the wizard
            response = self.session.post(f"{self.base_url}/Startup/Complete")
            
            if response.status_code in [200, 204]:
                print("✓ Initial configuration complete")
                return True
            else:
                print(f"✗ Startup wizard failed: {response.status_code}")
                if response.text:
                    print(f"  Response: {response.text}")
                return False
                
        except Exception as e:
            print(f"✗ Erreur: {e}")
            return False
    
    def authenticate(self, username: str, password: str = "") -> bool:
        """Authenticate and obtain an API key"""
        try:
            data = {
                "Username": username,
                "Pw": password
            }
            
            response = self.session.post(
                f"{self.base_url}/Users/AuthenticateByName",
                json=data
            )
            
            if response.status_code == 200:
                result = response.json()
                self.api_key = result.get("AccessToken")
                self.user_id = result.get("User", {}).get("Id")
                
                # Update headers for future requests
                self.session.headers.update({
                    "X-Emby-Token": self.api_key
                })
                
                print(f"✓ Authenticated as '{username}'")
                return True
            else:
                print(f"✗ Authentication failed: {response.status_code}")
                return False
                
        except Exception as e:
            print(f"✗ Erreur authentification: {e}")
            return False
    
    def get_libraries(self) -> List[Dict]:
        """Retrieve the list of libraries"""
        try:
            response = self.session.get(f"{self.base_url}/Library/VirtualFolders")
            if response.status_code == 200:
                return response.json()
            return []
        except:
            return []
    
    def library_exists(self, name: str) -> bool:
        """Check whether a library exists"""
        libraries = self.get_libraries()
        return any(lib.get("Name") == name for lib in libraries)
    
    def create_library(
        self,
        name: str,
        library_type: str,
        paths: List[str],
        language: str = "fr",
        country: str = "FR"
    ) -> bool:
        """Create a media library"""
        
        if self.library_exists(name):
            print(f"  ⚠️  Library '{name}' already exists")
            return True
        
        try:
            # Prepare parameters
            params = {
                "name": name,
                "collectionType": library_type,
                "refreshLibrary": "false",
                "paths": paths
            }
            
            # Library options
            library_options = {
                "PreferredMetadataLanguage": language,
                "MetadataCountryCode": country,
                "EnablePhotos": True,
                "EnableRealtimeMonitor": True,
                "EnableChapterImageExtraction": False,
                "ExtractChapterImagesDuringLibraryScan": False,
                "SaveLocalMetadata": True,
                "EnableInternetProviders": True,
                "EnableAutomaticSeriesGrouping": True if library_type == "tvshows" else False,
                "PreferredMetadataLanguages": [language, "en"],
                "MetadataCountryCodes": [country, "US"]
            }
            
            params["libraryOptions"] = json.dumps(library_options)
            
            response = self.session.post(
                f"{self.base_url}/Library/VirtualFolders",
                params=params
            )
            
            if response.status_code in [200, 204]:
                print(f"  ✓ Library '{name}' created ({library_type})")
                return True
            else:
                print(f"  ✗ Failed to create library '{name}': {response.status_code}")
                if response.text:
                    print(f"    Response: {response.text}")
                return False
                
        except Exception as e:
            print(f"  ✗ Error creating library '{name}': {e}")
            return False
    
    def scan_library(self) -> bool:
        """Trigger a scan on all libraries"""
        try:
            response = self.session.post(f"{self.base_url}/Library/Refresh")
            if response.status_code in [200, 204]:
                print("✓ Library scan started")
                return True
            return False
        except:
            return False


def load_env_file(filepath: str = ".env") -> Dict[str, str]:
    """Load environment variables from a .env file"""
    env_vars = {}
    
    if not os.path.exists(filepath):
        return env_vars
    
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, value = line.split('=', 1)
                value = value.strip('"').strip("'")
                # Resolve variable references
                while '${' in value:
                    start = value.index('${')
                    end = value.index('}', start)
                    var_name = value[start+2:end]
                    var_value = env_vars.get(var_name, '')
                    value = value[:start] + var_value + value[end+1:]
                env_vars[key.strip()] = value
    
    return env_vars


def wait_for_jellyfin(base_url: str = "http://localhost:8096", timeout: int = 120):
    """Wait until Jellyfin is reachable"""
    print("⏳ Waiting for Jellyfin to start...")
    
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            response = requests.get(f"{base_url}/System/Info/Public", timeout=5)
            if response.status_code == 200:
                print("✓ Jellyfin is reachable")
                return True
        except:
            pass
        
        time.sleep(3)
        print("  ⏳ Waiting...")
    
    print("✗ Timeout: Jellyfin is not responding")
    return False


def main():
    """Main function"""
    print("╔════════════════════════════════════════════════╗")
    print("║  Automated Jellyfin Configuration            ║")
    print("╚════════════════════════════════════════════════╝")
    print()
    
    # Load environment variables
    print("📝 Loading environment variables...")
    _env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '.env')
    env = load_env_file(_env_path)
    
    # Configuration
    jellyfin_user = env.get('JELLYFIN_ADMIN_USER', 'admin')
    jellyfin_password = env.get('JELLYFIN_ADMIN_PASSWORD', '')
    media_path = env.get('MEDIA_PATH', '/datadisk/Media')
    
    print("✓ Configuration loaded")
    print(f"  • User: {jellyfin_user}")
    print(f"  • Media Path: {media_path}")
    print()
    
    # Attendre Jellyfin
    if not wait_for_jellyfin():
        print("✗ Jellyfin is not reachable")
        print("  Make sure the container is running: docker compose up -d jellyfin")
        sys.exit(1)
    
    print()
    
    # Create the API client
    jellyfin = JellyfinAPI()
    
    # Check if already configured
    if jellyfin.is_configured():
        print("ℹ️  Jellyfin is already configured")
        print()
        
        # Try to authenticate
        print("🔐 Authenticating...")
        if not jellyfin.authenticate(jellyfin_user, jellyfin_password):
            print("✗ Authentication failed")
            print("  If you changed the password, update JELLYFIN_ADMIN_PASSWORD in .env")
            sys.exit(1)
    else:
        print("🔧 Initial Jellyfin setup...")
        print()
        
        # Initial configuration (order matters for the Jellyfin API)
        print("1️⃣  Setting up localization...")
        jellyfin.configure_startup_locale()

        print()
        print("2️⃣  Creating administrator account...")
        print("  ⏳ Waiting for user database initialization...")
        if not jellyfin.wait_for_user_init():
            print("  ⚠️  User initialization timeout, trying anyway...")
        if not jellyfin.create_initial_user(jellyfin_user, jellyfin_password):
            print("✗ Failed to create user")
            sys.exit(1)
        
        print()
        print("3️⃣  Completing startup wizard...")
        if not jellyfin.complete_startup():
            print("✗ Startup wizard failed")
            sys.exit(1)
        
        print()
        print("⏳ Waiting 5 seconds for finalization...")
        time.sleep(5)
        
        print()
        print("4️⃣  Authenticating...")
        if not jellyfin.authenticate(jellyfin_user, jellyfin_password):
            print("✗ Authentication failed")
            sys.exit(1)
    
    print()
    
    # Configure media libraries
    print("📚 Configuring media libraries...")
    print()
    
    libraries_raw = env.get('JELLYFIN_LIBRARIES', '')
    libraries = []
    for entry in libraries_raw.split(','):
        parts = entry.strip().split(':')
        if len(parts) == 3:
            libraries.append({
                "name": parts[0].strip(),
                "type": parts[1].strip(),
                "path": f"{media_path}/{parts[2].strip()}"
            })
    if not libraries:
        print("✗ No libraries defined in JELLYFIN_LIBRARIES (.env)")
        sys.exit(1)
    
    success_count = 0
    for lib in libraries:
        print(f"Configuring '{lib['name']}'...")
        
        # Verify the path exists inside the container
        # The path in the container uses /media/ prefix, not the host path
        container_path = lib['path'].replace(media_path, '/media')
        
        if jellyfin.create_library(
            name=lib['name'],
            library_type=lib['type'],
            paths=[container_path],
            language="fr",
            country="FR"
        ):
            success_count += 1
        
        print()
    
    # Start scan
    if success_count > 0:
        print("🔍 Starting library scan...")
        jellyfin.scan_library()
        print()
    
    # Summary
    print("═" * 48)
    print(f"✓ Configuration complete: {success_count}/{len(libraries)} libraries configured")
    print()
    
    # Access information
    print("📋 Jellyfin access:")
    print(f"  • URL:      http://localhost:8096")
    
    domain_jellyfin = env.get('DOMAIN_JELLYFIN', '')
    if domain_jellyfin:
        protocol = "https" if env.get('ENABLE_SSL', 'false').lower() == 'true' else "http"
        print(f"  • Domain:   {protocol}://{domain_jellyfin}")
    
    print(f"  • User:     {jellyfin_user}")
    if jellyfin_password:
        print(f"  • Password: {jellyfin_password}")
    else:
        print(f"  • Password: (not set)")
    print()
    
    print("💡 Tips:")
    print("  • Library scan may take a while depending on the size of your media collection")
    print("  • Track scan progress in Jellyfin → Dashboard → Scheduled Tasks")
    print("  • Configure metadata providers in Settings → Libraries")
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
