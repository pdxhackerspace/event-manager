RSpec.configure do |config|
  config.before do
    # Jobs stay in a local queue. Sidekiq 8.1 enables this with Sidekiq.testing!.
    Sidekiq.testing!(:fake)
  end

  config.after do
    # Clear any queued jobs after each test
    Sidekiq::Worker.clear_all
  end
end
