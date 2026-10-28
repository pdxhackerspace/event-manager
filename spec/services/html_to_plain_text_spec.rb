require 'rails_helper'

RSpec.describe HtmlToPlainText do
  def text(html)
    described_class.call(html)
  end

  it 'separates paragraphs with a blank line' do
    expect(text('<p>Hello</p><p>World</p>')).to eq("Hello\n\nWorld")
  end

  it 'turns br into a line break inside a paragraph' do
    expect(text('<p>Hello<br>there</p>')).to eq("Hello\nthere")
  end

  it 'turns lists into bullets' do
    expect(text('<ul><li>One</li><li>Two</li></ul>')).to eq("- One\n- Two")
  end

  it 'keeps a link URL when the visible text does not include it' do
    html = '<p>See <a href="https://example.com">the site</a>.</p>'

    expect(text(html)).to eq("See the site.\n\nhttps://example.com")
  end

  it 'does not repeat a URL that is already the link text' do
    html = '<p><a href="https://example.com">https://example.com</a></p>'

    expect(text(html)).to eq('https://example.com')
  end

  it 'puts headings on their own lines' do
    expect(text('<h2>Title</h2><p>Body</p>')).to eq("Title\n\nBody")
  end

  it 'turns non-breaking spaces into spaces' do
    expect(text('<p>Hello&nbsp;there</p>')).to eq('Hello there')
  end

  it 'collapses long runs of blank lines' do
    expect(text('<p>A<br><br><br>B</p>')).to eq("A\n\nB")
  end

  it 'drops script and style contents' do
    html = '<p>Hi</p><script>alert(1)</script><style>body{}</style>'

    expect(text(html)).to eq('Hi')
  end

  it 'returns an empty string for blank input' do
    expect(text(nil)).to eq('')
    expect(text('<p><br></p>')).to eq('')
  end
end
