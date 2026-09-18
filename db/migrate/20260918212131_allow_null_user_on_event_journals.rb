# frozen_string_literal: true

# EventJournal is an audit log: User declares `has_many :event_journals,
# dependent: :nullify` so entries outlive the account that made them. The column
# was NOT NULL, so that nullify raised and deleting any user who had ever touched
# an event failed outright.
class AllowNullUserOnEventJournals < ActiveRecord::Migration[8.1]
  def change
    change_column_null :event_journals, :user_id, true
  end
end
