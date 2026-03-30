require 'sidekiq/web'
require 'sidekiq-scheduler/web'

Rails.application.routes.draw do
  # Health check endpoints (before authentication)
  # Multiple aliases for compatibility with different monitoring systems
  get 'health', to: 'health#show'
  get 'up', to: 'health#show' # Rails 7.1+ convention
  get 'health/live', to: 'health#live'
  get 'health/liveness', to: 'health#live' # Kubernetes-style alias
  get 'health/ready', to: 'health#ready'
  get 'health/readiness', to: 'health#ready' # Kubernetes-style alias

  get 'calendar/index'
  get 'event_occurrences/show'
  get 'event_occurrences/edit'
  get 'event_occurrences/update'
  get 'event_occurrences/destroy'
  get 'event_occurrences/postpone'
  get 'event_occurrences/cancel'
  get 'event_occurrences/reactivate'
  # Devise routes with OmniAuth
  # Users created via Authentik OAuth only (no signup)
  # Skip all registration routes and manually add only edit/update/destroy
  devise_for :users, controllers: {
    omniauth_callbacks: 'omniauth_callbacks'
  }, skip: [:registrations]

  # Manually add only the registration routes we need (no new/create for sign up)
  devise_scope :user do
    get 'users/edit', to: 'devise/registrations#edit', as: :edit_user_registration
    patch 'users', to: 'devise/registrations#update', as: :user_registration
    put 'users', to: 'devise/registrations#update'
    delete 'users', to: 'devise/registrations#destroy'
  end

  # Sidekiq Web UI (admin only)
  authenticate :user, ->(user) { user.admin? } do
    mount Sidekiq::Web => '/sidekiq'
  end

  # letter_opener_web: dev is open locally; staging requires admin (same host may be untrusted)
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: '/letter_opener'
  elsif Rails.env.staging?
    authenticate :user, ->(user) { user.admin? } do
      mount LetterOpenerWeb::Engine, at: '/letter_opener'
    end
  end

  # Root path
  root 'home#index'

  # Dashboard for logged-in users
  get 'dashboard', to: 'dashboard#index', as: 'dashboard'

  # Events routes
  get 'events/rss', to: 'events#rss', as: 'events_rss', defaults: { format: 'rss' }
  get 'events/eink', to: 'events#eink', as: 'events_eink', defaults: { format: 'json' }
  resources :events do
    member do
      post :postpone
      post :cancel
      post :reactivate
      post :generate_ai_reminder
      get :embed
      get :rss, action: :event_rss, as: :rss, defaults: { format: 'rss' }
    end

    # Host management
    resources :event_hosts, only: %i[create destroy]
  end

  # Event Occurrences routes
  resources :event_occurrences, only: %i[show edit update destroy], path: 'occurrences' do
    member do
      post :postpone
      post :cancel
      post :relocate
      post :reactivate
      post :post_slack_reminder
      post :post_social_reminder
      post :generate_ai_reminder
      post :send_host_reminder
      get :ical, defaults: { format: 'ics' }
    end
  end

  # Site-wide public iCal feed
  get 'calendar.ics', to: 'calendar#ical', as: 'calendar_ical'

  # Calendar view
  get 'calendar', to: 'calendar#index', as: 'calendar'
  get 'calendar/embed', to: 'calendar#embed', as: 'calendar_embed'

  # Public iCal feed
  get 'events/:token/ical', to: 'events#ical', as: 'event_ical'

  # Users management (admin only)
  resources :users, only: %i[index show edit update destroy] do
    member do
      post :make_admin
    end
  end

  # Site configuration (admin only, singleton)
  resource :site_config, only: %i[edit update]

  # Reminder postings (admin can see all, hosts can delete their own)
  resources :reminder_postings, only: %i[index destroy]

  # Activity journal (admin only)
  resources :event_journals, only: [:index]

  # Location information page (public)
  get 'location', to: 'site_configs#location', as: 'location_info'

  # Locations management (admin only)
  resources :locations, except: %i[show]

  # SEO: Sitemap and robots.txt
  get 'sitemap.xml', to: 'sitemap#index', as: 'sitemap', defaults: { format: 'xml' }
  get 'robots.txt', to: 'robots#show', as: 'robots', defaults: { format: 'text' }
end
