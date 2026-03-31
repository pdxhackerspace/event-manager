# Testing Guide for EventManager

This document provides comprehensive information about the testing framework and how to run tests for the EventManager application.

## Overview

The EventManager application uses **RSpec** as its testing framework, along with several supporting libraries to provide comprehensive test coverage.

### Testing Stack

- **RSpec** (6.x) - Primary testing framework
- **FactoryBot** - Test data generation
- **Faker** - Realistic fake data generation
- **Capybara** - Feature/integration testing
- **Shoulda Matchers** - Simplified Rails matchers
- **Database Cleaner** - Test database management
- **SimpleCov** - Code coverage reporting
- **Pundit RSpec** - Policy testing helpers

## Test Organization

Tests are organized in the `spec/` directory following Rails conventions:

```
spec/
├── factories/           # FactoryBot factories for test data
│   ├── users.rb
│   ├── events.rb
│   ├── event_occurrences.rb
│   ├── event_hosts.rb
│   └── event_journals.rb
├── features/            # End-to-end feature tests (smoke tests)
│   └── smoke_tests_spec.rb
├── models/              # Model unit tests
│   ├── user_spec.rb
│   ├── event_spec.rb
│   ├── event_occurrence_spec.rb
│   ├── event_host_spec.rb
│   └── event_journal_spec.rb
├── policies/            # Pundit authorization policy tests
│   ├── user_policy_spec.rb
│   └── event_policy_spec.rb
├── requests/            # Controller/request integration tests
│   ├── events_spec.rb
│   ├── event_occurrences_spec.rb
│   ├── calendar_spec.rb
│   └── json_api_spec.rb
├── support/             # Test configuration and helpers
│   ├── factory_bot.rb
│   ├── shoulda_matchers.rb
│   └── database_cleaner.rb
├── rails_helper.rb      # Rails-specific test configuration
└── spec_helper.rb       # General RSpec configuration
```

## Running Tests

### Prerequisites

Ensure your Docker containers are running:

```bash
docker compose up
```

### Run All Tests

```bash
docker compose exec web bundle exec rspec
```

### Run Specific Test Files

```bash
# Run model tests only
docker compose exec web bundle exec rspec spec/models/

# Run a specific model test
docker compose exec web bundle exec rspec spec/models/event_spec.rb

# Run a specific test by line number
docker compose exec web bundle exec rspec spec/models/event_spec.rb:45
```

### Run Tests by Type

```bash
# Unit tests (models)
docker compose exec web bundle exec rspec spec/models/

# Policy tests
docker compose exec web bundle exec rspec spec/policies/

# Request/Integration tests
docker compose exec web bundle exec rspec spec/requests/

# Feature tests (smoke tests)
docker compose exec web bundle exec rspec spec/features/
```

### Run with Different Formats

```bash
# Progress format (default)
docker compose exec web bundle exec rspec --format progress

# Documentation format (detailed)
docker compose exec web bundle exec rspec --format documentation

# Failures only
docker compose exec web bundle exec rspec --format failures
```

### Run Tests with Tags

Tests can be tagged and run selectively:

```bash
# Run only slow tests
docker compose exec web bundle exec rspec --tag slow

# Skip slow tests
docker compose exec web bundle exec rspec --tag ~slow
```

## Test Coverage

To generate a code coverage report:

```bash
# Run tests with coverage
docker compose exec web bash -c "COVERAGE=true bundle exec rspec"

# View the coverage report
# Open coverage/index.html in your browser
```

Coverage reports show:
- Overall test coverage percentage
- Per-file coverage
- Uncovered lines of code
- Branch coverage

## Test Database

### Setup Test Database

```bash
# Create and prepare test database
docker compose exec web bash -c "RAILS_ENV=test rails db:create db:schema:load"
```

### Reset Test Database

```bash
# Drop and recreate test database
docker compose exec web bash -c "RAILS_ENV=test rails db:drop db:create db:schema:load"
```

### Database Cleaning

DatabaseCleaner is configured to automatically clean the test database between test runs using transactions for speed.

## Writing Tests

### Model Tests

Model tests verify business logic, validations, associations, and callbacks:

```ruby
require 'rails_helper'

RSpec.describe Event, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:title) }
    it { should validate_numericality_of(:duration).is_greater_than(0) }
  end

  describe 'associations' do
    it { should belong_to(:user) }
    it { should have_many(:occurrences) }
  end

  describe '#postpone!' do
    let(:event) { create(:event) }
    
    it 'changes status to postponed' do
      event.postpone!(1.week.from_now)
      expect(event.status).to eq('postponed')
    end
  end
end
```

### Request Tests

Request tests verify controller behavior and HTTP responses:

```ruby
require 'rails_helper'

RSpec.describe "Events", type: :request do
  let(:user) { create(:user) }

  describe "GET /events" do
    it "returns success" do
      get events_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /events" do
    before { sign_in user }

    it "creates a new event" do
      expect {
        post events_path, params: { event: attributes_for(:event) }
      }.to change(Event, :count).by(1)
    end
  end
end
```

### Feature Tests

Feature tests verify complete user workflows:

```ruby
require 'rails_helper'

RSpec.describe "Event Creation", type: :feature do
  let(:user) { create(:user) }

  before { sign_in user }

  it "allows creating a new event" do
    visit new_event_path
    
    fill_in 'Title', with: 'New Event'
    fill_in 'Description', with: 'Event Description'
    click_button 'Create Event'
    
    expect(page).to have_content('Event was successfully created')
    expect(page).to have_content('New Event')
  end
end
```

### Policy Tests

Policy tests verify authorization rules:

```ruby
require 'rails_helper'

RSpec.describe EventPolicy, type: :policy do
  subject { described_class.new(user, event) }

  let(:event) { create(:event) }
  let(:user) { create(:user) }

  context 'for a regular user' do
    it { should_not permit_action(:destroy) }
  end

  context 'for an admin' do
    let(:user) { create(:user, :admin) }
    it { should permit_action(:destroy) }
  end
end
```

## Using Factories

FactoryBot factories provide convenient test data creation:

```ruby
# Create a basic user
user = create(:user)

# Create with specific attributes
admin = create(:user, :admin, name: 'Admin User')

# Create without saving
event = build(:event)

# Create with associations
event_with_host = create(:event, user: user)

# Create with traits
weekly_event = create(:event, :weekly)
postponed_event = create(:event, :postponed)
event_with_banner = create(:event, :with_banner)

# Build attributes hash
event_attrs = attributes_for(:event)
```

## Common Test Patterns

### Testing Callbacks

```ruby
describe 'callbacks' do
  it 'generates ical_token on create' do
    event = build(:event)
    expect(event.ical_token).to be_nil
    event.save
    expect(event.ical_token).to be_present
  end
end
```

### Testing Scopes

```ruby
describe 'scopes' do
  let!(:active_event) { create(:event, status: 'active') }
  let!(:cancelled_event) { create(:event, :cancelled) }

  describe '.active' do
    it 'returns only active events' do
      expect(Event.active).to include(active_event)
      expect(Event.active).not_to include(cancelled_event)
    end
  end
end
```

### Testing JSON APIs

```ruby
describe "GET /events.json" do
  it "returns JSON" do
    get events_path(format: :json)
    expect(response.content_type).to include('application/json')
  end

  it "includes event data" do
    event = create(:event, visibility: 'public')
    get events_path(format: :json)
    json = JSON.parse(response.body)
    expect(json['events'].first['title']).to eq(event.title)
  end
end
```

### Testing Authentication

```ruby
describe "protected actions" do
  context "as a guest" do
    it "redirects to sign in" do
      get new_event_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  context "as logged in user" do
    before { sign_in create(:user) }

    it "allows access" do
      get new_event_path
      expect(response).to have_http_status(:success)
    end
  end
end
```

## Test Coverage Goals

Aim for these coverage targets:

- **Models**: 95%+ coverage
  - All validations
  - All associations
  - All methods
  - All callbacks
  - All scopes

- **Controllers**: 90%+ coverage
  - All actions
  - All authorization checks
  - Success and failure paths

- **Policies**: 100% coverage
  - All permission checks
  - All scopes

- **Features**: Core user workflows
  - Happy paths
  - Critical error paths

## Continuous Integration

Tests should be run automatically on:
- Every pull request
- Before deployment
- On a regular schedule (nightly)

Example CI configuration:

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:13
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v2
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.1.2
      - name: Install dependencies
        run: bundle install
      - name: Setup database
        run: |
          RAILS_ENV=test bundle exec rails db:create db:schema:load
      - name: Run tests
        run: bundle exec rspec
```

## Troubleshooting

### Tests Failing Due to Database Issues

```bash
# Reset the test database
docker compose exec web bash -c "RAILS_ENV=test rails db:drop db:create db:schema:load"
```

### Tests Failing Due to Stale Data

```bash
# DatabaseCleaner should handle this, but you can manually clean:
docker compose exec web bash -c "RAILS_ENV=test rails db:test:prepare"
```

### Slow Tests

```bash
# Profile slow tests
docker compose exec web bundle exec rspec --profile 10

# Run tests in parallel (if configured)
docker compose exec web bundle exec parallel_rspec spec/
```

### Debugging Failing Tests

```ruby
# Add debugging output
it "does something" do
  event = create(:event)
  puts event.inspect  # Add debugging
  binding.pry  # Add breakpoint (requires pry gem)
  expect(event).to be_valid
end
```

## Best Practices

1. **Keep tests fast**: Use factories efficiently, avoid unnecessary database hits
2. **Test behavior, not implementation**: Test what the code does, not how
3. **One assertion per test**: Makes failures easier to diagnose
4. **Use descriptive names**: Test names should explain what they verify
5. **Follow AAA pattern**: Arrange, Act, Assert
6. **Don't test the framework**: Trust that Rails works, test your code
7. **Use let and let!**: For better test organization
8. **Avoid brittle selectors**: In feature tests, use semantic selectors
9. **Test edge cases**: Don't just test the happy path
10. **Keep tests DRY**: But prefer clarity over brevity

## Resources

- [RSpec Documentation](https://rspec.info/)
- [FactoryBot Documentation](https://github.com/thoughtbot/factory_bot)
- [Capybara Documentation](https://github.com/teamcapybara/capybara)
- [Better Specs](https://www.betterspecs.org/) - RSpec best practices
- [Pundit Testing](https://github.com/varvet/pundit#testing)

## Getting Help

If you encounter issues with tests:

1. Check the test output carefully - error messages are usually helpful
2. Review the test database state
3. Ensure all factories are properly configured
4. Check that test dependencies are installed
5. Verify Docker containers are running properly

## Summary

The EventManager test suite provides comprehensive coverage across all layers of the application:

- ✅ **Unit tests** for models and business logic
- ✅ **Integration tests** for controllers and requests
- ✅ **Feature tests** for end-to-end workflows
- ✅ **Policy tests** for authorization rules
- ✅ **API tests** for JSON endpoints

Run tests regularly during development to catch issues early and ensure code quality!

