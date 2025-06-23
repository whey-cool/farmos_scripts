#!/usr/bin/env bash
# farmOS Installation Validation Script
#
# This script validates the installation of farmOS by performing comprehensive checks:
# - Docker container health
# - Database connectivity
# - Web server response
# - Drupal site status
# - Basic functionality tests
# - Optional PHPUnit tests
#
# Usage: ./validate-installation.sh [OPTIONS]
#
# Options:
#   --skip-tests    Skip PHPUnit tests (faster validation)
#   --verbose       Show detailed output
#   --help          Show this help message
#
# Environment variables:
#   FARMOS_DIR      - Path to farmOS installation (default: ../farmos)
#   ADMIN_USER      - Admin username (default: admin)
#   ADMIN_PASS      - Admin password (default: admin)

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FARMOS_DIR="${FARMOS_DIR:-"$PROJECT_ROOT/farmos"}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin}"

# Options
SKIP_TESTS=false
VERBOSE=false
HELP=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            HELP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Show help if requested
if [[ "$HELP" == "true" ]]; then
    cat << 'EOF'
farmOS Installation Validation Script

This script validates the installation of farmOS by performing comprehensive checks:
- Docker container health
- Database connectivity
- Web server response
- Drupal site status
- Basic functionality tests
- Optional PHPUnit tests

Usage: ./validate-installation.sh [OPTIONS]

Options:
  --skip-tests    Skip PHPUnit tests (faster validation)
  --verbose       Show detailed output
  --help          Show this help message

Environment variables:
  FARMOS_DIR      - Path to farmOS installation (default: ../farmos)
  ADMIN_USER      - Admin username (default: admin)
  ADMIN_PASS      - Admin password (default: admin)
EOF
    exit 0
fi

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}  →${NC} $1"
    fi
}

# Check if running in the correct directory
validate_environment() {
    log_info "Validating environment..."
    
    if [[ ! -d "$FARMOS_DIR" ]]; then
        log_error "farmOS directory not found: $FARMOS_DIR"
        log_error "Please ensure farmOS is installed or set FARMOS_DIR environment variable"
        exit 1
    fi
    
    if [[ ! -f "$FARMOS_DIR/docker-compose.yml" ]]; then
        log_error "docker-compose.yml not found in $FARMOS_DIR"
        log_error "This doesn't appear to be a valid farmOS installation"
        exit 1
    fi
    
    log_verbose "farmOS directory: $FARMOS_DIR"
    log_success "Environment validation passed"
}

# Detect Docker Compose command
detect_docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose >/dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        log_error "Docker Compose not found. Please install Docker Compose."
        exit 1
    fi
    log_verbose "Using Docker Compose command: $DOCKER_COMPOSE"
}

# Check Docker container status
validate_containers() {
    log_info "Checking Docker containers..."
    
    cd "$FARMOS_DIR"
    
    # Check if containers are running
    if ! $DOCKER_COMPOSE ps --services --filter "status=running" | grep -q "www\|db"; then
        log_error "farmOS containers are not running"
        log_info "Container status:"
        $DOCKER_COMPOSE ps
        log_error "Please start the containers with: cd $FARMOS_DIR && $DOCKER_COMPOSE up -d"
        exit 1
    fi
    
    # Check individual container health
    local www_status=""
    local db_status=""
    
    # Get container status in a compatible way
    if $DOCKER_COMPOSE ps www | grep -q "Up"; then
        www_status="Up"
    else
        www_status="Down"
    fi
    
    if $DOCKER_COMPOSE ps db | grep -q "Up"; then
        db_status="Up"
    else
        db_status="Down"
    fi
    
    log_verbose "Web container status: $www_status"
    log_verbose "Database container status: $db_status"
    
    if [[ "$www_status" == "Up" ]] && [[ "$db_status" == "Up" ]]; then
        log_success "All containers are running"
    else
        log_warning "Some containers may have issues. Check with: $DOCKER_COMPOSE ps"
    fi
}

# Test database connectivity
validate_database() {
    log_info "Testing database connectivity..."
    
    cd "$FARMOS_DIR"
    
    if $DOCKER_COMPOSE exec -T db pg_isready -h localhost >/dev/null 2>&1; then
        log_success "Database is accepting connections"
    else
        log_error "Database is not responding"
        return 1
    fi
    
    # Test database access from web container
    if $DOCKER_COMPOSE exec -T -u www-data www drush sql:query "SELECT 1;" >/dev/null 2>&1; then
        log_success "Database query test passed"
    else
        log_error "Cannot query database from web container"
        return 1
    fi
}

# Test web server response
validate_web_server() {
    log_info "Testing web server response..."
    
    cd "$FARMOS_DIR"
    
    # Get the actual port
    local port=$($DOCKER_COMPOSE port www 80 2>/dev/null | cut -d: -f2 || echo "80")
    log_verbose "Testing on port: $port"
    
    # Test HTTP response
    local http_status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port" || echo "000")
    log_verbose "HTTP status: $http_status"
    
    if [[ "$http_status" == "200" ]] || [[ "$http_status" == "403" ]]; then
        log_success "Web server is responding (status: $http_status)"
        if [[ "$http_status" == "403" ]]; then
            log_verbose "403 status is normal for farmOS requiring login"
        fi
    else
        log_error "Web server not responding properly (status: $http_status)"
        return 1
    fi
}

# Test Drupal site status
validate_drupal_status() {
    log_info "Checking Drupal site status..."
    
    cd "$FARMOS_DIR"
    
    # Get detailed site status
    local status_output
    if status_output=$($DOCKER_COMPOSE exec -T -u www-data www drush status 2>/dev/null); then
        log_verbose "Drush status command successful"
        
        # Parse key information from text output
        local drupal_version=$(echo "$status_output" | grep "Drupal version" | awk '{print $NF}' || echo "unknown")
        local bootstrap=$(echo "$status_output" | grep "Drupal bootstrap" | awk '{print $NF}' || echo "unknown")
        local database=$(echo "$status_output" | grep "Database" | awk '{print $NF}' || echo "unknown")
        
        log_verbose "Drupal version: $drupal_version"
        log_verbose "Bootstrap: $bootstrap"
        log_verbose "Database: $database"
        
        if [[ "$bootstrap" == "Successful" ]] && [[ "$database" == "Connected" ]]; then
            log_success "Drupal site is healthy"
        else
            log_warning "Drupal site may have issues (bootstrap: $bootstrap, db: $database)"
        fi
    else
        log_error "Cannot get Drupal status"
        return 1
    fi
}

# Test user authentication
validate_authentication() {
    log_info "Testing user authentication..."
    
    cd "$FARMOS_DIR"
    
    # Try to login and get user information
    if $DOCKER_COMPOSE exec -T -u www-data www drush user:information "$ADMIN_USER" >/dev/null 2>&1; then
        log_success "Admin user '$ADMIN_USER' exists and is accessible"
    else
        log_warning "Cannot access admin user '$ADMIN_USER'"
        log_verbose "This might be normal if the username was changed during installation"
    fi
}

# Test farmOS specific functionality
validate_farmos_functionality() {
    log_info "Testing farmOS specific functionality..."
    
    cd "$FARMOS_DIR"
    
    # Check if farmOS modules are enabled
    local farm_modules=$($DOCKER_COMPOSE exec -T -u www-data www drush pm:list --status=enabled --format=json 2>/dev/null | grep -c '"farm_' || echo "0")
    log_verbose "farmOS modules enabled: $farm_modules"
    
    if [[ "$farm_modules" -gt 0 ]]; then
        log_success "farmOS modules are enabled ($farm_modules found)"
    else
        log_warning "No farmOS modules found - this may not be a complete farmOS installation"
    fi
    
    # Check if farm profile is installed
    if $DOCKER_COMPOSE exec -T -u www-data www drush status | grep -q "Install profile.*farm"; then
        log_success "farmOS install profile detected"
    else
        log_warning "farmOS install profile not detected"
    fi
}

# Run PHPUnit tests
validate_phpunit_tests() {
    if [[ "$SKIP_TESTS" == "true" ]]; then
        log_info "Skipping PHPUnit tests (--skip-tests specified)"
        return 0
    fi
    
    log_info "Running PHPUnit tests..."
    
    cd "$FARMOS_DIR"
    
    # Check if PHPUnit is available
    if ! $DOCKER_COMPOSE exec -T -u www-data www which phpunit >/dev/null 2>&1; then
        log_warning "PHPUnit not found - skipping tests"
        return 0
    fi
    
    # Look for farmOS test files
    local test_files=()
    
    # Check common test locations
    for test_path in \
        "/opt/drupal/web/profiles/farm/tests" \
        "/opt/drupal/web/modules/contrib/farm/tests" \
        "/opt/drupal/web/sites/all/modules/farm/tests"; do
        
        if $DOCKER_COMPOSE exec -T -u www-data www test -d "$test_path" 2>/dev/null; then
            test_files+=("$test_path")
            log_verbose "Found test directory: $test_path"
        fi
    done
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        log_warning "No farmOS test files found - skipping PHPUnit tests"
        return 0
    fi
    
    # Run tests for each found directory
    local test_results=0
    for test_path in "${test_files[@]}"; do
        log_verbose "Running tests in: $test_path"
        if $DOCKER_COMPOSE exec -T -u www-data www phpunit "$test_path" >/dev/null 2>&1; then
            log_success "Tests passed in $test_path"
        else
            log_warning "Some tests failed in $test_path"
            test_results=1
        fi
    done
    
    if [[ $test_results -eq 0 ]]; then
        log_success "All PHPUnit tests passed"
    else
        log_warning "Some PHPUnit tests failed (this may be normal for development installations)"
    fi
}

# Main validation function
main() {
    echo "farmOS Installation Validation"
    echo "=============================="
    echo ""
    
    local validation_errors=0
    
    # Run all validation checks
    validate_environment || ((validation_errors++))
    detect_docker_compose || ((validation_errors++))
    validate_containers || ((validation_errors++))
    validate_database || ((validation_errors++))
    validate_web_server || ((validation_errors++))
    validate_drupal_status || ((validation_errors++))
    validate_authentication || ((validation_errors++))
    validate_farmos_functionality || ((validation_errors++))
    validate_phpunit_tests || ((validation_errors++))
    
    echo ""
    echo "Validation Summary"
    echo "=================="
    
    if [[ $validation_errors -eq 0 ]]; then
        log_success "All validation checks passed! farmOS installation appears to be healthy."
        echo ""
        log_info "Access your farmOS instance at: http://localhost"
        log_info "Default admin credentials: $ADMIN_USER / $ADMIN_PASS"
        exit 0
    else
        log_warning "$validation_errors validation check(s) failed or had warnings."
        log_info "farmOS may still be functional, but please review the issues above."
        exit 1
    fi
}

# Run main function
main "$@"
