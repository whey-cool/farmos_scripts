#!/bin/bash
set -euo pipefail

# =============================================================================
# farmOS Browser Installation Setup Script
# =============================================================================
# Automate the web-based farmOS installation using Drush.
# Requires the Docker Compose environment from docs/development/environment.
# Run this script from the directory that contains `docker-compose.yml`.
# =============================================================================

echo "🚀 Starting farmOS browser installation setup..."
echo ""

# =============================================================================
# CONFIGURATION
# =============================================================================

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
# STEP 1: VERIFY ENVIRONMENT
# =============================================================================

echo "🔍 Verifying environment..."

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ ERROR: docker-compose.yml not found in current directory"
    echo "   Please run this script from the directory containing docker-compose.yml"
    exit 1
fi

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ ERROR: Docker is not running or not accessible"
    echo "   Please ensure Docker is installed and running"
    exit 1
fi

echo "✅ Environment verification passed"
echo ""

# =============================================================================
# STEP 2: START CONTAINERS
# =============================================================================

echo "🐳 Ensuring containers are running..."
docker compose up -d

echo "🔍 Checking container status..."
if ! docker compose ps | grep -q "Up"; then
    echo "❌ ERROR: Containers failed to start"
    docker compose ps
    exit 1
fi

echo "✅ Containers are running"
docker compose ps
echo ""

# =============================================================================
# STEP 3: WAIT FOR SERVICES TO INITIALIZE
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
# STEP 4: VERIFY DATABASE CONNECTION
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
# STEP 5: INSTALL FARMOS
# =============================================================================

echo "🌱 Installing farmOS via Drush..."
echo "   This will:"
echo "   • Install the farmOS Drupal distribution"
echo "   • Configure database connection"
echo "   • Create admin user: $ADMIN_USER"
echo "   • Set site name: $SITE_NAME"
echo ""

# Check if farmOS is already installed
if $DRUSH status bootstrap | grep -q "Successful"; then
    echo "⚠️  WARNING: farmOS appears to already be installed"
    echo "   Current status:"
    $DRUSH status
    echo ""
    read -p "   Do you want to reinstall? This will destroy existing data! (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "   Installation cancelled by user"
        exit 0
    fi
    echo "   Proceeding with reinstallation..."
fi

# Perform the installation
echo "🔧 Running site installation..."
$DRUSH site-install farm \
  --db-url=pgsql://farm:farm@db/farm \
  --account-name="$ADMIN_USER" \
  --account-pass="$ADMIN_PASS" \
  --site-name="$SITE_NAME" \
  --yes

echo "✅ farmOS installation completed successfully"
echo ""

# =============================================================================
# STEP 6: VERIFY INSTALLATION
# =============================================================================

echo "🔍 Verifying installation..."

# Check Drupal status
echo "📊 Drupal Status:"
$DRUSH status

# Check if admin user was created
echo ""
echo "👤 Verifying admin user..."
if $DRUSH user:information "$ADMIN_USER" >/dev/null 2>&1; then
    echo "✅ Admin user '$ADMIN_USER' created successfully"
else
    echo "⚠️  WARNING: Could not verify admin user creation"
fi

# Test web interface connectivity
echo ""
echo "🌐 Testing web interface..."
if curl -s -o /dev/null -w "%{http_code}" http://localhost:80 | grep -q "200\|302"; then
    echo "✅ Web interface is responding"
else
    echo "⚠️  WARNING: Web interface may not be ready yet"
fi

echo ""

# =============================================================================
# INSTALLATION COMPLETE
# =============================================================================

echo "🎉 farmOS browser installation setup completed successfully!"
echo ""
echo "📍 Access Information:"
echo "   • Web Interface: http://localhost:80"

# Detect IP addresses for better user guidance (similar to main script)
LOCAL_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "")
if [ -n "$LOCAL_IP" ] && [ "$LOCAL_IP" != "127.0.0.1" ]; then
    echo "   • Network Access: http://$LOCAL_IP:80"
fi

echo ""
echo "🔑 Login Credentials:"
echo "   • Username: $ADMIN_USER"
echo "   • Password: $ADMIN_PASS"
echo ""
echo "🔧 Useful Commands:"
echo "   • Check status:     $DRUSH status"
echo "   • Clear cache:      $DRUSH cache:rebuild"
echo "   • Update database:  $DRUSH updatedb"
echo "   • View logs:        docker compose logs www"
echo ""
echo "💡 Next Steps:"
echo "   1. Open your browser and navigate to the web interface"
echo "   2. Log in with the credentials above"
echo "   3. Complete any additional farmOS configuration as needed"
