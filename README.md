# n8n Production Stack - v2.5.2-config-optimized

A comprehensive, production-ready deployment script for n8n workflow automation platform with built-in retry mechanisms, cleanup functionality, and automatic SSL configuration.

## 🚀 Features

- **n8n Workflow Automation** - Latest version with SQLite database
- **FFmpeg + yt-dlp Media Processing** - Optional FFmpeg and yt-dlp integration built into n8n container
- **Qdrant Vector Database** - Optional AI/ML vector database
- **Automatic HTTPS** - Let's Encrypt SSL certificates via Caddy
- **Container Management** - Optional Portainer for Docker management
- **Log Monitoring** - Optional Dozzle for real-time container logs
- **Comprehensive Retry Logic** - 3-attempt retry system for all operations
- **Intelligent Cleanup** - Detects and handles existing installations
- **Subdomain-based Routing** - Access all services through dedicated subdomains when using domain
- **Qdrant API Key Authentication** - Secure API key for Qdrant vector database access
- **Latest Container Versions** - Always pulls the most recent images

## 📋 Prerequisites

- **VPS Requirements:**
  - Minimum 2GB RAM
  - Minimum 8GB disk space
  - Ubuntu/Debian Linux
  - Root access

- **Network Requirements:**
  - Domain name (optional, for HTTPS)
  - DNS pointing to your server IP (A record for main domain)
  - DNS wildcard or individual subdomains (for subdomain routing)
  - Ports 80, 443 open for HTTPS

## 🔧 Configuration Variables

Before running the script, you may want to customize these variables in the script:

### Required Configuration (Interactive Prompts)
```bash
N8N_DOMAIN=""        # Your domain (e.g., "n8n.yourdomain.com") - leave empty for IP access
N8N_USER=""          # Admin username/email (default: admin@example.com)
```

### Piped Execution Configuration (Environment Variables)
```bash
FORCE_INTERACTIVE="true"    # Force interactive mode even when piping from curl
CLEANUP_ACTION="clean"      # Pre-configure cleanup action: keep|clean|exit
```

### System Configuration (Modify in script if needed)
```bash
readonly MIN_RAM_GB=2           # Minimum RAM requirement
readonly MIN_DISK_GB=8          # Minimum disk space requirement
readonly SETUP_DIR="/opt/n8n-stack"  # Installation directory
```

### Retry Configuration (Modify in script if needed)
```bash
readonly MAX_RETRIES=3          # Number of retry attempts
readonly RETRY_DELAY=5          # Seconds between retries
readonly NETWORK_TIMEOUT=30     # Network operation timeout
```

### Container Versions (Always Latest)
```bash
readonly N8N_VERSION="latest"
readonly QDRANT_VERSION="latest"
readonly CADDY_VERSION="latest"
readonly DOZZLE_VERSION="latest"
readonly PORTAINER_VERSION="latest"
```

## 🚀 Quick Start

### 1. Download the Script
```bash
wget https://raw.githubusercontent.com/osamarehman/n8n_docker_script/main/docker-n8n.sh
chmod +x docker-n8n.sh
```

### 2. Run the Installation
```bash
sudo ./docker-n8n.sh
```

### 3. Follow the Interactive Prompts
- Enter your domain name (or leave empty for IP access)
- Enter admin username/email (or use default)
- The script will handle the rest automatically

### 4. Auto Mode (Non-Interactive)
```bash
sudo N8N_DOMAIN="your-domain.com" N8N_USER="admin@yourdomain.com" ./docker-n8n.sh --auto
```

### 5. Pre-configure Optional Components
You can skip interactive prompts by setting environment variables:
```bash
# Install all components
sudo INSTALL_FFMPEG=yes INSTALL_QDRANT=yes INSTALL_PORTAINER=yes INSTALL_DOZZLE=yes ./docker-n8n.sh

# Minimal installation (only n8n)
sudo INSTALL_FFMPEG=no INSTALL_QDRANT=no INSTALL_PORTAINER=no INSTALL_DOZZLE=no ./docker-n8n.sh

# Custom selection
sudo INSTALL_FFMPEG=yes INSTALL_QDRANT=yes INSTALL_PORTAINER=no INSTALL_DOZZLE=no ./docker-n8n.sh
```

### 6. Piped Execution with Interactive Mode
```bash
# Force interactive mode when piping from curl
curl -fsSL http://sh.mughal.pro/docker-n8n.sh | sudo FORCE_INTERACTIVE=true bash

# Or with cleanup action pre-configured
curl -fsSL http://sh.mughal.pro/docker-n8n.sh | sudo CLEANUP_ACTION=clean bash
```

### 7. DNS Configuration for Subdomain Routing
When using a domain, configure these DNS records:
```
# Main domain (A record)
yourdomain.com        A    YOUR_SERVER_IP

# Subdomains (A records or CNAME)
portainer.yourdomain.com   A    YOUR_SERVER_IP
dozzle.yourdomain.com      A    YOUR_SERVER_IP
qdrant.yourdomain.com      A    YOUR_SERVER_IP

# Alternative: Wildcard (if supported by your DNS provider)
*.yourdomain.com           A    YOUR_SERVER_IP
```

## 🌐 Access Your Services

### With Domain (HTTPS) - Subdomain Routing
- **n8n**: `https://yourdomain.com`
- **Portainer**: `https://portainer.yourdomain.com`
- **Dozzle Logs**: `https://dozzle.yourdomain.com`
- **Qdrant**: `https://qdrant.yourdomain.com`

### Without Domain (HTTP + IP)
- **n8n**: `http://YOUR_SERVER_IP:5678`
- **Portainer**: `http://YOUR_SERVER_IP:9000`
- **Dozzle Logs**: `http://YOUR_SERVER_IP:8080`
- **Qdrant**: `http://YOUR_SERVER_IP:6333`

## 🔐 Default Credentials

### n8n
- **Username**: As configured during setup (default: admin@example.com)
- **Password**: Auto-generated (displayed after installation)

### Portainer
- **First-time Setup**: Access via web UI to create admin account
- **Default Access**: Visit Portainer URL and follow setup wizard
- **Note**: No hardcoded password - secure setup through web interface

### Qdrant Vector Database
- **API Key**: Auto-generated (displayed after installation)
- **Usage**: Required for n8n Qdrant nodes authentication
- **Location**: Available in `/opt/n8n-stack/.env` as `QDRANT_API_KEY`

## 🛠️ Management Commands

After installation, use the management script:

```bash
cd /opt/n8n-stack

# Check status
./manage.sh status

# View logs
./manage.sh logs
./manage.sh logs n8n    # Specific service logs

# Control services
./manage.sh start
./manage.sh stop
./manage.sh restart

# Update containers
./manage.sh update
```

## 🎬 FFmpeg + yt-dlp Integration

FFmpeg and yt-dlp are now integrated directly into the main installation script as optional components.

### Integrated Installation (Recommended)
When running the main installation script, you'll be prompted to install both tools:
```
Install FFmpeg + yt-dlp for video/audio processing and downloading? (recommended for media workflows) [Y/n]:
```

Both FFmpeg and yt-dlp will be built directly into your n8n Docker image, making them immediately available for workflows.

### Pre-configure Media Tools Installation
Skip the interactive prompt by setting the environment variable:
```bash
# Include FFmpeg + yt-dlp in installation
sudo INSTALL_FFMPEG=yes ./docker-n8n.sh

# Skip media tools installation
sudo INSTALL_FFMPEG=no ./docker-n8n.sh
```

### How It Works
- Creates a custom Dockerfile that extends the official n8n image
- Uses Alpine Linux `apk` package manager to install FFmpeg, Python3, and pip
- Installs yt-dlp via pip3 (latest version)
- Builds a custom n8n image `n8n-with-media:latest` with both tools included
- Uses the custom image in your Docker Compose setup

### Common Use Cases in n8n

#### FFmpeg Examples
- **Convert video formats**: `ffmpeg -i input.mp4 output.avi`
- **Extract audio**: `ffmpeg -i video.mp4 -vn -acodec copy audio.aac`
- **Resize video**: `ffmpeg -i input.mp4 -vf scale=1280:720 output.mp4`
- **Create thumbnail**: `ffmpeg -i video.mp4 -ss 00:00:01.000 -vframes 1 thumb.png`
- **Convert audio**: `ffmpeg -i input.wav output.mp3`

#### yt-dlp Examples
- **Download video**: `yt-dlp "https://www.youtube.com/watch?v=VIDEO_ID"`
- **Extract audio only**: `yt-dlp -x --audio-format mp3 "URL"`
- **Download playlist**: `yt-dlp -o "%(uploader)s - %(title)s.%(ext)s" "PLAYLIST_URL"`
- **Get video info**: `yt-dlp --dump-json "URL"`
- **Download with specific quality**: `yt-dlp -f "best[height<=720]" "URL"`

#### Combined Workflows
1. Download video with yt-dlp
2. Process/convert with FFmpeg
3. Upload to storage or send notifications

### Verify Installation
Test both tools availability in your n8n container:
```bash
# Test FFmpeg
docker exec n8n ffmpeg -version

# Test yt-dlp
docker exec n8n yt-dlp --version

# Test Python3 (required for yt-dlp)
docker exec n8n python3 --version
```

### Legacy Standalone Installer
For existing installations that need FFmpeg added later, a standalone installer is available:
```bash
wget https://raw.githubusercontent.com/osamarehman/n8n_docker_script/main/install-ffmpeg-n8n.sh
chmod +x install-ffmpeg-n8n.sh
./install-ffmpeg-n8n.sh
```

> **Note**: The integrated installation method is recommended as it includes both FFmpeg and yt-dlp, and ensures compatibility by building them into the container image during initial setup.

## 🔄 Retry & Error Handling

The script includes comprehensive retry mechanisms:

- **3 automatic retries** for each failed operation
- **User interaction** after failures with options to:
  - Retry again
  - Skip the step (with warning)
  - Exit the script
- **Network timeouts** (30 seconds) for all downloads
- **Safe operation wrappers** for all critical functions

### Example Error Handling Flow
```
[INFO] Attempting Docker Installation (attempt 1/3)...
[WARNING] Docker Installation failed on attempt 1/3 (exit code: 1)
[RETRY] Waiting 5 seconds before retry...
[INFO] Attempting Docker Installation (attempt 2/3)...
[SUCCESS] Docker Installation completed successfully
```

## 🧹 Cleanup & Reinstallation

The script automatically detects existing installations:

### Existing Installation Detected
```
⚠️  An existing n8n installation was detected.

Choose an option:
1) Keep existing installation and exit (k/keep)
2) Clean everything and start fresh (c/clean)
3) Exit without changes (e/exit)
```

### What Gets Cleaned
- All n8n stack containers (stopped and removed)
- All Docker volumes (⚠️ **DATA LOSS**)
- Docker network
- Configuration files in `/opt/n8n-stack`
- Unused Docker images

## 🔧 Troubleshooting

### Common Issues

#### 1. Domain Not Accessible
- Verify DNS points to your server IP
- Check firewall allows ports 80/443
- Wait for SSL certificate generation (can take 2-3 minutes)

#### 2. Container Health Check Failures
- The script waits up to 5 minutes for n8n to be ready
- Check logs: `cd /opt/n8n-stack && ./manage.sh logs n8n`

#### 3. Portainer Login Issues
- Use credentials: `admin` / `admin123456`
- If still failing, restart Portainer: `./manage.sh restart portainer`

#### 4. Network Timeouts
- Script automatically retries with 30-second timeouts
- Check internet connectivity
- Consider running during off-peak hours

#### 5. Domain Concatenation Issues (Fixed in v2.5.1)
- **Problem**: URLs showing as "n8n.domain.com.domain.com" instead of "n8n.domain.com"
- **Solution**: Update to latest script version (v2.5.1+)
- **Manual Fix**: Check `/opt/n8n-stack/.env` for correct subdomain variables

#### 6. Readonly Variable Errors (Fixed in v2.5.1)
- **Problem**: Errors like "N8N_VERSION: readonly variable" during installation
- **Solution**: Update to latest script version (v2.5.1+)
- **Manual Fix**: Remove duplicate version variables from `.env` file if present

### Manual Cleanup
If automatic cleanup fails:
```bash
# Stop all containers
docker stop n8n qdrant dozzle portainer caddy

# Remove containers
docker rm n8n qdrant dozzle portainer caddy

# Remove volumes (⚠️ DATA LOSS)
docker volume rm n8n_data qdrant_data portainer_data caddy_data caddy_config

# Remove network
docker network rm n8n_network

# Remove configuration
rm -rf /opt/n8n-stack
```

## 📁 File Structure

After installation:
```
/opt/n8n-stack/
├── .env                    # Environment variables
├── docker-compose.yml     # Container configuration
├── Caddyfile             # Reverse proxy config (if domain used)
├── manage.sh             # Management script
└── data/                 # Persistent data
    ├── n8n/
    ├── qdrant/
    └── portainer/
```

## 🔒 Security Features

- **Automatic HTTPS** with Let's Encrypt
- **Security headers** via Caddy
- **Firewall configuration** with UFW
- **Container isolation** with Docker networks
- **Non-root container execution** where possible
- **Secure password generation** for n8n

## 🆕 Version History

### v2.5.2-config-optimized (Latest)
- 🔧 **OPTIMIZED**: Added n8n security and performance environment variables:
  - `N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true` - Enhanced file security
  - `DB_SQLITE_POOL_SIZE=5` - Optimized SQLite connection pooling
  - `N8N_RUNNERS_ENABLED=true` - Enabled task runners for better performance
  - `N8N_PROXY_HOPS=1` - Proper proxy trust configuration for Caddy
- 🔧 **IMPROVED**: Removed hardcoded Portainer admin password to allow first-time web UI setup
- 🔧 **ENHANCED**: Better n8n configuration for production environments
- ✅ Resolved n8n warnings about file permissions and SQLite configuration
- ✅ Fixed Portainer first-time setup process
- ✅ Improved container security and performance settings

### v2.5.1-bugfix-enhanced
- 🐛 **FIXED**: Domain concatenation bug causing "n8n.mughal.pro.mughal.pro" instead of "n8n.mughal.pro"
- 🐛 **FIXED**: Readonly variable conflicts in .env file generation
- 🐛 **FIXED**: Docker Compose variable accessibility - exported readonly variables for proper image pulling
- ✅ Enhanced IP detection with multiple fallback services (ifconfig.me → ipv4.icanhazip.com)
- ✅ Improved subdomain URL construction and display
- ✅ Better error handling for missing environment variables
- ✅ Cleaner .env file generation without redundant readonly variables
- ✅ More reliable domain extraction logic for subdomain routing
- ✅ Resolved "variable is not set" warnings during Docker Compose operations

### v2.5.0-subdomain-enhanced
- ✅ Qdrant API key authentication for secure vector database access
- ✅ Subdomain-based routing (replaces path-based routing)
- ✅ Enhanced DNS configuration with wildcard support
- ✅ Improved service isolation and UI compatibility
- ✅ Auto-generated secure API keys for Qdrant integration

### v2.4.0-cleanup-enhanced
- ✅ Comprehensive retry mechanisms (3 attempts + user interaction)
- ✅ Intelligent cleanup system for existing installations
- ✅ Latest container versions with explicit pulling
- ✅ Fixed Portainer authentication
- ✅ Path-based routing for domain setups
- ✅ Enhanced SSL configuration with debugging
- ✅ Smart firewall rules based on configuration
- ✅ Improved error handling and user feedback

### v2.2.0-simplified
- ✅ SQLite database (removed PostgreSQL complexity)
- ✅ Fixed username validation for emails
- ✅ Added Portainer for Docker management
- ✅ Simplified configuration

## 📞 Support

If you encounter issues:

1. **Check the logs**: `cd /opt/n8n-stack && ./manage.sh logs`
2. **Verify system requirements**: Minimum 2GB RAM, 8GB disk
3. **Check network connectivity**: Ensure ports 80/443 are accessible
4. **Review firewall settings**: UFW should allow HTTP/HTTPS traffic
5. **Try cleanup and reinstall**: The script handles this automatically

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## 📄 License

This project is open source and available under the MIT License.
