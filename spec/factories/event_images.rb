FactoryBot.define do
  factory :event_image do
    association :event
    sequence(:position) { |n| n }
    in_pool { true }

    trait :with_image do
      after(:create) do |event_image|
        event_image.image.attach(
          io: StringIO.new('fake image content'),
          filename: 'pool-image.jpg',
          content_type: 'image/jpeg'
        )
      end
    end

    trait :occurrence_only do
      in_pool { false }
    end
  end
end
