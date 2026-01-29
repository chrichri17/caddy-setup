# Invoice Service Deployment Guide

This directory contains deployment configurations and scripts for the Invoice Service application with blue-green deployment support for production.

## Architecture Overview

### Staging Environment
- **Single deployment**: Simple docker-compose setup with one instance of each service
- **Services**: `backend`, `webui`, `caddy`
- **Domain**: `staging.invoices.gogofuels.com` and `staging.api.gogofuels.com`

### Production Environment
- **Blue-Green deployment**: Zero-downtime deployments with two parallel environments
- **Services**: `backend-blue`, `backend-green`, `webui-blue`, `webui-green`, `caddy`
- **Domain**: `invoices.gogofuels.com` and `api.gogofuels.com`
- **Traffic routing**: Caddy uses `ACTIVE_VERSION` environment variable to route to active color

## Directory Structure

```
devops/
├── deploy.sh              # Main deployment script
├── README.md             # This file
├── staging/
│   ├── docker-compose.yaml
│   └── Caddyfile
└── prod/
    ├── docker-compose.yaml
    ├── Caddyfile
    └── .active           # Tracks currently active version (blue/green)
```

## Prerequisites

- Docker and Docker Compose installed
- Access to the server/deployment environment
- Proper DNS configuration for domains

## Deployment Script Usage

### Basic Commands

```bash
# Deploy to staging
./devops/deploy.sh --env staging

# Deploy to production (auto-detects inactive color)
./devops/deploy.sh --env prod

# Deploy to specific production color
./devops/deploy.sh --env prod --color green

# Check deployment status
./devops/deploy.sh --env prod --status

# Rollback production to previous version
./devops/deploy.sh --env prod --rollback

# Show help
./devops/deploy.sh --help
```

### Deployment Options

| Option | Description |
|--------|-------------|
| `-e, --env <staging\|prod>` | Environment to deploy to (required) |
| `-c, --color <blue\|green>` | Color to deploy to (prod only, auto-detected if not specified) |
| `-r, --rollback` | Rollback to the other color (prod only) |
| `-s, --status` | Show current deployment status |
| `-h, --help` | Show help message |

## How It Works

### Staging Deployment Flow

1. Updates `ui/.env` to point to `http://backend:5000`
2. Builds Docker images with `--no-cache`
3. Stops existing containers
4. Starts new containers
5. Shows container status

**Note**: Staging deployments cause brief downtime during container restart.

### Production Blue-Green Deployment Flow

1. **Preparation Phase**:
   - Detects currently active version (from `.active` file)
   - Determines inactive version to deploy to
   - Updates `ui/.env` to point to correct backend (e.g., `http://backend-green:5000`)

2. **Build Phase**:
   - Builds new Docker images for the target color
   - Only builds `backend-{color}` and `webui-{color}` services

3. **Deploy Phase**:
   - Stops and removes old containers of target color
   - Starts new containers of target color
   - Waits 10 seconds for health check
   - Verifies containers are running

4. **Traffic Switch Phase** (requires confirmation):
   - Updates `.active` file with new version
   - Reloads Caddy with `ACTIVE_VERSION` environment variable
   - Caddy routes traffic to new version
   - Old version remains running for quick rollback

### Rollback Process

Rollback is instant because both versions are running:

1. Reads current active version from `.active` file
2. Switches Caddy to point to the other version
3. Updates `.active` file
4. No rebuild required!

## Environment Configuration

### UI Environment File (`ui/.env`)

The deploy script automatically updates this file:

**Staging**:
```env
VITE_SERVER_ADDRESS=http://backend:5000
```

**Production** (example for green deployment):
```env
VITE_SERVER_ADDRESS=http://backend-green:5000
```

This allows the UI to connect to the correct backend service within the Docker network.

### Caddy Configuration

#### Staging Caddyfile
Routes traffic to single instances:
```
staging.invoices.gogofuels.com {
    @api path /api/*
    reverse_proxy @api backend:5000
    reverse_proxy webui:80
}
```

#### Production Caddyfile
Uses `ACTIVE_VERSION` variable for blue-green routing:
```
invoices.gogofuels.com {
    @api path /api/*
    reverse_proxy @api backend-{$ACTIVE_VERSION}:5000
    reverse_proxy webui-{$ACTIVE_VERSION}:80
}
```

The `{$ACTIVE_VERSION}` placeholder is replaced with either `blue` or `green`.

## Docker Compose Configuration

### Staging Setup

Simple single-instance setup:
```yaml
services:
  backend:
    build: ../../backend
    environment:
      - FLASK_ENV=staging

  webui:
    build: ../../ui
    environment:
      - VITE_ENV=staging

  caddy:
    image: caddy:2
    ports:
      - "8080:80"
      - "8443:443"
```

### Production Setup

Dual-instance blue-green setup:
```yaml
services:
  backend-blue:
    build: ../../backend
    environment:
      - FLASK_ENV=production

  backend-green:
    build: ../../backend
    environment:
      - FLASK_ENV=production

  webui-blue:
    build: ../../ui
    environment:
      - VITE_ENV=production

  webui-green:
    build: ../../ui
    environment:
      - VITE_ENV=production

  caddy:
    image: caddy:2
    environment:
      - ACTIVE_VERSION=${ACTIVE_VERSION:-blue}
    ports:
      - "80:80"
      - "443:443"
```

## Typical Workflow

### Initial Production Deployment

```bash
# First deployment (deploys to blue by default)
./devops/deploy.sh --env prod
```

This will:
1. Deploy to blue (inactive)
2. Ask for confirmation to switch traffic
3. Make blue active

### Subsequent Deployments

```bash
# Deploy new version (automatically uses inactive color)
./devops/deploy.sh --env prod
```

This will:
1. Detect current active version (e.g., blue)
2. Deploy to inactive version (green)
3. Ask for confirmation to switch traffic
4. Switch traffic to green
5. Blue remains running for rollback

### If Something Goes Wrong

```bash
# Instant rollback to previous version
./devops/deploy.sh --env prod --rollback
```

This switches traffic back to the previous version immediately (no rebuild needed).

## Benefits of Blue-Green Deployment

1. **Zero Downtime**: New version is fully started before traffic switch
2. **Instant Rollback**: Previous version is still running, just switch back
3. **Safe Testing**: Deploy to inactive color, verify it works, then switch traffic
4. **Gradual Rollout**: Can manually test inactive version before switching traffic

## Monitoring Deployments

```bash
# Check which version is active and container status
./devops/deploy.sh --env prod --status

# View logs for specific color
cd devops/prod
docker compose logs -f backend-blue
docker compose logs -f webui-green

# Check all running containers
docker compose ps
```

## Troubleshooting

### Container Won't Start

Check logs:
```bash
cd devops/prod
docker compose logs backend-blue
docker compose logs webui-green
```

### Traffic Not Switching

Verify Caddy configuration:
```bash
cd devops/prod
docker compose logs caddy
docker compose exec caddy caddy environ
```

### Rollback Not Working

Ensure both versions are running:
```bash
./devops/deploy.sh --env prod --status
```

If inactive version isn't running, the rollback script will start it automatically.

## Security Notes

- Ensure `.env` files are in `.gitignore`
- Never commit secrets or credentials
- Use proper file permissions on deployment scripts
- Consider using Docker secrets for sensitive data

## Future Enhancements

Potential improvements to consider:

- Health check endpoints before traffic switch
- Automated smoke tests on inactive version
- Integration with monitoring/alerting systems
- Database migration handling
- Backup automation before deployments
- Load testing on inactive version before switch
