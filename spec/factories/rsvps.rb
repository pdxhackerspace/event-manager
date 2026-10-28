FactoryBot.define do
  factory :rsvp do
    event_occurrence
    sequence(:name) { |n| "Guest #{n}" }
    sequence(:email) { |n| "guest#{n}@example.com" }
    status { 'confirmed' }
    confirmed_at { Time.current }

    trait :pending do
      status { 'pending' }
      confirmed_at { nil }
    end

    trait :waitlisted do
      status { 'waitlisted' }
      confirmed_at { nil }
      waitlisted_at { Time.current }
    end
  end
end
