# GitHub Actions CI/CD Pipeline

This repository uses GitHub Actions for automated testing, building, and deploying Docker images.

## Workflow Overview

### On Pull Requests
When you create a PR targeting `main`:
1. ✅ **Lint** - Runs RuboCop to check code style
2. ✅ **Test** - Runs RSpec test suite with PostgreSQL
3. ✅ **Build** - Builds Docker image to verify it works
4. ✅ **Security** - Checks dependencies with bundler-audit and brakeman
5. ❌ **Does NOT push** image to registry

### On Push to Main
When code is merged to `main`:
1. ✅ **Lint** - Runs RuboCop
2. ✅ **Test** - Runs RSpec test suite
3. ✅ **Security** - Checks dependencies
4. ❌ **Does NOT build or push** Docker images

### On Version Tags
When you push a version tag (e.g., `v1.0.0`):
1. ✅ **Lint** - Runs RuboCop
2. ✅ **Test** - Runs RSpec test suite
3. ✅ **Build** - Builds Docker image
4. ✅ **Push** - Pushes to GitHub Container Registry with multiple tags:
   - `v1.0.0` (exact version)
   - `v1.0` (minor version)
   - `v1` (major version)
   - `latest` (latest release)
   - `main-abc1234` (branch + commit SHA for rollback)
5. ✅ **Security Scan** - Scans image with Trivy for vulnerabilities

## Creating a Release

### 1. Prepare the Release
```bash
# Make sure you're on main and up to date
git checkout main
git pull origin main

# Create and push a version tag
git tag v1.0.0
git push origin v1.0.0
```

### 2. Monitor the Build
- Go to the **Actions** tab in GitHub
- Watch the workflow run
- All jobs must pass (lint → test → build → security)

### 3. Use the Image
Once the workflow completes, the image will be available at:
```
ghcr.io/romkey/pdxhackerspace-eventmanager:v1.0.0
ghcr.io/romkey/pdxhackerspace-eventmanager:latest
```

## Using Pre-built Images in Production

### Update docker-compose.yml

The production `docker-compose.yml` file should use pre-built images:

```yaml
web:
  image: ghcr.io/romkey/pdxhackerspace-eventmanager:latest
  # Or pin to specific version:
  # image: ghcr.io/romkey/pdxhackerspace-eventmanager:v1.0.0
```

### Deploy Updates

```bash
# Pull the latest image
docker compose pull

# Restart with new image
docker compose up -d

# View logs
docker compose logs -f web
```

## Rollback to Previous Version

If something goes wrong:
```bash
# Update docker-compose.yml to previous version
# image: ghcr.io/romkey/pdxhackerspace-eventmanager:v1.0.0

# Pull and restart
docker compose pull
docker compose up -d
```

## Making Images Public

By default, GitHub Container Registry images are private. To make them public:

1. Go to your GitHub profile
2. Click **Packages**
3. Click on your **eventmanager** package
4. Go to **Package settings**
5. Scroll to **Danger Zone**
6. Click **Change visibility** → **Public**

## Required GitHub Secrets

The workflow uses the built-in `GITHUB_TOKEN` which is automatically provided.

No additional secrets are required unless you want to:
- Push to Docker Hub (add `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`)
- Send notifications (add Slack webhook, Discord webhook, etc.)

## Testing the Workflow Locally

### Run Tests Locally
```bash
# Run linter
docker compose exec web bundle exec rubocop

# Run tests
docker compose exec web bundle exec rspec
```

### Build Docker Image Locally
```bash
docker build -t eventmanager:test .
```

## Workflow Files

- `.github/workflows/ci-cd.yml` - Main CI/CD pipeline

## Troubleshooting

### "Package does not exist" Error
If you get authentication errors when pulling:
```bash
# Log in to GitHub Container Registry
echo $GITHUB_TOKEN | docker login ghcr.io -u romkey --password-stdin

# Or create a Personal Access Token with read:packages scope
```

### Tests Failing in CI but Pass Locally
- Check Ruby version matches (3.2.2)
- Check PostgreSQL version (15)
- Ensure all environment variables are set
- Check that test database setup is correct

### Build is Slow
The workflow uses build caching. First build will be slow, subsequent builds are faster.

## Version Numbering

We follow [Semantic Versioning](https://semver.org/):

- `v1.0.0` - Major.Minor.Patch
- **Major** - Breaking changes
- **Minor** - New features (backward compatible)
- **Patch** - Bug fixes (backward compatible)

Examples:
- `v1.0.0` → `v1.0.1` - Bug fix
- `v1.0.1` → `v1.1.0` - New feature
- `v1.1.0` → `v2.0.0` - Breaking change

