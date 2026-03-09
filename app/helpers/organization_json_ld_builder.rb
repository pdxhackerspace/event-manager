class OrganizationJsonLdBuilder
  def initialize(site_config, helper)
    @site_config = site_config
    @helper = helper
  end

  def build
    schema = {
      '@context': 'https://schema.org',
      '@type': 'Organization',
      name: @site_config&.organization_name || 'EventManager',
      url: @site_config&.website_url || @helper.root_url
    }
    schema[:email] = @site_config.contact_email if @site_config&.contact_email.present?
    schema[:telephone] = @site_config.contact_phone if @site_config&.contact_phone.present?
    schema[:address] = { '@type': 'PostalAddress', streetAddress: @site_config.address } if @site_config&.address.present?
    schema[:logo] = @helper.url_for(@site_config.banner_image) if @site_config&.banner_image&.attached?
    schema
  end
end
