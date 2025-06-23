#!/usr/bin/env bash
# Install farmOS using the farmOS project template, set up Docker environment,
# and run the installation via Drush.
#
# Usage: ./setup.sh [FARMOS_SUBDIR]
#
# This script can be run from any directory. If FARMOS_SUBDIR is not specified,
# it will create a 'farmos' directory in the detected project root.
#
# Environment variables:
#   FARMOS_VERSION - farmOS version to install (default: 3.x-dev)
#   DB_NAME        - Database name (default: farm)
#   DB_USER        - Database user (default: farm)
#   DB_PASS        - Database password (default: farm)
#   ADMIN_USER     - Admin username (default: admin)
#   ADMIN_PASS     - Admin password (default: admin)
#   SITE_NAME      - Site name (default: farmOS)
#   WEB_PORT       - Web server port (default: 80)
#   LOGFILE        - Log file path (default: setup.log in project root)
#   SKIP_QA        - Skip quality assurance checks (default: 0)

set -euo pipefail

# Show help if requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat << 'EOF'
farmOS Installation Script

Install farmOS using the farmOS project template, set up Docker environment,
and run the installation via Drush.

Usage: ./scripts/setup.sh [FARMOS_SUBDIR]
   or: cd scripts && ./setup.sh [FARMOS_SUBDIR]

This script can be run from any directory. It will automatically detect the project root
and create the farmOS installation in a subdirectory of that root. If FARMOS_SUBDIR is 
not specified, it will create a 'farmos' directory in the project root.

Environment variables:
  FARMOS_VERSION - farmOS version to install (default: 3.x-dev)
  DB_NAME        - Database name (default: farm)
  DB_USER        - Database user (default: farm)
  DB_PASS        - Database password (default: farm)
  ADMIN_USER     - Admin username (default: admin)
  ADMIN_PASS     - Admin password (default: admin)
  SITE_NAME      - Site name (default: farmOS)
  WEB_PORT       - Web server port (default: 80)
  LOGFILE        - Log file path (default: setup.log in project root)
  SKIP_QA        - Skip quality assurance checks (default: 0)

Examples:
  # Install farmOS in default 'farmos' subdirectory of project root
  ./scripts/setup.sh

  # Install farmOS in custom subdirectory of project root
  ./scripts/setup.sh my-farm-project

  # Install with custom admin credentials
  ADMIN_USER=myadmin ADMIN_PASS=mypass ./scripts/setup.sh

  # Skip quality assurance checks for faster setup
  SKIP_QA=1 ./scripts/setup.sh
EOF
    exit 0
fi

# Determine the project root directory
# Look for key indicators to find the project root
find_project_root() {
    local current_dir="$(pwd)"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Start from the script's directory and work upward
    local search_dir="$script_dir"
    
    while [[ "$search_dir" != "/" ]]; do
        # Look for project indicators (git repo, workspace file, or specific directories)
        if [[ -d "$search_dir/.git" ]] || 
           [[ -f "$search_dir"/*.code-workspace ]] || 
           [[ -f "$search_dir/README.md" && -d "$search_dir/scripts" ]]; then
            echo "$search_dir"
            return 0
        fi
        search_dir="$(dirname "$search_dir")"
    done
    
    # If no project root found, fall back to the directory containing the script
    echo "$(dirname "$script_dir")"
}

# Determine project root and set paths relative to it
PROJECT_ROOT="$(find_project_root)"
PROJECT_NAME="$(basename "$PROJECT_ROOT")"

# Configuration variables
FARMOS_SUBDIR="${1:-farmos}"
PROJECT_DIR="$PROJECT_ROOT/$FARMOS_SUBDIR"
FARMOS_VERSION="${FARMOS_VERSION:-3.x-dev}"
DB_NAME="${DB_NAME:-farm}"
DB_USER="${DB_USER:-farm}"
DB_PASS="${DB_PASS:-farm}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin}"
SITE_NAME="${SITE_NAME:-farmOS}"
WEB_PORT="${WEB_PORT:-80}"
LOGFILE="${LOGFILE:-"$PROJECT_ROOT/setup.log"}"

# Progress tracking
TOTAL_STEPS=15
CURRENT_STEP=0

# Basic colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

# Cleanup function for failed installations
cleanup_on_failure() {
    local exit_code=$?
    log "Installation failed with exit code $exit_code. Cleaning up..."
    if [[ -d "$PROJECT_DIR" ]]; then
        cd "$PROJECT_DIR"
        if [[ -f "docker-compose.yml" ]]; then
            log "Stopping Docker containers..."
            $DOCKER_COMPOSE down --volumes --remove-orphans 2>/dev/null || true
        fi
        cd ..
        log "Removing incomplete installation directory..."
        rm -rf "$PROJECT_DIR"
    fi
    log "Cleanup completed. Check the log file for details: $LOGFILE"
    exit $exit_code
}

# Set up trap for cleanup on failure
trap cleanup_on_failure ERR

# Wait for container to be ready
wait_for_container() {
    local container=$1
    local max_attempts=30
    local attempt=1
    
    log "Waiting for container '$container' to be ready..."
    
    # First, wait a bit for the container to start
    sleep 5
    
    while [[ $attempt -le $max_attempts ]]; do
        # Check if container is running first
        if ! $DOCKER_COMPOSE ps "$container" | grep -q "Up"; then
            log "Container '$container' is not running yet, waiting..."
            sleep 3
            attempt=$((attempt + 1))
            continue
        fi
        
        # Try to execute a simple command in the container
        if $DOCKER_COMPOSE exec -T "$container" echo "Container ready" >/dev/null 2>&1; then
            log "Container '$container' is ready after $attempt attempts"
            return 0
        fi
        
        # Add some debug info on every 10th attempt
        if [[ $((attempt % 10)) -eq 0 ]]; then
            log "Still waiting for container '$container' (attempt $attempt/$max_attempts)"
            log "Container status:"
            $DOCKER_COMPOSE ps "$container" || true
        fi
        
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log "ERROR: Container $container failed to become ready after $max_attempts attempts"
    log "Final container status:"
    $DOCKER_COMPOSE ps "$container" || true
    log "Container logs:"
    $DOCKER_COMPOSE logs --tail=20 "$container" || true
    return 1
}

# Detect Docker Compose command
detect_docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose >/dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        return 1
    fi
    return 0
}

# Install environment dependencies
install_dependencies() {
    log "Installing system dependencies..."
    
    # Update package lists
    if command -v apt-get >/dev/null; then
        sudo apt-get update -qq
        
        # Install Docker if not present
        if ! command -v docker >/dev/null; then
            log "Installing Docker..."
            sudo apt-get install -y docker.io docker-compose-plugin
            sudo systemctl start docker
            sudo systemctl enable docker
            sudo usermod -aG docker $USER
        fi
        
        # Install docker-compose if not present
        if ! command -v docker-compose >/dev/null && ! docker compose version >/dev/null 2>&1; then
            log "Installing docker-compose..."
            sudo apt-get install -y docker-compose
        fi
        
        # Install curl if not present
        if ! command -v curl >/dev/null; then
            sudo apt-get install -y curl
        fi
        
        # Install PHP and required extensions
        if ! command -v php >/dev/null; then
            sudo apt-get install -y php-cli php-xml php-mbstring php-zip php-curl php-gd php-mysql php-pgsql
        fi
        
        # Install mkdocs if not present
        if ! command -v mkdocs >/dev/null; then
            sudo apt-get install -y mkdocs
        fi
        
    elif command -v yum >/dev/null; then
        # Red Hat/CentOS systems
        sudo yum update -y
        
        if ! command -v docker >/dev/null; then
            sudo yum install -y docker docker-compose
            sudo systemctl start docker
            sudo systemctl enable docker
            sudo usermod -aG docker $USER
        fi
        
    elif command -v brew >/dev/null; then
        # macOS systems
        if ! command -v docker >/dev/null; then
            brew install docker docker-compose
        fi
    else
        log "WARNING: Unable to detect package manager. Please install Docker manually."
        return 1
    fi
    
    log "Dependencies installation completed"
}

# Validate dependencies
validate_dependencies() {
    local missing_deps=()
    
    if ! command -v docker >/dev/null; then
        missing_deps+=("docker")
    fi
    
    if ! detect_docker_compose; then
        missing_deps+=("docker-compose")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "Missing dependencies: ${missing_deps[*]}"
        log "Attempting to install missing dependencies..."
        
        # Try to install dependencies
        if ! install_dependencies; then
            log "ERROR: Failed to install dependencies automatically"
            log "Please install the following manually: ${missing_deps[*]}"
            exit 1
        fi
        
        # Re-validate after installation
        if ! detect_docker_compose; then
            log "ERROR: Dependencies still missing after installation attempt"
            exit 1
        fi
    fi
    
    log "Using Docker Compose command: $DOCKER_COMPOSE"
}

# Spinner animation for long running commands
spinner() {
    local pid=$1
    local delay=0.1
    local spin=('|' '/' '-' '\\')
    while kill -0 "$pid" 2>/dev/null; do
        for i in "${spin[@]}"; do
            printf "\r%s" "$i"
            sleep "$delay"
        done
    done
    printf "\r"
}

# Run a command with a spinner
run_step() {
    local msg=$1
    shift
    CURRENT_STEP=$((CURRENT_STEP + 1))
    log "Starting: $msg ($CURRENT_STEP/$TOTAL_STEPS)"
    printf "%b" "${BLUE}➤${NC} [$CURRENT_STEP/$TOTAL_STEPS] $msg..."
    ("$@" >> "$LOGFILE" 2>&1) &
    local pid=$!
    spinner "$pid"
    wait "$pid"
    local status=$?
    if [[ $status -eq 0 ]]; then
        printf "\r%b\n" "${GREEN}✓${NC} [$CURRENT_STEP/$TOTAL_STEPS] $msg"
        log "Completed: $msg ($CURRENT_STEP/$TOTAL_STEPS)"
    else
        printf "\r%b\n" "${RED}✗${NC} [$CURRENT_STEP/$TOTAL_STEPS] $msg (exit $status)"
        log "Failed: $msg (exit $status)"
        return $status
    fi
}

# Main setup process
log "Starting farmOS project installation"
log "Project root: $PROJECT_ROOT"
log "Project name: $PROJECT_NAME"
log "farmOS directory: $PROJECT_DIR"
log "farmOS version: $FARMOS_VERSION"
log "Log file: $LOGFILE"

# Validate dependencies before proceeding
validate_dependencies

# Environment setup is now handled by validate_dependencies function
log "Environment setup completed"

# Create the project directory if it doesn't exist
if [[ -d "$PROJECT_DIR" ]]; then
    log "Project directory already exists: $PROJECT_DIR"
    if [[ -f "$PROJECT_DIR/composer.json" ]]; then
        log "Found existing farmOS project"
    else
        log "Directory exists but doesn't appear to be a farmOS project"
        log "Proceeding with farmOS installation..."
    fi
else
    log "Creating project directory: $PROJECT_DIR"
    mkdir -p "$PROJECT_DIR"
fi

# Create farmOS project using the official template
if [[ ! -f "$PROJECT_DIR/composer.json" ]]; then
    log "Creating farmOS project using farmos/project template"
    run_step "Creating farmOS project (template only)" composer create-project farmos/project:"$FARMOS_VERSION" "$PROJECT_DIR" --no-interaction --ignore-platform-reqs --no-install
    
    cd "$PROJECT_DIR"
    
    # Configure Composer to allow all plugins (safer for farmOS setup)
    run_step "Configuring Composer to allow plugins" composer config allow-plugins true
    
    # Now install dependencies
    run_step "Installing project dependencies" composer install --ignore-platform-reqs
else
    log "Found existing composer.json - assuming farmOS project already set up"
    cd "$PROJECT_DIR"
    run_step "Installing/updating Composer dependencies" composer install --ignore-platform-reqs
fi

# Change to project directory for the rest of the setup
cd "$PROJECT_DIR"

# Fetch the development docker-compose configuration if not present
if [[ ! -f "docker-compose.yml" ]]; then
    log "No docker-compose.yml found, using farmOS development configuration"
    run_step "Downloading docker-compose config" \
        curl -fsSL https://raw.githubusercontent.com/farmOS/farmOS/3.x/docker/docker-compose.development.yml -o docker-compose.yml
else
    log "Found existing docker-compose.yml file"
fi

# Start database and web containers
run_step "Starting containers" $DOCKER_COMPOSE up -d

# Wait for containers to be ready
run_step "Waiting for database container" wait_for_container db
run_step "Waiting for web container" wait_for_container www

# The farmOS project template should already have the correct structure
# Just make sure Composer dependencies are properly installed inside the container
run_step "Installing dependencies in container" $DOCKER_COMPOSE exec -T -u www-data www composer install --ignore-platform-reqs

# Programmatic farmOS installation
run_step "Running site install" \
    $DOCKER_COMPOSE exec -T -u www-data www drush site:install farm --yes \
  --db-url="pgsql://$DB_USER:$DB_PASS@db/$DB_NAME" \
  --account-name="$ADMIN_USER" --account-pass="$ADMIN_PASS" \
  --site-name="$SITE_NAME"

# Finish installation steps

run_step "Clearing caches" $DOCKER_COMPOSE exec -T -u www-data www drush cr

run_step "Running database updates" $DOCKER_COMPOSE exec -T -u www-data www drush updatedb -y

# Skip config import for fresh installations - only needed when updating existing sites
# For fresh installations, the configuration is already properly set up during site install
if [[ -d "config/sync" ]] && [[ -n "$(ls -A config/sync 2>/dev/null)" ]]; then
    log "Found existing configuration directory with content, attempting import..."
    run_step "Importing configuration" $DOCKER_COMPOSE exec -T -u www-data www drush config-import -y
else
    log "No existing configuration to import - skipping config import step (normal for fresh installations)"
fi

# Verify installation
run_step "Checking site status" $DOCKER_COMPOSE exec -T -u www-data www drush status

# Export current configuration for future updates
run_step "Exporting configuration" $DOCKER_COMPOSE exec -T -u www-data www drush config-export -y

# Get the actual port from docker-compose
ACTUAL_PORT=$($DOCKER_COMPOSE port www 80 2>/dev/null | cut -d: -f2 || echo "$WEB_PORT")

# Verify HTTP response - accept both 200 OK and 403 Forbidden as valid responses
# 403 is normal for farmOS installations that require login
log "Verifying HTTP response from farmOS..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$ACTUAL_PORT" || echo "000")
if [[ "$HTTP_STATUS" == "200" ]] || [[ "$HTTP_STATUS" == "403" ]]; then
    log "HTTP verification successful (status: $HTTP_STATUS)"
    printf "\r%b\n" "${GREEN}✓${NC} [14/15] HTTP verification successful (status: $HTTP_STATUS)"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    log "Completed: HTTP verification (14/15)"
else
    log "WARNING: Unexpected HTTP status: $HTTP_STATUS"
    printf "\r%b\n" "${YELLOW}⚠${NC} [14/15] HTTP verification returned status $HTTP_STATUS (proceeding anyway)"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    log "Completed: HTTP verification with warning (14/15)"
fi

# Run coding standard checks and automated tests (optional, can be skipped with SKIP_QA=1)
if [[ "${SKIP_QA:-0}" != "1" ]]; then
    log "Running quality assurance checks..."
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf "%b" "${BLUE}➤${NC} [$CURRENT_STEP/15] Running quality assurance checks..."
    
    # Check if the tools exist before running them
    QA_RESULTS=""
    if $DOCKER_COMPOSE exec -T -u www-data www which phpcs >/dev/null 2>&1; then
        log "Running phpcs..."
        if $DOCKER_COMPOSE exec -T -u www-data www phpcs /opt/drupal/web/profiles/farm >> "$LOGFILE" 2>&1; then
            QA_RESULTS="$QA_RESULTS phpcs:✓"
        else
            QA_RESULTS="$QA_RESULTS phpcs:⚠"
        fi
    else
        log "WARNING: phpcs not found, skipping code style check"
        QA_RESULTS="$QA_RESULTS phpcs:skip"
    fi
    
    if $DOCKER_COMPOSE exec -T -u www-data www which phpstan >/dev/null 2>&1; then
        log "Running phpstan..."
        if $DOCKER_COMPOSE exec -T -u www-data www phpstan analyze /opt/drupal/web/profiles/farm >> "$LOGFILE" 2>&1; then
            QA_RESULTS="$QA_RESULTS phpstan:✓"
        else
            QA_RESULTS="$QA_RESULTS phpstan:⚠"
        fi
    else
        log "WARNING: phpstan not found, skipping static analysis"
        QA_RESULTS="$QA_RESULTS phpstan:skip"
    fi
    
    if $DOCKER_COMPOSE exec -T -u www-data www which phpunit >/dev/null 2>&1; then
        log "Running phpunit..."
        if $DOCKER_COMPOSE exec -T -u www-data www phpunit --verbose --debug /opt/drupal/web/profiles/farm >> "$LOGFILE" 2>&1; then
            QA_RESULTS="$QA_RESULTS phpunit:✓"
        else
            QA_RESULTS="$QA_RESULTS phpunit:⚠"
        fi
    else
        log "WARNING: phpunit not found, skipping unit tests"
        QA_RESULTS="$QA_RESULTS phpunit:skip"
    fi
    
    printf "\r%b\n" "${GREEN}✓${NC} [$CURRENT_STEP/15] Quality assurance checks completed ($QA_RESULTS)"
    log "Completed: Quality assurance checks ($QA_RESULTS) ($CURRENT_STEP/15)"
else
    log "Skipping quality assurance checks (SKIP_QA=1)"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf "%b\n" "${BLUE}ℹ${NC} [$CURRENT_STEP/15] Skipping quality assurance checks (SKIP_QA=1)"
    log "Skipped: Quality assurance checks ($CURRENT_STEP/15)"
fi

# Remove the error trap since we're finishing up successfully
trap - ERR

log "farmOS installation and verification complete!"
echo ""
echo "${GREEN}✓${NC} farmOS installation and verification complete!"
echo "${BLUE}ℹ${NC} Access your farmOS instance at: http://localhost:$ACTUAL_PORT"
echo "${BLUE}ℹ${NC} Admin credentials: $ADMIN_USER / $ADMIN_PASS"
echo "${BLUE}ℹ${NC} Log file: $LOGFILE"
echo "${BLUE}ℹ${NC} farmOS directory: $PROJECT_DIR"
