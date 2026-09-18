# Counts the SQL queries a block issues, so specs can pin down N+1 regressions
# on the public feeds and index pages.
module QueryCounter
  IGNORED_QUERY = /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT|SHOW|SET)/i

  def count_queries(&)
    captured_queries(&).size
  end

  def captured_queries
    queries = []

    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      next if payload[:name] == 'SCHEMA' || payload[:cached]
      next if payload[:sql].match?(IGNORED_QUERY)

      queries << payload[:sql]
    end

    yield

    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end

RSpec.configure do |config|
  config.include QueryCounter
end
