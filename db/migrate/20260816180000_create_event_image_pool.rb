class CreateEventImagePool < ActiveRecord::Migration[8.1]
  class MigrationEvent < ApplicationRecord
    self.table_name = 'events'
  end

  class MigrationEventOccurrence < ApplicationRecord
    self.table_name = 'event_occurrences'
  end

  class MigrationEventImage < ApplicationRecord
    self.table_name = 'event_images'
  end

  class MigrationAttachment < ApplicationRecord
    self.table_name = 'active_storage_attachments'
  end

  def up
    create_table :event_images do |t|
      t.references :event, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.boolean :in_pool, null: false, default: true

      t.timestamps
    end

    add_index :event_images, %i[event_id position]

    change_table :events, bulk: true do |t|
      t.string :image_selection_mode, null: false, default: 'fixed'
      t.bigint :fixed_event_image_id
      t.integer :image_cycle_index, null: false, default: 0
    end

    add_index :events, :fixed_event_image_id

    change_table :event_occurrences, bulk: true do |t|
      t.references :event_image, foreign_key: true
      t.boolean :custom_event_image, null: false, default: false
    end

    migrate_event_banners
    migrate_occurrence_banners
    backfill_occurrence_images
  end

  def down
    revert_occurrence_banners
    revert_event_banners

    remove_reference :event_occurrences, :event_image, foreign_key: true
    remove_column :event_occurrences, :custom_event_image

    remove_index :events, :fixed_event_image_id
    change_table :events, bulk: true do |t|
      t.remove :image_selection_mode
      t.remove :fixed_event_image_id
      t.remove :image_cycle_index
    end

    drop_table :event_images
  end

  private

  def migrate_event_banners
    say_with_time 'Migrating event banner images to image pool' do
      MigrationAttachment.where(record_type: 'Event', name: 'banner_image').find_each do |attachment|
        event_image = MigrationEventImage.create!(
          event_id: attachment.record_id,
          position: 0,
          in_pool: true
        )
        attachment.update!(record_type: 'EventImage', record_id: event_image.id, name: 'image')
        MigrationEvent.where(id: attachment.record_id).update_all(
          fixed_event_image_id: event_image.id,
          image_selection_mode: 'fixed'
        )
      end
    end
  end

  def migrate_occurrence_banners
    say_with_time 'Migrating occurrence custom banner images' do
      MigrationAttachment.where(record_type: 'EventOccurrence', name: 'banner_image').find_each do |attachment|
        occurrence = MigrationEventOccurrence.find(attachment.record_id)
        next_position = MigrationEventImage.where(event_id: occurrence.event_id).maximum(:position).to_i + 1

        event_image = MigrationEventImage.create!(
          event_id: occurrence.event_id,
          position: next_position,
          in_pool: false
        )
        attachment.update!(record_type: 'EventImage', record_id: event_image.id, name: 'image')
        occurrence.update!(event_image_id: event_image.id, custom_event_image: true)
      end
    end
  end

  def backfill_occurrence_images
    say_with_time 'Backfilling occurrence image assignments from event pool' do
      MigrationEventOccurrence.where(event_image_id: nil).find_each do |occurrence|
        fixed_id = MigrationEvent.where(id: occurrence.event_id).pick(:fixed_event_image_id)
        occurrence.update!(event_image_id: fixed_id) if fixed_id
      end
    end
  end

  def revert_event_banners
    MigrationEventImage.where(in_pool: true, position: 0).find_each do |event_image|
      MigrationAttachment.where(record_type: 'EventImage', record_id: event_image.id, name: 'image')
                         .update_all(record_type: 'Event', record_id: event_image.event_id, name: 'banner_image')
    end
  end

  def revert_occurrence_banners
    MigrationEventOccurrence.where(custom_event_image: true).where.not(event_image_id: nil).find_each do |occurrence|
      MigrationAttachment.where(record_type: 'EventImage', record_id: occurrence.event_image_id, name: 'image')
                         .update_all(record_type: 'EventOccurrence', record_id: occurrence.id, name: 'banner_image')
    end
  end
end
