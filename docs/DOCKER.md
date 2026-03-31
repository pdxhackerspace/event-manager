# Docker Setup Guide

This guide will help you run EventManager using Docker and Docker Compose.

## Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+

## Compose Files

- **docker-compose.dev.yml** - Development environment (local builds, volume mounts)
- **docker-compose.yml** - Production environment (pre-built images from registry, default file)

## Quick Start - Development

### 1. Build and Start Services

```bash
docker compose -f docker-compose.dev.yml up -d
```

This will:
- Build the Rails application container
- Start PostgreSQL database
- Run database migrations
- Seed the database with sample data
- Start the Rails server

### 2. Access the Application

Open your browser to: **http://localhost:3000**

Default credentials:
- **Admin**: admin@example.com / password123
- **User**: user1@example.com / password123

### 3. View Logs

```bash
# All services
docker-compose logs -f

# Just the web app
docker-compose logs -f web

# Just the database
docker-compose logs -f db
```

## Common Commands

**Note:** Use `-f docker-compose.dev.yml` for development. Production uses `docker-compose.yml` (the default file).

### Start Services

```bash
docker compose -f docker-compose.dev.yml up -d
```

### Stop Services

```bash
docker compose -f docker-compose.dev.yml down
```

### Stop Services and Remove Volumes (Complete Reset)

```bash
docker compose -f docker-compose.dev.yml down -v
```

### Rebuild After Code Changes

```bash
docker compose -f docker-compose.dev.yml build
docker compose -f docker-compose.dev.yml up -d
```

### Run Rails Console

```bash
docker compose -f docker-compose.dev.yml exec web rails console
```

### Run Database Migrations

```bash
docker compose -f docker-compose.dev.yml exec web rails db:migrate
```

### Reset Database

```bash
docker compose -f docker-compose.dev.yml exec web rails db:reset
docker compose -f docker-compose.dev.yml exec web rails db:seed
```

### Run Tests

```bash
docker compose -f docker-compose.dev.yml exec web bundle exec rspec
```

### Access Rails Shell

```bash
docker compose -f docker-compose.dev.yml exec web bash
```

### View Running Containers

```bash
docker compose -f docker-compose.dev.yml ps
```

## Configuration

### Environment Variables

Copy the environment template and edit:

```bash
cp .env.development.example .env
```

See also `.env.test.example`, `.env.staging.example`, and `.env.production.example` for other targets. Docker Compose reads `.env` in the project root for variable substitution.

### Port Conflicts

If port 3000 is already in use, edit `docker-compose.dev.yml`:

```yaml
services:
  web:
    ports:
      - "3001:3000"  # Change 3001 to any available port
```

Then access the app at http://localhost:3001

### Database Port

If you need to access PostgreSQL from outside Docker:

```yaml
services:
  db:
    ports:
      - "5433:5432"  # Change 5433 to avoid conflicts
```

## Docker Compose Services

### Web Service (`web`)

- **Image**: Built from Dockerfile
- **Ports**: 3000
- **Volumes**: 
  - Application code (for live reloading)
  - Gem cache
  - Node modules
- **Depends on**: PostgreSQL database

### Database Service (`db`)

- **Image**: postgres:14-alpine
- **Ports**: 5432
- **Volumes**: Persistent PostgreSQL data
- **Healthcheck**: Ensures database is ready before starting web service

## Volumes

Docker Compose creates three volumes:

1. **postgres_data**: Stores PostgreSQL data (persists between restarts)
2. **bundle_cache**: Caches Ruby gems (faster rebuilds)
3. **node_modules**: Caches Node modules (faster rebuilds)

To view volumes:
```bash
docker volume ls | grep eventmanager
```

To remove all volumes (CAUTION: Deletes all data):
```bash
docker-compose down -v
```

## Troubleshooting

### "Port already in use" Error

Another service is using port 3000:
```bash
# Find what's using the port
lsof -ti:3000
# Kill it or change the port in docker-compose.yml
```

### Database Connection Errors

Make sure the database container is healthy:
```bash
docker-compose ps
# db should show "healthy" status

# Check database logs
docker-compose logs db
```

Restart services:
```bash
docker compose -f docker-compose.dev.yml down
docker compose -f docker-compose.dev.yml up -d
```

### "Bundle install" Errors

Rebuild the container:
```bash
docker compose -f docker-compose.dev.yml down
docker compose -f docker-compose.dev.yml build --no-cache
docker compose -f docker-compose.dev.yml up -d
```

### Asset Compilation Errors

Rebuild with fresh assets:
```bash
docker compose -f docker-compose.dev.yml exec web yarn build
docker compose -f docker-compose.dev.yml exec web yarn build:css
docker compose -f docker-compose.dev.yml restart web
```

### Container Won't Start

Check logs:
```bash
docker compose -f docker-compose.dev.yml logs web
```

Remove and recreate:
```bash
docker compose -f docker-compose.dev.yml down
docker compose -f docker-compose.dev.yml up -d
```

### Database Not Seeding

Manually seed:
```bash
docker compose -f docker-compose.dev.yml exec web rails db:seed
```

### File Permission Issues (Linux)

If you encounter permission errors on Linux:
```bash
# Fix ownership
sudo chown -R $USER:$USER .

# Or run with your user ID
docker compose -f docker-compose.dev.yml run --user $(id -u):$(id -g) web bash
```

## Development Workflow

### Making Code Changes

Code changes are automatically reflected due to volume mounting. Just refresh your browser.

### Adding Gems

1. Add gem to `Gemfile`
2. Rebuild container:
   ```bash
   docker compose -f docker-compose.dev.yml build web
   docker compose -f docker-compose.dev.yml up -d
   ```

### Running Migrations

After creating a migration:
```bash
docker compose -f docker-compose.dev.yml exec web rails db:migrate
```

### Installing Node Packages

```bash
docker compose -f docker-compose.dev.yml exec web yarn add <package-name>
```

## Production Deployment

Use the default compose file which pulls pre-built images from GitHub Container Registry:

```bash
# Pull latest image
docker compose pull

# Start services
docker compose up -d

# View logs
docker compose logs -f web
```

Production considerations:

1. **Pre-built images** - Images are built by GitHub Actions and pushed to registry
2. **Environment variables** - Set production secrets in `.env` file
3. **External database** - Consider managed PostgreSQL for production
4. **Container orchestration** - Kubernetes, Docker Swarm, or managed services
5. **Secrets management** - Use Docker secrets or external vaults
6. **Health checks and monitoring** - Already configured in docker-compose.yml
7. **Reverse proxy** - nginx or Traefik for SSL termination
8. **SSL certificates** - Let's Encrypt with automatic renewal

See **GITHUB_ACTIONS.md** for details on automated image builds and deployments.

## Useful Resources

- [Docker Documentation](https://docs.docker.com/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Rails Docker Guide](https://guides.rubyonrails.org/docker.html)
- [PostgreSQL Docker Image](https://hub.docker.com/_/postgres)

## Clean Up

### Remove Everything (Containers, Networks, Volumes)

```bash
docker compose -f docker-compose.dev.yml down -v
docker volume prune
docker image prune
```

### Remove Just EventManager Containers

```bash
docker compose -f docker-compose.dev.yml down
docker rmi eventmanager-web
```

## Support

For issues related to Docker setup, check the logs first:
```bash
docker compose -f docker-compose.dev.yml logs -f
```

For application issues, see the main [README.md](../README.md).

