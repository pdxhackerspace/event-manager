# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

class SocialService # rubocop:disable Metrics/ClassLength
  BLUESKY_MAX_IMAGE_SIZE = 950_000 # ~950KB to stay under 976.56KB limit

  class << self
    include Rails.application.routes.url_helpers

    def post_instagram(message, image_url: nil)
      # Try database credential first (with auto-refresh), then fall back to ENV
      token = SocialCredential.get_token('instagram') || ENV.fetch('INSTAGRAM_ACCESS_TOKEN', nil)
      account_id = ENV.fetch('INSTAGRAM_ACCOUNT_ID', nil)

      if token.blank? || account_id.blank?
        Rails.logger.info 'SocialService: Instagram not configured (missing token or INSTAGRAM_ACCOUNT_ID)'
        return { success: false, error: 'Not configured' }
      end

      # Instagram requires an image for feed posts
      if image_url.blank?
        Rails.logger.info 'SocialService: Instagram post skipped - image required for feed posts'
        return { success: false, error: 'Image required' }
      end

      # Step 1: Create media container
      container_id = create_instagram_container(account_id, token, image_url, message)
      return { success: false, error: 'Container creation failed' } unless container_id

      # Step 2: Wait for container to be ready (Instagram processes the image)
      unless instagram_container_ready?(container_id, token)
        Rails.logger.error 'SocialService: Instagram container processing timed out'
        return { success: false, error: 'Container processing timeout' }
      end

      # Step 3: Publish the container
      publish_instagram_container(account_id, token, container_id)
    rescue StandardError => e
      Rails.logger.error "SocialService: Instagram error - #{e.message}"
      { success: false, error: e.message }
    end

    def create_instagram_container(account_id, token, image_url, caption)
      uri = URI("https://graph.facebook.com/v21.0/#{account_id}/media")
      request = Net::HTTP::Post.new(uri)
      request.set_form_data({
                              image_url: image_url,
                              caption: caption,
                              access_token: token
                            })

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }

      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        Rails.logger.info "SocialService: Instagram container created: #{data['id']}"
        data['id']
      else
        Rails.logger.error "SocialService: Failed to create Instagram container (#{response.code}) #{response.body}"
        nil
      end
    end

    def instagram_container_ready?(container_id, token, max_attempts: 10)
      max_attempts.times do |attempt|
        uri = URI("https://graph.facebook.com/v21.0/#{container_id}?fields=status_code&access_token=#{token}")
        response = Net::HTTP.get_response(uri)

        if response.is_a?(Net::HTTPSuccess)
          data = JSON.parse(response.body)
          status = data['status_code']

          case status
          when 'FINISHED'
            Rails.logger.info 'SocialService: Instagram container ready'
            return true
          when 'ERROR'
            Rails.logger.error "SocialService: Instagram container error: #{data}"
            return false
          when 'IN_PROGRESS'
            Rails.logger.info "SocialService: Instagram container processing (attempt #{attempt + 1}/#{max_attempts})"
            sleep 2
          else
            Rails.logger.info "SocialService: Instagram container status: #{status} (attempt #{attempt + 1}/#{max_attempts})"
            sleep 2
          end
        else
          Rails.logger.error "SocialService: Failed to check Instagram container status (#{response.code})"
          return false
        end
      end
      false
    end

    def publish_instagram_container(account_id, token, container_id)
      uri = URI("https://graph.facebook.com/v21.0/#{account_id}/media_publish")
      request = Net::HTTP::Post.new(uri)
      request.set_form_data({
                              creation_id: container_id,
                              access_token: token
                            })

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }

      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        post_id = data['id']
        Rails.logger.info "SocialService: Posted to Instagram: #{post_id}"
        { success: true, post_id: post_id }
      else
        Rails.logger.error "SocialService: Failed to publish Instagram post (#{response.code}) #{response.body}"
        { success: false, error: "HTTP #{response.code}" }
      end
    end

    def post_bluesky(message, image_url: nil, image_alt: 'Event banner', link_url: nil, link_text: nil)
      handle = ENV.fetch('BLUESKY_HANDLE', nil)
      app_password = ENV.fetch('BLUESKY_APP_PASSWORD', nil)

      if handle.blank? || app_password.blank?
        Rails.logger.info 'SocialService: Bluesky not configured (missing BLUESKY_HANDLE or BLUESKY_APP_PASSWORD)'
        return { success: false, error: 'Not configured' }
      end

      Rails.logger.info "SocialService: Bluesky post starting for handle #{handle}"

      session = create_bluesky_session(handle, app_password)
      return { success: false, error: 'Session creation failed' } unless session

      access_token = session['accessJwt']
      did = session['did']
      Rails.logger.info "SocialService: Bluesky session created for DID #{did}"

      image_blob = fetch_bluesky_image_blob(access_token, image_url)
      record = build_bluesky_record(message, image_blob, image_alt, link_url: link_url, link_text: link_text)

      uri = URI('https://bsky.social/xrpc/com.atproto.repo.createRecord')
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{access_token}"
      request['Content-Type'] = 'application/json'
      request.body = { repo: did, collection: 'app.bsky.feed.post', record: record }.to_json

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }

      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        post_uri = data['uri']
        # Build web URL from AT URI: at://did:plc:xxx/app.bsky.feed.post/rkey -> https://bsky.app/profile/handle/post/rkey
        rkey = post_uri.split('/').last
        post_url = "https://bsky.app/profile/#{handle}/post/#{rkey}"
        Rails.logger.info "SocialService: Posted reminder to Bluesky - #{post_url}"
        { success: true, post_uid: post_uri, post_url: post_url }
      else
        Rails.logger.error "SocialService: Failed to post to Bluesky (#{response.code}) #{response.body}"
        { success: false, error: "HTTP #{response.code}" }
      end
    rescue StandardError => e
      Rails.logger.error "SocialService: Bluesky error - #{e.message}"
      { success: false, error: e.message }
    end

    def delete_bluesky_post(post_uri)
      handle = ENV.fetch('BLUESKY_HANDLE', nil)
      app_password = ENV.fetch('BLUESKY_APP_PASSWORD', nil)

      return { success: false, error: 'Not configured' } if handle.blank? || app_password.blank?

      session = create_bluesky_session(handle, app_password)
      return { success: false, error: 'Session creation failed' } unless session

      access_token = session['accessJwt']
      did = session['did']

      # Extract rkey from post URI (at://did:plc:xxx/app.bsky.feed.post/rkey)
      rkey = post_uri.split('/').last

      uri = URI('https://bsky.social/xrpc/com.atproto.repo.deleteRecord')
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{access_token}"
      request['Content-Type'] = 'application/json'
      request.body = { repo: did, collection: 'app.bsky.feed.post', rkey: rkey }.to_json

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }

      if response.is_a?(Net::HTTPSuccess)
        Rails.logger.info "SocialService: Deleted Bluesky post #{post_uri}"
        { success: true }
      else
        Rails.logger.error "SocialService: Failed to delete Bluesky post (#{response.code}) #{response.body}"
        { success: false, error: "HTTP #{response.code}" }
      end
    rescue StandardError => e
      Rails.logger.error "SocialService: Bluesky delete error - #{e.message}"
      { success: false, error: e.message }
    end

    def fetch_bluesky_image_blob(access_token, image_url)
      return nil if image_url.blank?

      Rails.logger.info "SocialService: Bluesky image URL provided: #{image_url}"
      blob = upload_bluesky_image(access_token, image_url)
      if blob
        Rails.logger.info "SocialService: Bluesky image blob obtained successfully"
      else
        Rails.logger.warn "SocialService: Bluesky image upload returned nil, posting without image"
      end
      blob
    end

    def build_bluesky_record(message, image_blob, image_alt, link_url: nil, link_text: nil)
      record = { '$type': 'app.bsky.feed.post', createdAt: Time.current.iso8601, text: message }

      # Add link facet if provided
      if link_url.present? && link_text.present?
        # Find where the link text appears in the message
        link_start = message.index(link_text)
        if link_start
          link_end = link_start + link_text.bytesize
          record[:facets] = [
            {
              index: { byteStart: link_start, byteEnd: link_end },
              features: [{ '$type': 'app.bsky.richtext.facet#link', uri: link_url }]
            }
          ]
          Rails.logger.info "SocialService: Added link facet for '#{link_text}' -> #{link_url}"
        end
      end

      if image_blob
        Rails.logger.info "SocialService: Adding image embed to Bluesky post"
        record[:embed] = {
          '$type': 'app.bsky.embed.images',
          images: [{ alt: image_alt, image: image_blob }]
        }
      end

      record
    end

    # Post reminder with separate short (Bluesky) and long (Instagram) messages
    # short_parts and long_parts should be { text: "...", link_url: "...", link_text: "..." }
    def post_occurrence_reminder(occurrence, short_parts:, long_parts:, reminder_type: nil)
      image_url = banner_url_for(occurrence)
      image_alt = occurrence.event.title

      Rails.logger.info "SocialService: Posting occurrence reminder for '#{occurrence.event.title}'"
      Rails.logger.info "SocialService: Banner image URL: #{image_url || 'none'}"

      # Bluesky gets short message with facet link
      bluesky_message = "#{short_parts[:text]} #{short_parts[:link_text]}"
      bluesky_result = post_bluesky(
        bluesky_message,
        image_url: image_url,
        image_alt: image_alt,
        link_url: short_parts[:link_url],
        link_text: short_parts[:link_text]
      )

      # Record Bluesky posting if successful
      if bluesky_result[:success]
        record_posting(occurrence, bluesky_message, platform: 'bluesky',
                                                    reminder_type: reminder_type,
                                                    post_uid: bluesky_result[:post_uid], post_url: bluesky_result[:post_url])
      end

      # Instagram gets long message with full URL
      instagram_message = "#{long_parts[:text]}\n\n#{long_parts[:link_url]}"
      instagram_result = post_instagram(instagram_message, image_url: image_url)

      # Record Instagram posting if successful
      if instagram_result[:success]
        record_posting(occurrence, instagram_message, platform: 'instagram',
                                                      reminder_type: reminder_type, post_uid: instagram_result[:post_id])
      end

      instagram_result[:success] || bluesky_result[:success]
    end

    private

    # rubocop:disable Metrics/ParameterLists
    def record_posting(occurrence, message, platform:, reminder_type: nil, post_uid: nil, post_url: nil)
      # rubocop:enable Metrics/ParameterLists
      ReminderPosting.create!(
        event: occurrence.event,
        event_occurrence: occurrence,
        platform: platform,
        message: message,
        reminder_type: reminder_type,
        post_uid: post_uid,
        post_url: post_url,
        posted_at: Time.current
      )
    rescue StandardError => e
      Rails.logger.error "SocialService: Failed to record #{platform} posting: #{e.message}"
    end

    def create_bluesky_session(handle, app_password)
      uri = URI('https://bsky.social/xrpc/com.atproto.server.createSession')
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = {
        identifier: handle,
        password: app_password
      }.to_json

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        Rails.logger.error "SocialService: Failed to create Bluesky session (#{response.code}) #{response.body}"
        nil
      end
    rescue StandardError => e
      Rails.logger.error "SocialService: Bluesky session error - #{e.message}"
      nil
    end

    def upload_bluesky_image(token, image_url)
      Rails.logger.info "SocialService: Fetching image from #{image_url}"

      # Fetch the image from the URL, following redirects
      image_data, content_type = fetch_image_with_redirects(image_url)

      unless image_data
        Rails.logger.error "SocialService: Failed to fetch image from #{image_url}"
        return nil
      end

      Rails.logger.info "SocialService: Fetched image - size: #{image_data.bytesize} bytes, content-type: #{content_type}"

      # Resize if too large for Bluesky
      if image_data.bytesize > BLUESKY_MAX_IMAGE_SIZE
        Rails.logger.info "SocialService: Image too large, resizing..."
        image_data, content_type = resize_image_for_bluesky(image_data)
        return nil unless image_data

        Rails.logger.info "SocialService: Resized image - size: #{image_data.bytesize} bytes, content-type: #{content_type}"
      end

      # Upload to Bluesky
      uri = URI('https://bsky.social/xrpc/com.atproto.repo.uploadBlob')
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{token}"
      request['Content-Type'] = content_type
      request.body = image_data

      Rails.logger.info "SocialService: Uploading image to Bluesky..."
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }

      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        Rails.logger.info "SocialService: Uploaded image to Bluesky successfully"
        Rails.logger.debug { "SocialService: Bluesky blob response: #{data.inspect}" }
        data['blob']
      else
        Rails.logger.error "SocialService: Failed to upload image to Bluesky (#{response.code}) #{response.body}"
        nil
      end
    rescue StandardError => e
      Rails.logger.error "SocialService: Bluesky image upload error - #{e.class}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      nil
    end

    def resize_image_for_bluesky(image_data)
      # Use ImageMagick/Vips via ActiveStorage to resize the image
      tempfile = Tempfile.new(['bluesky_image', '.jpg'])
      tempfile.binmode
      tempfile.write(image_data)
      tempfile.rewind

      # Use MiniMagick to resize and compress
      image = MiniMagick::Image.open(tempfile.path)
      image.resize '1200x1200>' # Max 1200px on longest side
      image.format 'jpeg'
      image.quality 85

      # If still too large, reduce quality further
      while image.size > BLUESKY_MAX_IMAGE_SIZE && image.data['quality'].to_i > 50
        current_quality = image.data['quality']&.to_i || 85
        image.quality(current_quality - 10)
      end

      result_data = File.binread(image.path)
      Rails.logger.info "SocialService: Resized to #{result_data.bytesize} bytes"

      [result_data, 'image/jpeg']
    rescue StandardError => e
      Rails.logger.error "SocialService: Failed to resize image: #{e.class}: #{e.message}"
      nil
    ensure
      tempfile&.close
      tempfile&.unlink
    end

    def fetch_image_with_redirects(url, redirect_limit = 5)
      return nil if redirect_limit.zero?

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Get.new(uri)
      response = http.request(request)

      case response
      when Net::HTTPSuccess
        content_type = response['Content-Type'] || 'image/jpeg'
        [response.body, content_type]
      when Net::HTTPRedirection
        new_location = response['Location']
        Rails.logger.info "SocialService: Following redirect to #{new_location}"
        fetch_image_with_redirects(new_location, redirect_limit - 1)
      else
        Rails.logger.error "SocialService: Failed to fetch image (#{response.code}) from #{url}"
        nil
      end
    rescue StandardError => e
      Rails.logger.error "SocialService: Error fetching image: #{e.class}: #{e.message}"
      nil
    end

    def banner_url_for(occurrence)
      host = ENV.fetch('RAILS_HOST', ENV.fetch('HOST', 'localhost:3000'))
      protocol = ENV.fetch('RAILS_PROTOCOL', 'http')

      banner = occurrence.banner
      if banner.attached?
        url = rails_blob_url(banner, host: host, protocol: protocol)
        Rails.logger.info "SocialService: Using banner image: #{url}"
        url
      else
        Rails.logger.info 'SocialService: No banner image attached to occurrence or event'
        nil
      end
    end
  end
end
