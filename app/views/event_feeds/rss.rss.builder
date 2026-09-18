xml.instruct! :xml, version: "1.0"
xml.rss version: "2.0", "xmlns:atom" => "http://www.w3.org/2005/Atom" do
  xml.channel do
    # Channel info
    xml.title "#{@site_config&.organization_name || 'EventManager'} Events"
    xml.description "Upcoming events at #{@site_config&.organization_name || 'our hackerspace'}"
    xml.link events_url
    xml.language "en-us"
    xml.lastBuildDate Time.current.rfc2822
    xml.tag! "atom:link", href: events_rss_url, rel: "self", type: "application/rss+xml"

    # Channel image
    if @site_config&.banner_image&.attached?
      xml.image do
        xml.url url_for(@site_config.banner_image)
        xml.title @site_config&.organization_name || 'EventManager'
        xml.link root_url
      end
    end

    # Event items
    @events.each do |event|
      xml.item do
        xml.title event.title
        xml.link event_url(event)
        xml.guid event_url(event), isPermaLink: "true"
        xml.pubDate event.created_at.rfc2822

        # Build description
        desc_parts = []
        next_occurrence = @next_occurrence_by_event[event.id]
        desc_parts << "<p><strong>Next:</strong> #{next_occurrence.occurs_at.strftime('%B %d, %Y at %I:%M %p')}</p>" if next_occurrence
        desc_parts << "<p><strong>Location:</strong> #{event.location.name}</p>" if event.location.present?
        desc_parts << "<p>#{h(event.description.truncate(500))}</p>" if event.description.present?
        desc_parts << "<p><a href=\"#{event.more_info_url}\">More information</a></p>" if event.more_info_url.present?
        xml.description desc_parts.join

        # Banner image enclosure
        if event.banner_image.attached?
          xml.enclosure url: url_for(event.banner_image),
                        type: event.banner_image.content_type,
                        length: event.banner_image.byte_size
        end

        xml.category event.recurrence_type.titleize
        xml.category event.open_to == 'public' ? 'Open to All' : 'Members Only'
      end
    end
  end
end
