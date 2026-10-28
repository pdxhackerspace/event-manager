module EmailTestMode
  module_function

  def recipient_for(address)
    return address unless test_mode?

    SiteConfig.current.email_test_mode_address
  end

  def test_mode?
    config = SiteConfig.current
    config&.email_test_mode_enabled? && config.email_test_mode_address.present?
  end
end
