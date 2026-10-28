require 'rails_helper'

RSpec.describe EventDescription do
  describe '.sanitize' do
    it 'removes scripts, event handlers, and inline styles' do
      html = '<p style="color:red" onclick="alert(1)">Hi</p><script>alert(1)</script><img src="x" onerror="alert(1)">'

      expect(described_class.sanitize(html)).to eq('<p>Hi</p>')
    end

    it 'keeps safe links and drops javascript and data URLs' do
      html = <<~HTML
        <p><a href="https://example.com">site</a>
        <a href="mailto:host@example.com">mail</a>
        <a href="javascript:alert(1)">bad</a>
        <a href="data:text/html,hi">data</a></p>
      HTML
      cleaned = described_class.sanitize(html)

      expect(cleaned).to include('href="https://example.com"')
      expect(cleaned).to include('href="mailto:host@example.com"')
      expect(cleaned).not_to include('javascript:')
      expect(cleaned).not_to include('data:')
    end

    it 'returns nil for markup that has no visible text' do
      expect(described_class.sanitize('<p><br></p>')).to be_nil
      expect(described_class.sanitize('<script>alert(1)</script>')).to be_nil
    end

    it 'is stable when run twice' do
      html = '<p>Hello <strong>there</strong></p><ul><li>One</li></ul>'
      once = described_class.sanitize(html)

      expect(described_class.sanitize(once)).to eq(once)
    end
  end

  describe '.for_display' do
    it 'adds rel to links and returns markup that is safe to render' do
      rendered = described_class.for_display('<p><a href="https://example.com">site</a></p>')

      expect(rendered).to include('rel="noopener nofollow"')
      expect(rendered).to be_html_safe
    end
  end

  describe '.assign_pair' do
    it 'regenerates the plain text when sync is requested' do
      attrs = { 'description_html' => '<p>Fresh <a href="https://example.com">link</a></p>', 'description' => 'stale' }

      described_class.assign_pair(attrs, html_key: 'description_html', text_key: 'description', sync: true)

      expect(attrs['description']).to eq("Fresh link\n\nhttps://example.com")
    end

    it 'keeps hand-edited plain text when sync is off' do
      attrs = { 'description_html' => '<p>Formatted</p>', 'description' => 'Hand edited' }

      described_class.assign_pair(attrs, html_key: 'description_html', text_key: 'description', sync: false)

      expect(attrs['description']).to eq('Hand edited')
      expect(attrs['description_html']).to include('Formatted')
    end

    it 'fills blank plain text from the HTML' do
      attrs = { 'description_html' => '<p>Hello</p>', 'description' => '' }

      described_class.assign_pair(attrs, html_key: 'description_html', text_key: 'description', sync: false)

      expect(attrs['description']).to eq('Hello')
    end

    it 'leaves the hash alone when the HTML key was not submitted' do
      attrs = { 'description' => 'Keep me' }

      described_class.assign_pair(attrs, html_key: 'description_html', text_key: 'description', sync: true)

      expect(attrs).to eq({ 'description' => 'Keep me' })
    end
  end
end
