# Shared plumbing for the public JSON feeds.
#
# `url_for` is injected rather than reached for directly so the serializers stay
# independent of the controller; `spectra6` is a Spectra6BannerLookup primed with
# every attachment in the batch.
class FeedSerializer
  def initialize(record, url_for:, spectra6:)
    @record = record
    @url_for = url_for
    @spectra6 = spectra6
  end

  private

  attr_reader :record

  def banner_url(attachment)
    return nil unless attachment&.attached?

    @url_for.call(attachment)
  end

  def spectra6_banner_url(attachment)
    blob = @spectra6.blob_for(attachment)
    blob && @url_for.call(blob)
  end

  def host_names(event)
    event.hosts.map { |host| host.name || host.email }
  end

  def location_json(location)
    return nil unless location

    { id: location.id, name: location.name }
  end
end
