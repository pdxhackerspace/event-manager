class AddPostponedToToEventOccurrences < ActiveRecord::Migration[8.1]
  def change
    add_reference :event_occurrences, :postponed_to,
                  foreign_key: { to_table: :event_occurrences, on_delete: :nullify }, index: true
  end
end
