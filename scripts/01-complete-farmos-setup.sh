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
MAX_WAIT_TIME=300  # Maximum wait time in seconds (5 minutes)
POLL_INTERVAL=2    # Check every 2 seconds

# Default credentials (can be overridden with environment variables)
ADMIN_USER="${FARMOS_ADMIN_USER:-admin}"
ADMIN_PASS="${FARMOS_ADMIN_PASS:-admin}"
SITE_NAME="${FARMOS_SITE_NAME:-farmOS Development}"

echo "📋 Configuration:"
echo "   Admin Username: $ADMIN_USER"
echo "   Admin Password: $ADMIN_PASS"
echo "   Site Name: $SITE_NAME"
echo ""

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

WAIT_COUNT=0
until docker compose exec -u www-data -T www test -f /opt/drupal/vendor/bin/drush >/dev/null 2>&1; do
    sleep $POLL_INTERVAL
    WAIT_COUNT=$((WAIT_COUNT + POLL_INTERVAL))
    
    if [ $WAIT_COUNT -ge $MAX_WAIT_TIME ]; then
        echo "❌ ERROR: Timeout waiting for Drush to be available"
        echo "   Container logs:"
        docker compose logs www
        exit 1
    fi
    
    if [ $((WAIT_COUNT % 10)) -eq 0 ]; then
        echo "   Still waiting... (${WAIT_COUNT}s elapsed)"
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
if [ "$WEB_READY" = false ]; then
    echo "💡 Note: If farmOS isn't responding yet, wait a few more minutes"
    echo "   for the application to fully initialize, then try accessing:"
    echo "   http://localhost:80"
    if [ -n "$LOCAL_IP" ] && [ "$LOCAL_IP" != "127.0.0.1" ]; then
        echo "   or http://$LOCAL_IP:80 (from other devices on the network)"
    fi
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
echo "�� Next Steps:"
echo "   1. Open your browser and navigate to the web interface"
echo "   2. Log in with the credentials shown above"
echo "   3. Your farmOS installation is ready to use!"
echo "   4. Consider setting up SSL/HTTPS for production use"
