FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}-#{SecureRandom.hex(4)}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
    sequence(:name) { |n| "User #{n}" }
    sequence(:username) { |n| "user#{n}" }
    role { "user" }
    can_create_events { false }

    trait :admin do
      role { "admin" }
      sequence(:name) { |n| "Admin #{n}" }
    end

    trait :can_create_events do
      can_create_events { true }
    end

    trait :with_oauth do
      provider { "authentik" }
      sequence(:uid) { |n| "authentik-#{n}" }
    end

    trait :email_reminders_disabled do
      email_reminders_enabled { false }
    end
  end
end
