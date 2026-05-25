class LocationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_location, only: %i[edit update destroy]
  before_action :authorize_admin

  def index
    @locations = Location.alphabetical
  end

  def new
    @location = Location.new
  end

  def edit; end

  def create
    @location = Location.new(location_params)

    if @location.save
      redirect_to locations_path, notice: 'Location was successfully created.'
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @location.update(location_params)
      redirect_to locations_path, notice: 'Location was successfully updated.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @location.destroy
    redirect_to locations_url, notice: 'Location was successfully deleted.'
  end

  private

  def set_location
    @location = Location.find(params.expect(:id))
  end

  def authorize_admin
    redirect_to root_path, alert: 'Only admins can manage locations.' unless current_user.admin?
  end

  def location_params
    params.expect(location: %i[name description])
  end
end
