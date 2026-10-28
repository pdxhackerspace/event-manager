class AddRsvps < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :username, :string
    add_index :users, :username

    change_table :events, bulk: true do |t|
      t.boolean :rsvp_enabled, null: false, default: false
      t.integer :capacity
      t.boolean :waitlist_enabled, null: false, default: true
      t.string :waitlist_mode, null: false, default: 'first_come'
      t.integer :rsvp_closes_minutes_before, null: false, default: 0
    end
    add_check_constraint :events, "waitlist_mode IN ('first_come', 'sequential')", name: 'events_waitlist_mode_check'

    change_table :event_occurrences, bulk: true do |t|
      t.integer :capacity_override
      t.boolean :rsvp_disabled, null: false, default: false
      t.datetime :checkin_finalized_at
    end

    add_column :event_hosts, :notify_on_rsvp, :boolean, null: false, default: false

    change_table :site_configs, bulk: true do |t|
      t.boolean :rsvps_enabled, null: false, default: true
      t.integer :rsvp_offer_hours, null: false, default: 24
      t.integer :rsvp_last_call_hours, null: false, default: 4
      t.integer :rsvp_guest_retention_days, null: false, default: 30
    end

    create_table :rsvps do |t|
      t.references :event_occurrence, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :name
      t.string :email
      t.string :status, null: false, default: 'pending'
      t.datetime :waitlisted_at
      t.datetime :offer_held_until
      t.datetime :last_offered_at
      t.datetime :offer_reminder_sent_at
      t.datetime :confirmed_at
      t.datetime :cancelled_at
      t.references :cancelled_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :cancellation_reason
      t.string :cancelled_via
      t.string :manage_token, null: false
      t.boolean :reminders_opted_out, null: false, default: false
      t.datetime :reminder_7d_sent_at
      t.datetime :reminder_1d_sent_at
      t.datetime :reminder_day_of_sent_at
      t.datetime :release_nag_sent_at
      t.boolean :attended
      t.references :checked_in_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :checked_in_at
      t.datetime :anonymized_at
      t.timestamps
    end

    add_index :rsvps, :manage_token, unique: true
    add_index :rsvps, %i[event_occurrence_id status waitlisted_at], name: 'index_rsvps_on_occurrence_status_and_waitlisted_at'
    add_index :rsvps, "event_occurrence_id, lower(email)",
              unique: true,
              where: "status <> 'cancelled' AND email IS NOT NULL",
              name: 'index_rsvps_on_occurrence_and_lower_email'
    add_index :rsvps, %i[event_occurrence_id user_id],
              unique: true,
              where: "status <> 'cancelled' AND user_id IS NOT NULL",
              name: 'index_rsvps_on_occurrence_and_user'
    add_check_constraint :rsvps, "status IN ('pending', 'confirmed', 'waitlisted', 'cancelled')", name: 'rsvps_status_check'
    add_check_constraint :rsvps,
                          "cancelled_via IS NULL OR cancelled_via IN ('self', 'host', 'admin', 'occurrence_cancelled')",
                          name: 'rsvps_cancelled_via_check'
  end
end
