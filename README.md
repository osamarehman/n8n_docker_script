# n8n Production Stack - Enhanced with Retry Logic & Cleanup

A comprehensive, production-ready deployment script for n8n workflow automation platform with built-in retry mechanisms, cleanup functionality, and automatic SSL configuration.

## 🚀 Features

- **n8n Workflow Automation** - Latest version with SQLite database
- **Qdrant Vector Database** - For AI/ML workflows
- **Automatic HTTPS** - Let's Encrypt SSL certificates via Caddy
- **Container Management** - Portainer for Docker management
- **Log Monitoring** - Dozzle for real-time container logs
- **Comprehensive Retry Logic** - 3-attempt retry system for all operations
- **Intelligent Cleanup** - Detects and handles existing installations
- **Path-based Routing** - Access all services through subpaths when using domain
- **Latest Container Versions** - Always pulls the most recent images

## 📋 Prerequisites

- **VPS Requirements:**
  - Minimum 2GB RAM
  - Minimum 8GB disk space
  - Ubuntu/Debian Linux
  - Root access

- **Network Requirements:**
  - Domain name (optional, for HTTPS)
  - DNS pointing to your server IP
  - Ports 80, 443 open for HTTPS

## 🔧 Configuration Variables

Before running the script, you may want to customize these variables in the script:

### Required Configuration (Interactive Prompts)
```bash
N8N_DOMAIN=""        # Your domain (e.g., "n8n.yourdomain.com") - leave empty for IP access
N8N_USER=""          # Admin username/email (default: admin@example.com)
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

## 🌐 Access Your Services

### With Domain (HTTPS)
- **n8n**: `https://yourdomain.com`
- **Portainer**: `https://yourdomain.com/portainer`
- **Dozzle Logs**: `https://yourdomain.com/dozzle`
- **Qdrant**: `https://yourdomain.com/qdrant`

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
- **Username**: `admin`
- **Password**: `admin123456`

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
