# rubocop:disable Rails/HelperInstanceVariable, Rails/OutputSafety
module SeoHelper
  # Set page title - call from views
  def page_title(title)
    content_for(:page_title) { title }
  end

  # Set page description
  def page_description(description)
    content_for(:page_description) { description&.truncate(160) }
  end

  # Set Open Graph image
  def og_image(image_url)
    content_for(:og_image) { image_url }
  end

  # Generate an absolute image URL for link preview crawlers.
  def preview_image_url(attachment)
    rails_blob_url(attachment) if attachment&.attached?
  end

  # Set canonical URL
  def canonical_url(url)
    content_for(:canonical_url) { url }
  end

  # Set page type for Open Graph
  def og_type(type)
    content_for(:og_type) { type }
  end

  # Generate full title with site name
  def full_page_title
    site_name = @site_config&.organization_name || 'EventManager'
    content_for?(:page_title) ? "#{content_for(:page_title)} | #{site_name}" : "#{site_name} - Hackerspace Event Management"
  end

  # Get page description with fallback
  def meta_description
    return content_for(:page_description) if content_for?(:page_description)

    "#{@site_config&.organization_name || 'EventManager'} - Find and manage hackerspace events, workshops, and meetups."
  end

  # Get Open Graph image URL
  def meta_og_image
    return content_for(:og_image) if content_for?(:og_image)

    preview_image_url(@site_config&.banner_image)
  end

  # Get canonical URL
  def meta_canonical_url
    content_for?(:canonical_url) ? content_for(:canonical_url) : request.original_url.split('?').first
  end

  # Get Open Graph type
  def meta_og_type
    content_for?(:og_type) ? content_for(:og_type) : 'website'
  end

  # Generate JSON-LD for an event
  def event_json_ld(event, occurrence = nil)
    EventJsonLdBuilder.new(event, occurrence, @site_config, self).build.to_json.html_safe
  end

  # Generate JSON-LD for organization
  def organization_json_ld
    OrganizationJsonLdBuilder.new(@site_config, self).build.to_json.html_safe
  end

  # Generate breadcrumb JSON-LD
  def breadcrumb_json_ld(items)
    list_items = items.each_with_index.map do |item, index|
      { '@type': 'ListItem', position: index + 1, name: item[:name], item: item[:url] }
    end
    { '@context': 'https://schema.org', '@type': 'BreadcrumbList', itemListElement: list_items }.to_json.html_safe
  end
end
# rubocop:enable Rails/HelperInstanceVariable, Rails/OutputSafety
