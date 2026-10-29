class AddSchedulingConflictsToEvents < ActiveRecord::Migration[8.1]
  def change
    change_table :events, bulk: true do |t|
      t.boolean :busy, null: false, default: false
      t.string :exclusive_status, null: false, default: 'none'
      t.datetime :exclusive_requested_at
      t.datetime :exclusive_reviewed_at
      t.text :exclusive_review_note
      t.integer :conflict_buffer_minutes
    end

    add_reference :events, :exclusive_requested_by, foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :events, :exclusive_reviewed_by, foreign_key: { to_table: :users, on_delete: :nullify }
    add_index :events, :exclusive_status
    add_check_constraint :events,
                         "exclusive_status IN ('none', 'pending', 'approved', 'denied')",
                         name: 'events_exclusive_status_check'

    add_column :site_configs, :default_conflict_buffer_minutes, :integer, null: false, default: 60
  end
end
