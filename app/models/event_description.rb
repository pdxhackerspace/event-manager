# Sanitizes event description HTML and keeps the plain-text column beside it.
#
# Hosts write descriptions that are shown on public pages, embeds, and RSS, so
# the allowed markup is a short list and link URLs are limited to http, https,
# and mailto. TINYMCE_VALID_ELEMENTS must stay in step with ALLOWED_TAGS.
module EventDescription
  ALLOWED_TAGS = %w[p br strong b em i u s h2 h3 h4 ul ol li a blockquote hr].freeze
  ALLOWED_ATTRIBUTES = %w[href].freeze
  DISPLAY_ATTRIBUTES = %w[href rel].freeze
  ALLOWED_PROTOCOLS = %w[http https mailto].freeze
  TINYMCE_VALID_ELEMENTS = 'p,br,strong/b,em/i,u,s,h2,h3,h4,ul,ol,li,a[href],blockquote,hr'.freeze

  class << self
    def sanitize(html)
      return nil if html.blank?

      cleaned = restrict_link_protocols(safe_list(remove_active_content(html), ALLOWED_ATTRIBUTES)).strip
      return nil if cleaned.blank? || HtmlToPlainText.call(cleaned).blank?

      cleaned
    end

    # Safe to render: sanitized, with rel="noopener nofollow" on links.
    # rails-html-sanitizer 1.7 returns a plain String, so this is marked safe
    # only after that second pass.
    def for_display(html)
      cleaned = sanitize(html)
      return nil if cleaned.blank?

      rendered = Rails::HTML5::SafeListSanitizer.new.sanitize(
        add_link_rel(cleaned),
        tags: ALLOWED_TAGS,
        attributes: DISPLAY_ATTRIBUTES
      )
      return nil if rendered.blank?

      rendered.html_safe # rubocop:disable Rails/OutputSafety
    end

    # Rewrites the HTML key in place. When +sync+ is set, or the plain text is
    # blank, the plain text is regenerated from the sanitized HTML.
    def assign_pair(attrs, html_key:, text_key:, sync:)
      return attrs unless attrs.key?(html_key)

      attrs[html_key] = sanitize(attrs[html_key])
      attrs[text_key] = HtmlToPlainText.call(attrs[html_key]) if sync || attrs[text_key].blank?
      attrs
    end

    private

    def remove_active_content(html)
      fragment = Nokogiri::HTML5.fragment(html.to_s)
      fragment.css('script, style, iframe, object, embed, noscript').each(&:remove)
      fragment.children.map(&:to_html).join
    end

    def safe_list(html, attributes)
      Rails::HTML5::SafeListSanitizer.new.sanitize(
        html.to_s,
        tags: ALLOWED_TAGS,
        attributes: attributes
      ).to_s
    end

    def restrict_link_protocols(html)
      fragment = Nokogiri::HTML5.fragment(html)
      fragment.css('a').each do |link|
        next if allowed_href?(link['href'])

        link.replace(link.children)
      end
      fragment.children.map(&:to_html).join
    end

    def add_link_rel(html)
      fragment = Nokogiri::HTML5.fragment(html)
      fragment.css('a[href]').each do |link|
        link['rel'] = 'noopener nofollow'
      end
      fragment.children.map(&:to_html).join
    end

    def allowed_href?(href)
      return false if href.blank?

      scheme = URI.parse(href.strip).scheme&.downcase
      ALLOWED_PROTOCOLS.include?(scheme)
    rescue URI::InvalidURIError
      false
    end
  end
end
