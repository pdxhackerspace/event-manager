class EventImage < ApplicationRecord
  belongs_to :event

  has_one_attached :image do |attachable|
    attachable.variant :thumb, resize_to_limit: [300, 300]
  end

  scope :pooled, -> { where(in_pool: true) }
  scope :ordered, -> { order(:position, :id) }

  before_save :rename_image
  after_commit :queue_spectra6_processing, if: :image_attached_recently?

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  private

  def rename_image
    return unless image.attached?
    return unless image.blob.persisted? == false || image.attachment&.new_record?

    blob = image.blob
    extension = File.extname(blob.filename.to_s)
    timestamp = Time.current.to_i
    slug = event.slug || event.title.parameterize
    blob.filename = "#{slug}-pool-#{position}-#{timestamp}#{extension}"
  end

  def image_attached_recently?
    image.attached? && image.blob.created_at > 10.seconds.ago
  end

  def queue_spectra6_processing
    return unless image.attached?

    Spectra6BannerJob.perform_later(image.blob.id)
  end
end
