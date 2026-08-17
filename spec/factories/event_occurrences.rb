FactoryBot.define do
  factory :event_occurrence do
    association :event
    occurs_at { 1.week.from_now }
    status { "active" }

    trait :with_custom_description do
      custom_description { Faker::Lorem.paragraph }
    end

    trait :with_duration_override do
      duration_override { 180 }
    end

    trait :postponed do
      status { "postponed" }
      postponed_until { 2.weeks.from_now }
      cancellation_reason { "Speaker unavailable" }
    end

    trait :cancelled do
      status { "cancelled" }
      cancellation_reason { "Weather conditions" }
    end

    trait :past do
      occurs_at { 1.week.ago }
    end

    trait :with_banner do
      after(:create) do |occurrence|
        event_image = occurrence.event.event_images.create!(position: 99, in_pool: false)
        event_image.image.attach(
          io: StringIO.new('fake image content'),
          filename: 'occurrence_banner.jpg',
          content_type: 'image/jpeg'
        )
        occurrence.update!(event_image: event_image, custom_event_image: true)
      end
    end
  end
end
