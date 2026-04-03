# EventManager

A Rails-based event management system for hackerspaces. Allows users to create, manage, and discover events with support for recurring schedules, user authentication via Authentik or local accounts, and public iCal feeds.

Additional guides (Docker, deployment, security, testing, feature notes) live in **[docs/](docs/)**.

## Features

- **User Authentication**
  - Local account creation with Devise
  - Single Sign-On via Authentik (OAuth2)
  - Role-based access control (Admin/User)

- **Event Management**
  - Create one-time or recurring events
  - Flexible recurrence patterns:
    - Weekly (specific days)
    - Monthly (e.g., "first Tuesday", "third Monday")
    - Custom patterns
  - Event status management (Active, Postponed, Cancelled)
  - Rich event details (title, description, duration)

- **Admin Features**
  - User management dashboard
  - Promote users to admin
  - View all events and users

- **Public Features**
  - Public event listing (no authentication required)
  - iCal feed generation for each event
  - Calendar integration for recurring events

- **Modern UI**
  - Bootstrap 5 styling
  - Responsive design
  - Intuitive navigation

## Prerequisites

### Option 1: Docker (Recommended)
- Docker Engine 20.10+
- Docker Compose 2.0+

### Option 2: Native Installation
- Ruby 3.3.11
- PostgreSQL 12+
- Node.js and Yarn
- (Optional) Authentik instance for SSO

## Installation

### Docker Installation (Recommended)

The easiest way to get started is with Docker:

```bash
# Clone the repository
git clone <repository-url>
cd EventManager

# Start all services
docker compose -f docker-compose.dev.yml up -d

# Access the application
open http://localhost:3000
```

That's it! The application will be running with a PostgreSQL database, migrations applied, and sample data loaded.

**Default credentials:**
- Admin: admin@example.com / password123
- User: user1@example.com / password123

For more Docker commands and troubleshooting, see [docs/DOCKER.md](docs/DOCKER.md).

### Native Installation

If you prefer to run without Docker:

#### 1. Clone the Repository

```bash
git clone <repository-url>
cd EventManager
```

#### 2. Install Dependencies

```bash
bundle install
yarn install
```

#### 3. Configure Database

Edit `config/database.yml` with your PostgreSQL credentials, or set environment variables:

```bash
export DATABASE_HOST=localhost
export DATABASE_USER=your_username
export DATABASE_PASSWORD=your_password
```

#### 4. Create and Setup Database

```bash
rails db:create
rails db:migrate
rails db:seed
```

#### 5. Configure Authentik (Optional)

If you want to use Authentik for authentication, set the following environment variables:

```bash
export AUTHENTIK_CLIENT_ID=your_client_id
export AUTHENTIK_CLIENT_SECRET=your_client_secret
export AUTHENTIK_SITE_URL=https://your-authentik-instance.com
```

Templates live in `.env.development.example`, `.env.test.example`, `.env.staging.example`, and `.env.production.example`. For local setup, copy the development template:

```bash
cp .env.development.example .env
```

Then set Authentik (and other vars) in `.env`:

```
AUTHENTIK_CLIENT_ID=your_client_id
AUTHENTIK_CLIENT_SECRET=your_client_secret
AUTHENTIK_SITE_URL=https://your-authentik-instance.com
```

Docker Compose loads `.env` for variable substitution. For `rails server` outside Docker, export variables in your shell or add `dotenv-rails` to the Gemfile if you want Rails to read `.env` automatically.

#### 6. Configure Slack Notifications (Optional)

EventManager can post event reminders to Slack at 9 AM on the day of each event. To enable this:

1. **Create a Slack Incoming Webhook:**
   - Go to https://api.slack.com/apps
   - Create a new app or select an existing one
   - Navigate to "Incoming Webhooks" and activate it
   - Click "Add New Webhook to Workspace"
   - Select the channel (e.g., `#announcements`) where reminders should be posted
   - Copy the webhook URL

2. **Set the environment variable:**
   ```bash
   export SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
   ```

   Or add it to your `.env` file:
   ```
   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
   ```

3. **Set the application host (for event links in Slack messages):**
   ```bash
   export RAILS_HOST=your-domain.com
   export RAILS_PROTOCOL=https  # or http for development
   ```

   Or in `.env`:
   ```
   RAILS_HOST=your-domain.com
   RAILS_PROTOCOL=https
   ```

4. **Enable Slack in Site Configuration:**
   - Sign in as an admin
   - Go to Site Configuration
   - Check "Enable Slack Notifications"
   - Save

5. **Enable Slack announcements for events:**
   - When creating or editing an event, check "Post to Slack"
   - Reminders will only be posted for public and members-only events (not private or draft events)

**Note:** The Slack reminder job runs daily at 9 AM via Sidekiq. Make sure Sidekiq is running for reminders to be posted.

#### 7. Configure Social Media Reminders (Optional)

Social media reminders post to Instagram and Bluesky one week and one day prior to each event at 10 AM. To enable them:

1. **Set the environment variables:**
   ```bash
   export INSTAGRAM_ACCESS_TOKEN=your_instagram_token
   export INSTAGRAM_PAGE_ID=your_instagram_page_id
   export BLUESKY_HANDLE=your_bluesky_handle
   export BLUESKY_APP_PASSWORD=your_bluesky_app_password
   ```

   Or add them to your `.env` file:
   ```
   INSTAGRAM_ACCESS_TOKEN=your_instagram_token
   INSTAGRAM_PAGE_ID=your_instagram_page_id
   BLUESKY_HANDLE=your_bluesky_handle
   BLUESKY_APP_PASSWORD=your_bluesky_app_password
   ```

   **Note:** For Bluesky, you need to create an App Password in your Bluesky account settings 
   (Settings → App Passwords → Add App Password). Your handle should be in the format 
   `yourname.bsky.social` or your custom domain if you have one.

2. **Enable social reminders in Site Configuration:** check “Enable Social Media Reminders”.
3. **Enable the flag on individual events:** check “Post to Social Media” when creating/editing (only public or members-only events will post).

**Note:** The social reminder job runs daily at 10 AM via Sidekiq.

You can customize the prompt used when generating reminders in the Site Configuration page. The default prompt is `Create a short, friendly reminder for {{event_title}} happening on {{event_date}} at {{event_time}} at PDX Hackerspace.` Use the `{{event_title}}`, `{{event_date}}`, `{{event_time}}`, and `{{event_description}}` placeholders to include occurrence details from the UI.

#### 8. Configure AI Reminder Generation (Optional)

If you want Ollama to craft flavorful reminder copy, set:

```
export OLLAMA_SERVER=http://localhost:11434
```

Or add to `.env`:

```
OLLAMA_SERVER=http://localhost:11434
```

This server is queried to generate AI text a week or a day before each event, using the event description, time, and the fact that it's at PDX Hackerspace.

#### 9. Configure Host Email Reminders (Optional)

Event hosts can receive email notifications the day before Slack or social media reminders are scheduled to be posted. This gives them a chance to review and customize the reminder message.

1. **Set SMTP environment variables:**

   ```bash
   export SMTP_ADDRESS=smtp.example.com
   export SMTP_PORT=587
   export SMTP_DOMAIN=example.com
   export SMTP_USERNAME=your_smtp_username
   export SMTP_PASSWORD=your_smtp_password
   export SMTP_AUTHENTICATION=plain
   export SMTP_ENABLE_STARTTLS=true
   export MAILER_FROM_EMAIL=noreply@example.com
   ```

   Or add them to your `.env` file:

   ```
   SMTP_ADDRESS=smtp.example.com
   SMTP_PORT=587
   SMTP_DOMAIN=example.com
   SMTP_USERNAME=your_smtp_username
   SMTP_PASSWORD=your_smtp_password
   SMTP_AUTHENTICATION=plain
   SMTP_ENABLE_STARTTLS=true
   MAILER_FROM_EMAIL=noreply@example.com
   ```

2. **Host URL configuration:** Ensure `RAILS_HOST` and `RAILS_PROTOCOL` are set so email links work correctly.

3. **User opt-out:** Event hosts can disable email reminders in their profile settings (Edit Profile → Notification Preferences).

**Note:** The host reminder job runs daily at 8 AM via Sidekiq, one hour before the Slack reminder job.

#### 10. Start the Application

Development mode with asset compilation:

```bash
./bin/dev
```

Or manually:

```bash
# Terminal 1 - Rails server
rails server

# Terminal 2 - Asset compilation
yarn build
yarn watch:css
```

#### 11. Access the Application

Open your browser and navigate to:

```
http://localhost:3000
```

## Default User Accounts

After running `rails db:seed`, you'll have these accounts:

- **Admin**: admin@example.com / password123
- **User 1**: user1@example.com / password123
- **User 2**: user2@example.com / password123

## Usage

### Creating Events

1. Sign in to your account
2. Click "New Event" in the navigation bar
3. Fill in the event details:
   - Title and description
   - Start date/time and duration
   - Recurrence pattern (if applicable)
4. Save the event

### Managing Events

Event owners and admins can:
- Edit event details
- Postpone events (with a reason)
- Cancel events (with a reason)
- Reactivate postponed/cancelled events
- Delete events

### Subscribing to Events

Each event has a unique iCal feed URL that can be added to calendar applications:

1. Navigate to an event
2. Click "iCal Feed" button
3. Copy the URL or click to download
4. Add to your calendar app (Google Calendar, Apple Calendar, Outlook, etc.)

For recurring events, the iCal feed will include all occurrences for the next year.

### User Management (Admin Only)

Admins can access the user management dashboard at `/users` to:
- View all registered users
- Edit user profiles
- Promote users to admin
- Delete users

## Recurrence Patterns

The system uses the `ice_cube` gem to handle complex recurring events:

### Weekly Events
Select specific days of the week (e.g., every Tuesday and Thursday)

### Monthly Events
Choose patterns like:
- First Tuesday of every month
- Third Monday of every month
- Last Friday of every month

### Custom Patterns
Extend the `Event.build_schedule` method in `app/models/event.rb` for custom recurrence rules.

## Authentik Integration

### Setting up Authentik Provider

1. Log in to your Authentik admin panel
2. Navigate to Applications → Providers
3. Create a new OAuth2/OpenID Provider:
   - Name: EventManager
   - Client Type: Confidential
   - Redirect URIs: `http://localhost:3000/users/auth/authentik/callback` (adjust for production)
4. Note the Client ID and Client Secret
5. Create an Application and link it to the provider
6. Update your environment variables with the credentials

## Deployment

### Production Setup

1. Set production environment variables:
   - `SECRET_KEY_BASE`
   - `DATABASE_URL`
   - `AUTHENTIK_*` variables (if using)

2. Precompile assets:
   ```bash
   RAILS_ENV=production rails assets:precompile
   ```

3. Run migrations:
   ```bash
   RAILS_ENV=production rails db:migrate
   ```

4. Update `config/environments/production.rb` with your production domain for Devise mailer.

### Recommended Deployment Platforms

- Heroku
- Digital Ocean App Platform
- AWS Elastic Beanstalk
- Docker/Kubernetes

## Testing

The application has a comprehensive automated testing framework with **308 tests** covering all features.

### Run Tests

```bash
# Using Docker (recommended)
docker compose exec web bundle exec rspec

# Native installation
bundle exec rspec
```

### Test Suite
- **Unit Tests** (151 tests) - Models and business logic
- **Policy Tests** (48 tests) - Authorization rules
- **Request Tests** (89 tests) - Controllers and APIs
- **Feature Tests** (30 tests) - End-to-end workflows

**All tests passing with 100% success rate!** ✅

For complete testing documentation, see:
- **[docs/TESTING.md](docs/TESTING.md)** — complete testing guide
- **[docs/TEST_CHEATSHEET.md](docs/TEST_CHEATSHEET.md)** — quick reference
- **[docs/GOOD_MORNING_README.md](docs/GOOD_MORNING_README.md)** — implementation summary

## Technology Stack

- **Framework**: Ruby on Rails 7.0
- **Database**: PostgreSQL
- **Authentication**: Devise + OmniAuth
- **Authorization**: Pundit
- **Recurring Events**: IceCube
- **Calendar Export**: iCalendar
- **Frontend**: Bootstrap 5, Hotwire (Turbo + Stimulus)
- **JavaScript**: esbuild
- **CSS**: Sass
- **Testing**: RSpec, FactoryBot, Capybara

## Project Structure

```
app/
├── controllers/        # Application controllers
├── models/            # ActiveRecord models
├── policies/          # Pundit authorization policies
├── views/             # ERB templates
│   ├── events/       # Event CRUD views
│   ├── users/        # User management views
│   └── home/         # Landing page
├── helpers/           # View helpers
└── javascript/        # Stimulus controllers
config/
├── initializers/      # Devise, OmniAuth configuration
└── routes.rb         # Application routes
db/
├── migrate/          # Database migrations
└── seeds.rb          # Seed data
lib/
└── omniauth/         # Custom Authentik OAuth strategy
```

## API Endpoints

### Public Endpoints
- `GET /` - Home page
- `GET /events` - List all events
- `GET /events/:id` - Event details
- `GET /events/:token/ical` - iCal feed

### Authenticated Endpoints
- `POST /events` - Create event
- `PATCH /events/:id` - Update event
- `DELETE /events/:id` - Delete event
- `POST /events/:id/postpone` - Postpone event
- `POST /events/:id/cancel` - Cancel event
- `POST /events/:id/reactivate` - Reactivate event

### Admin Endpoints
- `GET /users` - List all users
- `GET /users/:id` - User profile
- `PATCH /users/:id` - Update user
- `DELETE /users/:id` - Delete user
- `POST /users/:id/make_admin` - Promote to admin

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Write tests
5. Submit a pull request

## License

This project is available as open source under the terms of the MIT License.

## Support

For issues and questions, please open an issue on the GitHub repository.
