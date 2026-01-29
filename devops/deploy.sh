#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Usage function
usage() {
    local exit_code=${1:-1}
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --env <staging|prod>       Environment to deploy to (required)"
    echo "  -c, --color <blue|green>       Color to deploy to (prod only, auto-detected if not specified)"
    echo "  -r, --rollback                 Rollback to the other color (prod only)"
    echo "  -s, --status                   Show current deployment status"
    echo "  -h, --help                     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --env staging               Deploy to staging"
    echo "  $0 --env prod                  Deploy to production (auto-detects inactive color)"
    echo "  $0 --env prod --color green    Deploy to production green"
    echo "  $0 --env prod --rollback       Rollback production to previous color"
    echo "  $0 --env prod --status         Show current production status"
    exit $exit_code
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
ENV=""
COLOR=""
ROLLBACK=false
SHOW_STATUS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env)
            ENV="$2"
            shift 2
            ;;
        -c|--color)
            COLOR="$2"
            shift 2
            ;;
        -r|--rollback)
            ROLLBACK=true
            shift
            ;;
        -s|--status)
            SHOW_STATUS=true
            shift
            ;;
        -h|--help)
            usage 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate environment
if [ -z "$ENV" ]; then
    log_error "Environment is required"
    usage
fi

if [ "$ENV" != "staging" ] && [ "$ENV" != "prod" ]; then
    log_error "Environment must be 'staging' or 'prod'"
    usage
fi

# Set environment-specific variables
ENV_DIR="$SCRIPT_DIR/$ENV"
COMPOSE_FILE="$ENV_DIR/docker-compose.yaml"

if [ ! -f "$COMPOSE_FILE" ]; then
    log_error "Docker compose file not found: $COMPOSE_FILE"
    exit 1
fi

# Get current active version for production
get_active_version() {
    if [ "$ENV" = "prod" ]; then
        # Check if there's a .active file
        if [ -f "$ENV_DIR/.active" ]; then
            cat "$ENV_DIR/.active"
        else
            # Default to blue if not set
            echo "blue"
        fi
    fi
}

# Get inactive version (the opposite of active)
get_inactive_version() {
    local active=$(get_active_version)
    if [ "$active" = "blue" ]; then
        echo "green"
    else
        echo "blue"
    fi
}

# Update UI environment file
update_ui_env() {
    local env_type="$1"
    local color="$2"
    local ui_env_file="$PROJECT_ROOT/ui/.env"

    log_info "Updating UI environment configuration..."

    if [ "$env_type" = "staging" ]; then
        cat > "$ui_env_file" <<EOF
VITE_SERVER_ADDRESS=http://backend:5000
EOF
        log_info "UI configured for staging (backend:5000)"
    elif [ "$env_type" = "prod" ]; then
        if [ -z "$color" ]; then
            log_error "Color must be specified for production deployment"
            exit 1
        fi
        cat > "$ui_env_file" <<EOF
VITE_SERVER_ADDRESS=http://backend-${color}:5000
EOF
        log_info "UI configured for production ${color} (backend-${color}:5000)"
    else
        log_error "Invalid environment type: $env_type"
        exit 1
    fi
}

# Show deployment status
show_status() {
    log_info "Deployment Status for $ENV"
    echo "================================"

    if [ "$ENV" = "prod" ]; then
        local active=$(get_active_version)
        local inactive=$(get_inactive_version)

        echo -e "${GREEN}Active Version:${NC} $active"
        echo -e "${YELLOW}Inactive Version:${NC} $inactive"
        echo ""
        echo "Running Containers:"
        cd "$ENV_DIR"
        docker compose ps
    else
        echo "Environment: staging (single deployment)"
        echo ""
        echo "Running Containers:"
        cd "$ENV_DIR"
        docker compose ps
    fi
}

# Deploy to staging
deploy_staging() {
    log_info "Deploying to staging environment..."

    # Update UI environment configuration
    update_ui_env "staging"

    cd "$ENV_DIR"

    log_info "Building images..."
    docker compose build --no-cache

    log_info "Stopping existing containers..."
    docker compose down

    log_info "Starting new containers..."
    docker compose up -d

    log_success "Staging deployment completed successfully!"
    log_info "Waiting 5 seconds for containers to stabilize..."
    sleep 5

    log_info "Container status:"
    docker compose ps
}

# Deploy to production with blue-green
deploy_production() {
    local deploy_color="$1"

    if [ -z "$deploy_color" ]; then
        deploy_color=$(get_inactive_version)
        log_info "Auto-detected inactive version: $deploy_color"
    fi

    if [ "$deploy_color" != "blue" ] && [ "$deploy_color" != "green" ]; then
        log_error "Color must be 'blue' or 'green'"
        exit 1
    fi

    local active=$(get_active_version)

    if [ "$deploy_color" = "$active" ]; then
        log_warning "Deploying to currently active version: $deploy_color"
        read -p "This will cause downtime. Continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi

    log_info "Deploying to production $deploy_color environment..."
    log_info "Current active version: $active"

    # Update UI environment configuration
    update_ui_env "prod" "$deploy_color"

    cd "$ENV_DIR"

    # Build the new version
    log_info "Building $deploy_color images..."
    docker compose build --no-cache backend-${deploy_color} webui-${deploy_color}

    # Stop and start the target color containers
    log_info "Stopping $deploy_color containers..."
    docker compose stop backend-${deploy_color} webui-${deploy_color}
    docker compose rm -f backend-${deploy_color} webui-${deploy_color}

    log_info "Starting $deploy_color containers..."
    docker compose up -d backend-${deploy_color} webui-${deploy_color}

    log_info "Waiting for $deploy_color containers to be healthy (10 seconds)..."
    sleep 10

    # Check if containers are running
    if ! docker compose ps | grep -q "backend-${deploy_color}.*Up"; then
        log_error "Backend $deploy_color container is not running!"
        exit 1
    fi

    if ! docker compose ps | grep -q "webui-${deploy_color}.*Up"; then
        log_error "WebUI $deploy_color container is not running!"
        exit 1
    fi

    log_success "$deploy_color containers are running"

    # Prompt to switch traffic
    echo ""
    log_warning "Ready to switch traffic from $active to $deploy_color"
    read -p "Proceed with traffic switch? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Traffic switch cancelled. $deploy_color is running but not active."
        log_info "To manually switch, run: $0 --env prod --color $deploy_color"
        exit 0
    fi

    # Switch traffic
    switch_traffic "$deploy_color"
}

# Switch traffic to specified color
switch_traffic() {
    local new_active="$1"
    local old_active=$(get_active_version)

    log_info "Switching traffic from $old_active to $new_active..."

    cd "$ENV_DIR"

    # Update the active version file
    echo "$new_active" > "$ENV_DIR/.active"

    # Reload Caddy with new environment variable
    log_info "Reloading Caddy with ACTIVE_VERSION=$new_active..."
    docker compose stop caddy
    ACTIVE_VERSION="$new_active" docker compose up -d caddy

    sleep 3

    if docker compose ps | grep -q "caddy.*Up"; then
        log_success "Traffic switched to $new_active successfully!"
        log_info "Old version ($old_active) is still running for quick rollback if needed"
    else
        log_error "Failed to reload Caddy!"
        exit 1
    fi
}

# Rollback to previous version
rollback_production() {
    if [ "$ENV" != "prod" ]; then
        log_error "Rollback is only available for production"
        exit 1
    fi

    local current=$(get_active_version)
    local previous=$(get_inactive_version)

    log_warning "Rolling back from $current to $previous..."

    # Check if previous version containers are running
    cd "$ENV_DIR"
    if ! docker compose ps | grep -q "backend-${previous}.*Up"; then
        log_error "Previous version ($previous) backend is not running!"
        log_info "Starting $previous containers first..."
        docker compose up -d backend-${previous} webui-${previous}
        sleep 10
    fi

    switch_traffic "$previous"

    log_success "Rollback completed successfully!"
}

# Main execution
main() {
    log_info "Invoice Service Deployment Script"
    log_info "Environment: $ENV"
    echo ""

    if [ "$SHOW_STATUS" = true ]; then
        show_status
        exit 0
    fi

    if [ "$ROLLBACK" = true ]; then
        rollback_production
        exit 0
    fi

    if [ "$ENV" = "staging" ]; then
        deploy_staging
    else
        deploy_production "$COLOR"
    fi

    echo ""
    log_success "Deployment completed!"
    echo ""
    show_status
}

# Run main
main
