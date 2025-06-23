# HerdMate - farmOS Installation Scripts

🚀 **Complete farmOS installation and setup automation for development and production environments.**

## Overview

HerdMate provides a comprehensive set of scripts to automatically install, configure, and deploy farmOS with Docker. Perfect for development environments, VMs, and production deployments.

## Features

- ✅ **One-Command Installation**: Complete farmOS setup from scratch
- ✅ **Docker Integration**: Automated Docker and docker-compose installation
- ✅ **Browser Automation**: Automated farmOS installation via Drush
- ✅ **Selenium Testing**: Chrome/Selenium integration for automated testing
- ✅ **Network Detection**: Smart IP detection for VM/remote deployments
- ✅ **System Monitoring**: Resource checking and performance optimization
- ✅ **Error Handling**: Comprehensive error detection and recovery
- ✅ **VM-Friendly**: Optimized for virtual machine deployments

## Quick Start

### Complete Installation (Recommended)

```bash
# Download and run the complete installation script
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/herdmate/main/complete-farmos-installation.sh
chmod +x complete-farmos-installation.sh
./complete-farmos-installation.sh
```

### Custom Configuration

```bash
# Set custom credentials and site name
FARMOS_ADMIN_USER="myadmin" \
FARMOS_ADMIN_PASS="securepassword" \
FARMOS_SITE_NAME="My Farm Management System" \
./complete-farmos-installation.sh
```

## Scripts

### Main Installation Script

- **`complete-farmos-installation.sh`** - Complete farmOS installation with all features

### Additional Scripts

- **`scripts/01-complete-farmos-setup.sh`** - Alternative setup script
- **`scripts/03-run-installation-tests.sh`** - Installation verification tests
- **`scripts/04-setup-browser.sh`** - Browser-based farmOS setup automation
- **`scripts/05-setup-farmos-integration.sh`** - farmOS integration setup

## Installation Steps

The complete installation script performs these steps automatically:

1. **System Resource Check** - Verifies memory, disk space, and environment
2. **Docker Installation** - Installs Docker and docker-compose
3. **Directory Setup** - Creates and manages farmOS directory structure
4. **Configuration Download** - Downloads farmOS docker-compose configuration
5. **Selenium Integration** - Adds Chrome service for testing
6. **Container Startup** - Starts all Docker containers
7. **Network Detection** - Detects local and public IP addresses
8. **farmOS Initialization** - Waits for farmOS container to be ready
9. **Database Verification** - Verifies database connectivity
10. **Automated Installation** - Installs farmOS via Drush automation
11. **Post-Installation Fixes** - Applies Apache permission fixes
12. **Final Verification** - Comprehensive system verification

## System Requirements

- **OS**: Ubuntu/Debian Linux (tested on Ubuntu 20.04+)
- **RAM**: 2GB+ recommended (1GB minimum)
- **Disk**: 10GB+ available space
- **Network**: Internet connection for downloading packages

## Environment Variables

Customize the installation with these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `FARMOS_ADMIN_USER` | `admin` | farmOS admin username |
| `FARMOS_ADMIN_PASS` | `admin` | farmOS admin password |
| `FARMOS_SITE_NAME` | `farmOS Development` | Site name |

## Access Points

After installation, farmOS will be available at:

- **Local access**: http://localhost:80
- **Network access**: http://YOUR_IP:80 (detected automatically)
- **Selenium Hub**: http://localhost:4444

## Troubleshooting

### Common Issues

**Apache 403 Errors:**
```bash
cd farmOS
docker compose restart www
# Wait 30 seconds, then try accessing the web interface
```

**Container Issues:**
```bash
# Check container status
docker compose ps

# View logs
docker compose logs

# Restart all services
docker compose restart
```

**Memory Issues:**
- Ensure at least 2GB RAM available
- Close unnecessary applications
- Consider upgrading VM memory

### Useful Commands

```bash
# Check system status
docker compose ps

# View application logs
docker compose logs www

# Access farmOS container
docker compose exec www bash

# Run Drush commands
docker compose exec -u www-data www /opt/drupal/vendor/bin/drush status

# Stop all services
docker compose down

# Start services
docker compose up -d
```

## Development

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Testing

Run the installation tests:
```bash
./scripts/03-run-installation-tests.sh
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- **Issues**: Report bugs and feature requests via GitHub Issues
- **Documentation**: See the [farmOS documentation](https://farmOS.org/guide/)
- **Community**: Join the [farmOS community](https://farmOS.org/community/)

## Acknowledgments

- [farmOS](https://farmOS.org/) - The farm management platform
- [Docker](https://docker.com/) - Containerization platform
- [Drupal](https://drupal.org/) - Content management framework

---

**Made with ❤️ for sustainable farming and agricultural technology**
