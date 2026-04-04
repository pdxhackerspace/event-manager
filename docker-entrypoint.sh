#!/bin/bash
set -e

# Create necessary directories
mkdir -p /app/tmp/pids /app/tmp/cache /app/tmp/sockets

# Remove a potentially pre-existing server.pid for Rails.
rm -f /app/tmp/pids/server.pid

# Wait for database to be ready
echo "Waiting for database..."
until PGPASSWORD=$DATABASE_PASSWORD psql -h "$DATABASE_HOST" -U "$DATABASE_USER" -d "postgres" -c '\q' 2>/dev/null; do
  >&2 echo "Postgres is unavailable - sleeping"
  sleep 1
done

echo "Database is ready!"

# Create database if it doesn't exist
bundle exec rails db:create 2>/dev/null || echo "Database already exists"

# Run migrations from one process only (e.g. web). Sidekiq uses the same entrypoint; if both
# run db:migrate on an empty DB in parallel, initialize_database loads schema.rb twice and
# concurrent enable_extension("pg_trgm") hits PG::UniqueViolation on pg_extension_name_index.
if [ "${SKIP_DB_MIGRATE:-}" = "true" ]; then
  echo "Skipping database migrations (SKIP_DB_MIGRATE=true)"
else
  echo "Running database migrations..."
  bundle exec rails db:migrate
fi

# NEVER auto-seed in production - seeds are only for development/test
# To seed development: docker compose run --rm app bundle exec rails db:seed
if [ "$RAILS_ENV" = "development" ] || [ "$RAILS_ENV" = "test" ]; then
  # Check if database is seeded (check if any users exist)
  if bundle exec rails runner "exit(User.count > 0 ? 0 : 1)" 2>/dev/null; then
    echo "Database already seeded, skipping seed data"
  else
    echo "Seeding database..."
    bundle exec rails db:seed
  fi
else
  echo "Skipping seed data (production environment)"
fi

# Execute the main command
exec "$@"
