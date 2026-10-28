RSpec.configure do |config|
  config.include ActiveJob::TestHelper

  config.around(:each, :mail) do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end
end
