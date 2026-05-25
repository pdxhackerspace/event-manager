class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user, only: %i[show edit update destroy make_admin]
  before_action :authorize_user, only: %i[index show edit update destroy make_admin]

  def index
    authorize User
    @users = User.order(created_at: :desc)
  end

  def show; end

  def edit; end

  def update
    if @user.update(user_params)
      redirect_to @user, notice: 'User was successfully updated.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @user.destroy
    redirect_to users_url, notice: 'User was successfully deleted.'
  end

  def make_admin
    authorize @user, :make_admin?
    @user.update(role: 'admin')
    redirect_to @user, notice: 'User is now an admin.'
  end

  private

  def set_user
    @user = User.find(params.expect(:id))
  end

  def authorize_user
    authorize @user || User
  end

  def user_params
    permitted = params.expect(user: %i[name email])

    # Only admins can change roles, and only to valid values
    if current_user.admin?
      role_valid = %w[user admin].include?(params[:user][:role])
      permitted[:role] = params[:user][:role] if params[:user][:role].present? && role_valid

      # Only admins can set can_create_events flag
      permitted[:can_create_events] = params[:user][:can_create_events] if params[:user].key?(:can_create_events)
    end

    permitted
  end
end
