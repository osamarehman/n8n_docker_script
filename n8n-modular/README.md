# n8n Modular Docker Stack

A modular, production-ready Docker setup for n8n workflow automation with optional components that can be installed independently or together.

## 🎯 Overview

This modular stack provides a flexible way to deploy n8n with various supporting services. Each component can be installed standalone or as part of a complete stack.

### Available Components

- **n8n** - Core workflow automation platform (required)
- **Caddy** - Reverse proxy with automatic HTTPS
- **Qdrant** - Vector database for AI/ML workflows  
- **Portainer** - Docker management web interface
- **Watchtower** - Automatic container updates

## 🚀 Quick Start

### Complete Stack Installation

Install everything with domain-based HTTPS:
```bash
sudo ./install-stack.sh
```

Install minimal stack (n8n only):
```bash
sudo ./install-stack.sh --minimal
```

### Individual Component Installation

Each component can be installed independently:

```bash
# Install n8n only
sudo ./scripts/install-n8n.sh

# Add reverse proxy with HTTPS
sudo ./scripts/install-caddy.sh

# Add vector database
sudo ./scripts/install-qdrant.sh

# Add Docker management UI
sudo ./scripts/install-portainer.sh

# Add automatic updates
sudo ./scripts/install-watchtower.sh
```

## 📋 Requirements

- Ubuntu 20.04+ or similar Linux distribution
- 2GB+ RAM (4GB+ recommended)
- 8GB+ available disk space
- Root access (`sudo`)
- Domain name (optional, for HTTPS)

## 🌐 Access Methods

### With Domain (HTTPS)
- n8n: `https://n8n.yourdomain.com`
- Portainer: `https://portainer.yourdomain.com`
- Qdrant: `https://qdrant.yourdomain.com`

### Without Domain (HTTP)
- n8n: `http://your-server-ip:5678`
- Portainer: `http://your-server-ip:9000`
- Qdrant: `http://your-server-ip:6333`

## 🛠️ Management

### Stack Management
```bash
# Show status
./manage-stack.sh status

# Start/stop all services
./manage-stack.sh start
./manage-stack.sh stop

# Update all components
./manage-stack.sh update

# View logs
./manage-stack.sh logs

# Create backup
./manage-stack.sh backup

# Show access URLs and info
./manage-stack.sh info
```

### Individual Component Management
Each component has its own management script:
```bash
# n8n management
docker compose -f /opt/n8n-stack/docker-compose.n8n.yml {start|stop|restart|logs}

# Component-specific management scripts (when available)
./manage-portainer.sh {start|stop|backup|restore}
./manage-qdrant.sh {status|test}
./manage-watchtower.sh {force-update|schedule|exclude}
```

## 📂 File Structure

```
n8n-modular/
├── install-stack.sh           # Master installation script
├── common/
│   └── utils.sh              # Shared utilities and functions
├── scripts/
│   ├── install-n8n.sh       # n8n standalone installer
│   ├── install-caddy.sh     # Caddy reverse proxy installer
│   ├── install-qdrant.sh    # Qdrant vector DB installer
│   ├── install-portainer.sh # Portainer management installer
│   └── install-watchtower.sh# Watchtower auto-update installer
└── README.md                 # This file
```

## 🔧 Configuration

### Environment Variables

Set these before installation to customize the setup:

```bash
# Domain configuration
export MAIN_DOMAIN="yourdomain.com"
export N8N_SUBDOMAIN="n8n"
export PORTAINER_SUBDOMAIN="portainer" 
export QDRANT_SUBDOMAIN="qdrant"

# Component selection
export INSTALL_QDRANT="yes"
export INSTALL_PORTAINER="yes"
export INSTALL_WATCHTOWER="yes"
export INSTALL_CADDY="yes"

# Then run installation
sudo -E ./install-stack.sh --auto
```

### DNS Configuration (for HTTPS)

Before installing with a domain, configure these DNS A records:
```
n8n.yourdomain.com        → your-server-ip
portainer.yourdomain.com  → your-server-ip
qdrant.yourdomain.com     → your-server-ip
```

## 🔒 Security Features

- Automatic HTTPS with Let's Encrypt SSL certificates
- API key authentication for Qdrant
- Secure password generation for all services
- Security headers via Caddy
- Firewall configuration (UFW)
- Non-root container execution where possible

## 📊 Monitoring & Maintenance

### Logs
```bash
# Stack logs
./manage-stack.sh logs

# Individual component logs
docker logs n8n
docker logs caddy
docker logs qdrant
docker logs portainer
docker logs watchtower
```

### Health Checks
```bash
# Stack status
./manage-stack.sh status

# Test Qdrant (if installed)
/opt/n8n-stack/test-qdrant.sh

# Container health
docker ps
```

### Backups
```bash
# Create full stack backup
./manage-stack.sh backup

# Restore from backup
./manage-stack.sh restore backup-file.tar.gz

# Component-specific backups
./manage-portainer.sh backup
```

## 🔄 Updates

### Automatic Updates (Watchtower)
If Watchtower is installed, containers automatically update when new versions are available.

```bash
# Check Watchtower status
./manage-watchtower.sh status

# Force immediate update check
./manage-watchtower.sh force-update

# Exclude a container from updates
./manage-watchtower.sh exclude container-name
```

### Manual Updates
```bash
# Update all components
./manage-stack.sh update

# Update specific component
./manage-stack.sh update n8n
```

## 🆘 Troubleshooting

### Common Issues

**Permission Problems**
```bash
# Fix n8n volume permissions
/opt/n8n-stack/manage-stack.sh stop
docker run --rm -v n8n_data:/fix alpine chown -R 1000:1000 /fix
/opt/n8n-stack/manage-stack.sh start
```

**SSL Certificate Issues**
```bash
# Check Caddy logs
docker logs caddy

# Verify DNS configuration
dig n8n.yourdomain.com

# Restart Caddy
docker restart caddy
```

**Service Not Starting**
```bash
# Check logs
./manage-stack.sh logs component-name

# Check container status
docker ps -a

# Restart specific service
./manage-stack.sh restart component-name
```

### Support Commands
```bash
# Full system status
./manage-stack.sh status

# Component information
./manage-stack.sh info

# Stack diagnostics
docker compose -f /opt/n8n-stack/docker-compose.*.yml ps
docker stats --no-stream
```

## 🧹 Cleanup

### Remove Individual Components
```bash
# Remove specific component
sudo ./scripts/install-component.sh --cleanup
```

### Remove Entire Stack
```bash
# Remove everything
sudo ./install-stack.sh --cleanup
```

## 📚 Documentation Links

- [n8n Documentation](https://docs.n8n.io/)
- [n8n Community Forum](https://community.n8n.io/)
- [Caddy Documentation](https://caddyserver.com/docs/)
- [Qdrant Documentation](https://qdrant.tech/documentation/)
- [Portainer Documentation](https://docs.portainer.io/)
- [Watchtower Documentation](https://containrrr.dev/watchtower/)

## 🤝 Contributing

This modular setup is designed to be easily extensible. To add new components:

1. Create a new installation script in `scripts/`
2. Follow the existing patterns for configuration and deployment
3. Source the common utilities from `common/utils.sh`
4. Update the master `install-stack.sh` to include your component

## 📄 License

This project is provided as-is for educational and production use. Individual components may have their own licenses.

---

**Note**: This modular approach allows you to start small (just n8n) and add components as needed. Each script can run independently, making it easy to maintain and extend your setup over time.