# frozen_string_literal: true

# Prometheus scrape endpoint. Disabled (404) unless METRICS_TOKEN is set, and
# requires `Authorization: Bearer <token>`. The token is deliberately not
# accepted as a query parameter so it never lands in access logs.
class MetricsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :load_site_config
  skip_forgery_protection

  before_action :require_token

  # GET /metrics
  def show
    render plain: PrometheusMetrics.new.render, content_type: PrometheusMetrics::CONTENT_TYPE
  end

  private

  def require_token
    expected = ENV['METRICS_TOKEN'].to_s
    return head :not_found if expected.blank?

    provided = request.authorization.to_s[/\ABearer (.+)\z/, 1].to_s
    return if ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(provided),
                                                          Digest::SHA256.hexdigest(expected))

    response.headers['WWW-Authenticate'] = 'Bearer realm="metrics"'
    head :unauthorized
  end
end
