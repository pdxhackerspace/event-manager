# Quick Setup Guide

## Option 1: Docker Setup (Easiest)

### Prerequisites
- [ ] Docker installed
- [ ] Docker Compose installed

### Quick Start

```bash
# Start everything
docker-compose up -d

# View logs
docker-compose logs -f

# Access application at http://localhost:3000
```

**Login:**
- Admin: admin@example.com / password123
- User: user1@example.com / password123

**Common Commands:**
```bash
# Stop services
docker-compose down

# Restart services
docker-compose restart

# Rails console
docker-compose exec web rails console

# View logs
docker-compose logs -f web
```

See [DOCKER.md](DOCKER.md) for detailed Docker documentation.

---

## Option 2: Native Setup

### Prerequisites Checklist

- [ ] Ruby 3.1.2 installed
- [ ] PostgreSQL installed and running
- [ ] Node.js and Yarn installed

## Setup Steps

### 1. Start PostgreSQL

Make sure PostgreSQL is running on your system:

```bash
# macOS with Homebrew
brew services start postgresql@14

# Linux
sudo systemctl start postgresql

# Or check if it's already running
psql --version
```

### 2. Install Dependencies

```bash
bundle install
yarn install
```

### 3. Setup Database

```bash
# Create databases
rails db:create

# Run migrations
rails db:migrate

# Load seed data (creates admin and test users)
rails db:seed
```

### 4. Start the Development Server

```bash
./bin/dev
```

Or if that doesn't work:

```bash
# Terminal 1
rails server

# Terminal 2  
yarn build:css
```

### 5. Visit the Application

Open your browser to: http://localhost:3000

### 6. Login

Use these test accounts:

- **Admin**: admin@example.com / password123
- **User**: user1@example.com / password123

## Next Steps

1. **Configure Authentik (Optional)**
   - Set up an OAuth2 provider in Authentik
   - Add environment variables (see [README.md](../README.md))
   - Restart the server

2. **Customize the Application**
   - Update `config/database.yml` for your database settings
   - Modify styles in `app/assets/stylesheets/`
   - Add custom recurrence patterns in `app/models/event.rb`

3. **Deploy to Production**
   - See [README.md](../README.md) for deployment instructions
   - Set production environment variables
   - Configure production domain in Devise settings

## Troubleshooting

### "Database does not exist"
Make sure PostgreSQL is running and create the database:
```bash
rails db:create
```

### "Connection refused" on port 3000
Another process might be using port 3000:
```bash
lsof -ti:3000 | xargs kill -9
rails server
```

### Asset compilation errors
Try rebuilding assets:
```bash
yarn build
yarn build:css
```

### Authentik OAuth errors
- Verify environment variables are set
- Check Authentik redirect URI matches your app
- Ensure the strategy file is loaded (check `lib/omniauth/strategies/authentik.rb`)

## Common Tasks

### Create a new admin user
```bash
rails console
User.create!(email: 'admin@hackerspace.com', password: 'secure_password', role: 'admin', name: 'Admin Name')
```

### Reset the database
```bash
rails db:reset
rails db:seed
```

### Check routes
```bash
rails routes
```

### Run Rails console
```bash
rails console
```

