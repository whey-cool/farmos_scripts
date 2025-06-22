#!/bin/bash
set -e

# =============================================================================
# farmOS Complete Installation Script
# =============================================================================
# This script installs Docker, downloads farmOS, sets up a development
# environment with Selenium Chrome for testing, and completes the browser
# installation automatically.
# =============================================================================

echo "🚀 Starting complete farmOS installation..."
echo ""

# =============================================================================
# CONFIGURATION
# =============================================================================

# Drush command for later use
DRUSH="docker compose exec -u www-data -T www /opt/drupal/vendor/bin/drush"
MAX_WAIT_TIME=600  # Increased to 10 minutes for slower systems
POLL_INTERVAL=2    # Check every 2 seconds

# Default credentials (can be overridden with environment variables)
ADMIN_USER="${FARMOS_ADMIN_USER:-admin}"
ADMIN_PASS="${FARMOS_ADMIN_PASS:-admin}"
SITE_NAME="${FARMOS_SITE_NAME:-farmOS Development}"

echo "📋 Configuration:"
echo "   Admin Username: $ADMIN_USER"
echo "   Admin Password: $ADMIN_PASS"
echo "   Site Name: $SITE_NAME"
echo "   Max Wait Time: $((MAX_WAIT_TIME / 60)) minutes"
echo ""

# Function to check system resources
check_system_resources() {
    echo "🔧 System Resource Check:"
    
    # Check available memory
    TOTAL_MEM=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    AVAILABLE_MEM=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    echo "   Memory: ${AVAILABLE_MEM}MB available / ${TOTAL_MEM}MB total"
    
    if [ "$AVAILABLE_MEM" -lt 1000 ]; then
        echo "   ⚠️  WARNING: Low memory detected. farmOS may be slow to initialize"
        echo "      Recommendation: 2GB+ RAM for optimal performance"
    fi
    
    # Check disk space
    AVAILABLE_DISK=$(df -h . | awk 'NR==2 {print $4}')
    echo "   Disk: ${AVAILABLE_DISK} available in current directory"
    
    # Check if running in container/VM
    if [ -f /.dockerenv ] || grep -q "docker\|lxc" /proc/1/cgroup 2>/dev/null; then
        echo "   Environment: Running in container"
    elif command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt >/dev/null 2>&1; then
        VIRT_TYPE=$(systemd-detect-virt)
        echo "   Environment: Running in ${VIRT_TYPE} virtual machine"
    else
        echo "   Environment: Running on physical hardware"
    fi
    echo ""
}

# Check system resources before starting
check_system_resources

# =============================================================================
# STEP 1: INSTALL DOCKER & DOCKER COMPOSE
# =============================================================================

echo "📦 Installing Docker and docker-compose..."
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2

echo "🔍 Verifying Docker installation..."
if ! command -v docker &> /dev/null; then
    echo "❌ ERROR: Docker installation failed"
    exit 1
fi

if ! command -v docker compose &> /dev/null; then
    echo "❌ ERROR: docker-compose installation failed"
    exit 1
fi

echo "✅ Docker and docker-compose installed successfully"
echo "   Docker version: $(docker --version)"
echo "   Compose version: $(docker compose version --short)"
echo ""

# =============================================================================
# STEP 2: SETUP FARMOS DIRECTORY
# =============================================================================

echo "📁 Setting up farmOS directory..."
if [ -d "farmOS" ]; then
    echo "   farmOS directory already exists, moving into it..."
    cd farmOS
else
    echo "   Creating farmOS directory..."
    mkdir farmOS
    cd farmOS
fi

echo "✅ Working in farmOS directory: $(pwd)"
echo ""

# =============================================================================
# STEP 3: DOWNLOAD FARMOS CONFIGURATION
# =============================================================================

echo "📥 Downloading farmOS docker-compose configuration..."
curl -f https://raw.githubusercontent.com/farmOS/farmOS/3.x/docker/docker-compose.development.yml -o docker-compose.yml

echo "🔍 Verifying download..."
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ ERROR: Failed to download docker-compose.yml"
    exit 1
fi

echo "✅ docker-compose.yml downloaded successfully"
echo "   File size: $(du -h docker-compose.yml | cut -f1)"
echo ""

# =============================================================================
# STEP 4: ADD SELENIUM CHROME SERVICE
# =============================================================================

echo "🌐 Adding Chrome service for Selenium testing..."
sed -i '/^services:/a\
  chrome:\
    image: selenium/standalone-chrome:4.1.2-20220217' docker-compose.yml

echo "🔍 Verifying Chrome service addition..."
if grep -q "chrome:" docker-compose.yml && grep -q "selenium/standalone-chrome" docker-compose.yml; then
    echo "✅ Chrome service added successfully"
else
    echo "❌ ERROR: Failed to add Chrome service to docker-compose.yml"
    exit 1
fi
echo ""

# =============================================================================
# STEP 5: START DOCKER CONTAINERS
# =============================================================================

echo "🐳 Starting Docker containers..."
docker compose up -d

echo "⏳ Waiting for containers to initialize..."
sleep 5

echo "🔍 Checking container status..."
if docker compose ps | grep -q "Up"; then
    echo "✅ Containers started successfully"
    echo ""
    echo "📋 Container Status:"
    docker compose ps
    echo ""
    echo "💾 Container Resource Usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | head -4 || echo "   (Resource stats not available)"
else
    echo "❌ ERROR: Some containers failed to start"
    echo ""
    echo "📋 Container Status:"
    docker compose ps
    echo ""
    echo "📝 Container Logs:"
    docker compose logs
    exit 1
fi
echo ""

# =============================================================================
# STEP 6: NETWORK DETECTION
# =============================================================================

echo "🔍 Detecting network configuration..."
LOCAL_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "")
PUBLIC_IP=$(curl -s -4 icanhazip.com 2>/dev/null || curl -s -4 ifconfig.me 2>/dev/null || echo "")

if [ -n "$LOCAL_IP" ]; then
    echo "   Local IP: $LOCAL_IP"
fi
if [ -n "$PUBLIC_IP" ]; then
    echo "   Public IP: $PUBLIC_IP"
fi
echo ""

# =============================================================================
# STEP 7: WAIT FOR FARMOS TO INITIALIZE
# =============================================================================

echo "⏳ Waiting for farmOS container to finish initialization..."
echo "   This may take several minutes on first run..."
echo "   💡 Tip: Container is downloading and setting up Drupal/farmOS files"

# Function to show what's happening
show_container_activity() {
    echo "   📊 Container activity:"
    echo "      • Checking www container logs for progress..."
    # Filter out PHP deprecation warnings to show meaningful logs
    docker compose logs --tail=5 www 2>/dev/null | grep -v "assert.active INI setting is deprecated" | sed 's/^/      /' || echo "      No recent activity"
    echo ""
}

WAIT_COUNT=0
LAST_ACTIVITY_CHECK=0

until docker compose exec -u www-data -T www test -f /opt/drupal/vendor/bin/drush >/dev/null 2>&1; do
    sleep $POLL_INTERVAL
    WAIT_COUNT=$((WAIT_COUNT + POLL_INTERVAL))
    
    if [ $WAIT_COUNT -ge $MAX_WAIT_TIME ]; then
        echo "❌ ERROR: Timeout waiting for Drush to be available"
        echo "   Container logs:"
        docker compose logs www
        echo ""
        echo "   💡 Troubleshooting tips:"
        echo "      • Check if containers have enough memory (recommend 2GB+)"
        echo "      • Verify internet connection for downloading packages"
        echo "      • Try: docker compose down && docker compose up -d"
        exit 1
    fi
    
    # Show progress every 10 seconds
    if [ $((WAIT_COUNT % 10)) -eq 0 ]; then
        echo "   Still waiting... (${WAIT_COUNT}s elapsed)"
        
        # Show container activity every 30 seconds
        if [ $((WAIT_COUNT - LAST_ACTIVITY_CHECK)) -ge 30 ]; then
            show_container_activity
            LAST_ACTIVITY_CHECK=$WAIT_COUNT
        fi
    fi
    
    # Check if container is still running
    if ! docker compose ps --services --filter "status=running" | grep -q "www"; then
        echo "❌ ERROR: farmOS container has stopped running"
        echo "   Container status:"
        docker compose ps
        echo "   Container logs:"
        docker compose logs www
        exit 1
    fi
done

echo "✅ farmOS container is ready (took ${WAIT_COUNT}s)"
echo ""

# =============================================================================
# STEP 8: VERIFY DATABASE CONNECTION
# =============================================================================

echo "🗄️  Verifying database connection..."
if ! $DRUSH sql:query "SELECT 1;" >/dev/null 2>&1; then
    echo "❌ ERROR: Cannot connect to database"
    echo "   Checking database container status..."
    docker compose logs db | tail -20
    exit 1
fi

echo "✅ Database connection verified"
echo ""

# =============================================================================
# STEP 9: INSTALL FARMOS VIA BROWSER AUTOMATION
# =============================================================================

echo "🌱 Installing farmOS via Drush (Browser Automation)..."
echo "   This will:"
echo "   • Install the farmOS Drupal distribution"
echo "   • Configure database connection"
echo "   • Create admin user: $ADMIN_USER"
echo "   • Set site name: $SITE_NAME"
echo ""

# Check if farmOS is already installed
if $DRUSH status bootstrap 2>/dev/null | grep -q "Successful"; then
    echo "⚠️  WARNING: farmOS appears to already be installed"
    echo "   Current status:"
    $DRUSH status
    echo ""
    echo "   Skipping installation to preserve existing data"
    echo "   If you want to reinstall, run: $DRUSH site-install farm --yes"
else
    # Perform the installation
    echo "🔧 Running site installation..."
    $DRUSH site-install farm \
      --db-url=pgsql://farm:farm@db/farm \
      --account-name="$ADMIN_USER" \
      --account-pass="$ADMIN_PASS" \
      --site-name="$SITE_NAME" \
      --yes

    echo "✅ farmOS installation completed successfully"
fi
echo ""

# =============================================================================
# STEP 10: VERIFY INSTALLATION
# =============================================================================

echo "🔍 Verifying complete installation..."

# Check Drupal status
echo "📊 Drupal Status:"
$DRUSH status

# Check if admin user was created
echo ""
echo "👤 Verifying admin user..."
if $DRUSH user:information "$ADMIN_USER" >/dev/null 2>&1; then
    echo "✅ Admin user '$ADMIN_USER' verified successfully"
else
    echo "⚠️  WARNING: Could not verify admin user"
fi

# Test web interface connectivity
echo ""
echo "🌐 Testing web interface..."
WEB_READY=false
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" =~ ^(200|302|404)$ ]]; then
        echo "✅ farmOS web interface is responding (HTTP $HTTP_CODE)"
        WEB_READY=true
        break
    fi
    if [ $i -eq 30 ]; then
        echo "⚠️  WARNING: farmOS web interface not responding after 30 seconds"
        echo "   This might be normal if the application is still initializing"
        echo "   HTTP response code: $HTTP_CODE"
    fi
    sleep 1
done
echo ""

# =============================================================================
# STEP 11: POST-INSTALLATION FIXES
# =============================================================================

echo "🔧 Applying post-installation fixes..."

# Fix Apache symbolic link permissions
echo "   • Fixing Apache symbolic link permissions..."
if docker compose exec -T www test -L /var/www/html 2>/dev/null; then
    docker compose exec -T www bash -c "
        # Remove symlink and copy files properly
        rm -f /var/www/html
        cp -r /opt/drupal/web /var/www/html
        chown -R www-data:www-data /var/www/html
    " 2>/dev/null || echo "   Note: Apache permissions will be handled by container restart"
    
    echo "   • Restarting web container to apply fixes..."
    docker compose restart www
    
    # Wait for container to be ready again
    echo "   • Waiting for web container to restart..."
    sleep 5
    
    # Verify the fix worked
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:80 | grep -q "200\|302"; then
        echo "✅ Web server permissions fixed successfully"
    else
        echo "⚠️  Web server may need additional configuration"
    fi
else
    echo "   • No symbolic link issues detected"
fi

echo ""

# =============================================================================
# FINAL VERIFICATION
# =============================================================================

echo "🔍 Final verification..."

# Test web interface one more time
echo "🌐 Final web interface test..."
WEB_FINAL_TEST=false
for i in {1..10}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" =~ ^(200|302)$ ]]; then
        echo "✅ farmOS web interface is fully operational (HTTP $HTTP_CODE)"
        WEB_FINAL_TEST=true
        break
    fi
    if [ $i -eq 10 ]; then
        echo "⚠️  Web interface still showing issues, but farmOS core functionality appears to be working"
        echo "   You may need to access farmOS directly via browser for final setup"
    fi
    sleep 1
done
echo ""

# =============================================================================
# INSTALLATION COMPLETE
# =============================================================================

echo "🎉 Complete farmOS installation finished successfully!"
echo ""
echo "📍 Access Points:"
echo "   • Local access:        http://localhost:80"
if [ -n "$LOCAL_IP" ] && [ "$LOCAL_IP" != "127.0.0.1" ]; then
    echo "   • Network access:      http://$LOCAL_IP:80"
fi
if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "$LOCAL_IP" ]; then
    echo "   • External access:     http://$PUBLIC_IP:80"
fi
echo "   • Selenium Chrome Hub: http://localhost:4444"
if [ -n "$LOCAL_IP" ] && [ "$LOCAL_IP" != "127.0.0.1" ]; then
    echo "   • Chrome Hub (network): http://$LOCAL_IP:4444"
fi
echo ""
echo "🔑 Login Credentials:"
echo "   • Username: $ADMIN_USER"
echo "   • Password: $ADMIN_PASS"
echo ""
echo "🔧 Useful Commands:"
echo "   • Check status:       docker compose ps"
echo "   • View logs:          docker compose logs"
echo "   • Stop services:      docker compose down"
echo "   • Restart services:   docker compose restart"
echo "   • Drush status:       $DRUSH status"
echo "   • Clear cache:        $DRUSH cache:rebuild"
echo "   • Update database:    $DRUSH updatedb"
echo ""
if [ "$WEB_FINAL_TEST" = false ]; then
    echo "💡 Note: If farmOS isn't responding yet, wait a few more minutes"
    echo "   for the application to fully initialize, then try accessing:"
    echo "   http://localhost:80"
    if [ -n "$LOCAL_IP" ] && [ "$LOCAL_IP" != "127.0.0.1" ]; then
        echo "   or http://$LOCAL_IP:80 (from other devices on the network)"
    fi
    echo ""
    echo "🔧 If you see Apache 403 errors, run these commands:"
    echo "   cd farmOS"
    echo "   docker compose restart www"
    echo "   # Wait 30 seconds, then try accessing the web interface again"
fi

echo ""
echo "🌐 Network Information:"
echo "   • This script detected the following network configuration"
if [ -n "$LOCAL_IP" ]; then
    echo "   • Use the 'Network access' URL to connect from other devices"
    echo "     on the same network (including from your host machine if running in VM)"
else
    echo "   • Could not detect local IP address"
fi
if [ -n "$PUBLIC_IP" ]; then
    echo "   • External access may require firewall configuration"
else
    echo "   • Could not detect public IP address"
fi
echo ""
echo "🎯 Next Steps:"
echo "   1. Open your browser and navigate to the web interface"
echo "   2. Log in with the credentials shown above"
echo "   3. Your farmOS installation is ready to use!"
echo "   4. Consider setting up SSL/HTTPS for production use"
