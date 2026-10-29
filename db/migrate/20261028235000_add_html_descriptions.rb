class AddHtmlDescriptions < ActiveRecord::Migration[8.1]
  def up
    add_column :events, :description_html, :text
    add_column :event_occurrences, :custom_description_html, :text

    Event.reset_column_information
    EventOccurrence.reset_column_information

    backfill(Event, :description, :description_html)
    backfill(EventOccurrence, :custom_description, :custom_description_html)
  end

  def down
    remove_column :events, :description_html
    remove_column :event_occurrences, :custom_description_html
  end

  private

  # Existing descriptions are plain text. Wrap them the way the event page
  # already presented them, so formatted and unformatted views match.
  def backfill(model, source, target)
    model.unscoped.find_each do |record|
      text = record.public_send(source).to_s
      next if text.strip.empty?

      record.update_columns(target => plain_text_to_html(text)) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def plain_text_to_html(text)
    escaped = ERB::Util.html_escape(text.gsub("\r\n", "\n").strip)
    escaped.split(/\n{2,}/).map { |paragraph| "<p>#{paragraph.gsub("\n", '<br>')}</p>" }.join
  end
end
