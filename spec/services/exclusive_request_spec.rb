require 'rails_helper'

RSpec.describe ExclusiveRequest, :mail do
  let(:host) { create(:user, :can_create_events) }
  let!(:admin) { create(:user, :admin) }
  let(:event) { create(:event, user: host, start_time: 1.week.from_now) }

  def apply(actor, requested)
    event.exclusive_actor = actor
    event.request_exclusive = requested
    event.save!
    described_class.new(event, actor: actor).notify_review
  end

  it 'leaves a host request pending and emails admins' do
    expect { apply(host, true) }.to have_enqueued_mail(ExclusiveRequestMailer, :review_needed)

    expect(event.reload.exclusive_status).to eq('pending')
    expect(event.exclusive_requested_by).to eq(host)
  end

  it 'approves an admin request immediately' do
    expect { apply(admin, true) }.not_to have_enqueued_mail(ExclusiveRequestMailer, :review_needed)

    expect(event.reload.exclusive_status).to eq('approved')
    expect(event.exclusive_reviewed_by).to eq(admin)
  end

  it 'sends an approved event back to pending when the schedule changes' do
    apply(admin, true)

    expect do
      event.exclusive_actor = host
      event.request_exclusive = true
      event.update!(start_time: event.start_time + 1.day)
      described_class.new(event, actor: host).notify_review
    end.to have_enqueued_mail(ExclusiveRequestMailer, :review_needed)

    expect(event.reload.exclusive_status).to eq('pending')
  end

  it 'keeps an approved event approved when only the title changes' do
    apply(admin, true)

    event.exclusive_actor = host
    event.request_exclusive = true
    event.update!(title: 'Renamed')

    expect(event.reload.exclusive_status).to eq('approved')
  end

  it 'withdraws the request when the box is unchecked' do
    apply(host, true)
    apply(host, false)

    expect(event.reload.exclusive_status).to eq('none')
  end

  it 'emails hosts when an admin decides' do
    apply(host, true)

    expect do
      described_class.new(event, actor: admin).approve!(note: 'Looks good')
    end.to have_enqueued_mail(ExclusiveRequestMailer, :decision)

    expect(event.reload.exclusive_status).to eq('approved')
    expect(event.exclusive_review_note).to eq('Looks good')
  end
end
