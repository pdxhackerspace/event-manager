RSpec.configure do |config|
  config.use_transactional_fixtures = false

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before do
    DatabaseCleaner.strategy = :transaction
  end

  config.before(:each, :js) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before(:each, :concurrency) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before do
    DatabaseCleaner.start
  end

  config.after do
    DatabaseCleaner.clean
  rescue ActiveRecord::StatementInvalid => e
    # If transaction is in a failed state, rollback and retry
    raise unless e.cause.is_a?(PG::InFailedSqlTransaction)

    ActiveRecord::Base.connection.rollback_db_transaction
    DatabaseCleaner.clean

  end
end
