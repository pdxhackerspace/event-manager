module EventImagesHelper
  # Banner originals routinely run 1-3 MB. Any view rendering a preview smaller
  # than the full banner should use these instead of image_tag so a scaled
  # variant is served and loading is deferred until the image scrolls into view.
  # Reserve the original for full-width hero banners.
  def event_image_thumbnail_tag(attachment, **)
    event_image_variant_tag(attachment, :thumb, **)
  end

  def event_image_card_tag(attachment, **)
    event_image_variant_tag(attachment, :card, **)
  end

  def event_image_variant_tag(attachment, variant_name, **options)
    return nil unless attachment&.attached?

    image_tag event_image_variant(attachment, variant_name), **options.reverse_merge(loading: 'lazy')
  end

  # Blobs ImageMagick cannot transform (SVG, corrupt uploads) fall back to the
  # original rather than raising mid-render.
  def event_image_variant(attachment, variant_name)
    return attachment unless attachment.variable?

    attachment.variant(variant_name)
  end
end
