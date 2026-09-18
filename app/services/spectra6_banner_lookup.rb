# Resolves the pre-rendered Spectra6 variants for a batch of Active Storage
# attachments in a single query.
#
# The variants are uploaded by Spectra6BannerJob under a derived key rather than
# as an Active Storage variant record, so they cannot be eager-loaded with the
# rest of the feed. Looking them up one at a time costs a query per serialized
# row; this collects the keys up front instead.
class Spectra6BannerLookup
  def self.derived_key(blob)
    File.join(
      File.dirname(blob.key),
      Spectra6BannerJob::OUTPUT_SUBDIR,
      "#{File.basename(blob.key, '.*')}.png"
    )
  end

  def initialize(attachments)
    keys = Array(attachments).filter_map { |attachment| key_for(attachment) }.uniq
    @blobs_by_key = keys.empty? ? {} : ActiveStorage::Blob.where(key: keys).index_by(&:key)
  end

  def blob_for(attachment)
    key = key_for(attachment)
    key && @blobs_by_key[key]
  end

  private

  def key_for(attachment)
    return nil unless attachment&.attached?

    self.class.derived_key(attachment.blob)
  end
end
