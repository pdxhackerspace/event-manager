class EventImagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_event
  before_action :set_event_image, only: %i[update destroy]
  before_action :authorize_event_image, only: %i[create update destroy reorder reassign]

  def create
    files = Array(params[:images]).compact_blank
    if files.empty?
      redirect_to edit_event_path(@event, anchor: 'image-pool'), alert: 'Please select at least one image to upload.'
      return
    end

    next_position = @event.event_images.pooled.maximum(:position).to_i + 1
    created_count = 0

    files.each_with_index do |file, index|
      event_image = @event.event_images.create!(position: next_position + index, in_pool: true)
      event_image.image.attach(file)
      created_count += 1
    end

    if @event.fixed_event_image_id.blank?
      first_image = @event.event_images.pooled.ordered.first
      @event.update!(fixed_event_image_id: first_image.id) if first_image
    end

    log_pool_change('images_added', { 'count' => created_count })
    redirect_to edit_event_path(@event, anchor: 'image-pool'), notice: "#{created_count} #{'image'.pluralize(created_count)} added to the pool."
  end

  def update
    if @event_image.update(event_image_params)
      log_pool_change('image_updated', { 'event_image_id' => @event_image.id, 'in_pool' => @event_image.in_pool? })
      redirect_to edit_event_path(@event, anchor: 'image-pool'), notice: 'Image updated.'
    else
      redirect_to edit_event_path(@event, anchor: 'image-pool'), alert: @event_image.errors.full_messages.to_sentence
    end
  end

  def destroy
    if @event.fixed_event_image_id == @event_image.id
      replacement = @event.event_images.pooled.ordered.where.not(id: @event_image.id).first
      @event.update!(fixed_event_image_id: replacement&.id)
    end

    EventOccurrence.unscoped.where(event_image_id: @event_image.id).find_each do |occurrence|
      occurrence.update!(event_image_id: nil, custom_event_image: false)
    end
    filename = @event_image.image.filename.to_s if @event_image.image.attached?
    @event_image.destroy!

    log_pool_change('image_removed', { 'filename' => filename })
    redirect_to edit_event_path(@event, anchor: 'image-pool'), notice: 'Image removed from the pool.'
  end

  def reorder
    ordered_ids = Array(params[:ordered_ids]).map(&:to_i)
    pooled_images = @event.event_images.pooled.where(id: ordered_ids).index_by(&:id)

    ordered_ids.each_with_index do |image_id, index|
      event_image = pooled_images[image_id]
      event_image&.update!(position: index)
    end

    log_pool_change('images_reordered', { 'ordered_ids' => ordered_ids })
    head :ok
  end

  def reassign
    count = EventImageReassigner.new(@event).reassign!
    log_pool_change('images_reassigned', { 'count' => count, 'mode' => @event.image_selection_mode })

    if count.zero?
      redirect_to edit_event_path(@event, anchor: 'image-pool'),
                  alert: 'No occurrences were reassigned. Add images to the pool first.'
    else
      redirect_to edit_event_path(@event, anchor: 'image-pool'),
                  notice: "Reassigned images for #{count} #{'occurrence'.pluralize(count)}."
    end
  end

  private

  def set_event
    @event = Event.friendly_find(params[:event_id])
    authorize @event, :update?
  end

  def set_event_image
    @event_image = @event.event_images.find(params.expect(:id))
  end

  def authorize_event_image
    authorize @event_image || EventImage.new(event: @event)
  end

  def event_image_params
    params.expect(event_image: [:in_pool])
  end

  def log_pool_change(action, data)
    return unless current_user

    @event.current_user_for_journal = current_user
    EventJournal.log_event_change(@event, current_user, action, data)
  end
end
