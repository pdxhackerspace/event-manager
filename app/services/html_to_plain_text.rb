# Turns a fragment of HTML into the plain text stored beside it.
#
# Paragraphs and headings stay separated by a blank line so the result reads
# properly in calendar apps. Link URLs are kept when the visible text does not
# already include them, because the anchor itself does not survive as text.
class HtmlToPlainText
  BLOCK_TAGS = %w[div li tr ul ol].freeze
  BLANK_LINE_TAGS = %w[p blockquote h1 h2 h3 h4 h5 h6].freeze
  LINK_URL_TAGS = %w[p li blockquote h1 h2 h3 h4 h5 h6].freeze
  SPACED_TAGS = %w[td th].freeze

  def self.call(html)
    new(html).to_text
  end

  def initialize(html)
    @html = html.to_s
  end

  def to_text
    fragment = Nokogiri::HTML5.fragment(@html)
    fragment.css('script, style').each(&:remove)

    node_to_plain_text(fragment)
      .gsub("\u00a0", ' ')
      .gsub(/[ \t]+\n/, "\n")
      .gsub(/\n[ \t]+/, "\n")
      .gsub(/\n{3,}/, "\n\n")
      .strip
  end

  private

  def node_to_plain_text(node)
    return node.text if node.text?
    return "\n" if node.element? && node.name == 'br'
    return node.children.map { |child| node_to_plain_text(child) }.join unless node.element?

    text = node.children.map { |child| node_to_plain_text(child) }.join
    text = "- #{text.lstrip}" if node.name == 'li' && text.strip.present?
    text = append_link_urls(text, link_urls(node)) if LINK_URL_TAGS.include?(node.name)
    text += "\n" if BLOCK_TAGS.include?(node.name) || BLANK_LINE_TAGS.include?(node.name)
    text += "\n" if BLANK_LINE_TAGS.include?(node.name)
    text += ' ' if SPACED_TAGS.include?(node.name)
    text
  end

  def link_urls(node)
    node.css('a[href]').filter_map { |link| link['href'].presence }
  end

  def append_link_urls(text, urls)
    visible = urls.reject { |url| text.include?(url) }
    return text if visible.blank?

    "#{text.rstrip}\n\n#{visible.join("\n")}\n"
  end
end
