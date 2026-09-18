require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    subject { build(:user) }

    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
  end

  describe 'associations' do
    it { is_expected.to have_many(:events).dependent(:destroy) }
    it { is_expected.to have_many(:event_hosts).dependent(:destroy) }
    it { is_expected.to have_many(:hosted_events).through(:event_hosts) }
  end

  describe 'devise modules' do
    it 'includes database_authenticatable' do
      expect(described_class.devise_modules).to include(:database_authenticatable)
    end

    it 'includes registerable' do
      expect(described_class.devise_modules).to include(:registerable)
    end

    it 'includes recoverable' do
      expect(described_class.devise_modules).to include(:recoverable)
    end

    it 'includes rememberable' do
      expect(described_class.devise_modules).to include(:rememberable)
    end

    it 'includes validatable' do
      expect(described_class.devise_modules).to include(:validatable)
    end

    it 'includes omniauthable' do
      expect(described_class.devise_modules).to include(:omniauthable)
    end
  end

  describe '#admin?' do
    context 'when user is an admin' do
      let(:user) { create(:user, :admin) }

      it 'returns true' do
        expect(user.admin?).to be true
      end
    end

    context 'when user is not an admin' do
      let(:user) { create(:user) }

      it 'returns false' do
        expect(user.admin?).to be false
      end
    end
  end

  describe '#can_create_events?' do
    context 'when user has can_create_events permission' do
      let(:user) { create(:user, :can_create_events) }

      it 'returns true' do
        expect(user.can_create_events?).to be true
      end
    end

    context 'when user does not have can_create_events permission' do
      let(:user) { create(:user) }

      it 'returns false' do
        expect(user.can_create_events?).to be false
      end
    end
  end

  describe '.from_omniauth' do
    let(:auth) do
      OmniAuth::AuthHash.new(
        provider: 'authentik',
        uid: '12345',
        info: {
          email: 'oauth_user@example.com',
          name: 'OAuth User'
        },
        credentials: {
          token: 'mock_access_token',
          expires_at: Time.now.to_i + 3600
        },
        extra: {
          raw_info: {
            sub: '12345',
            email: 'oauth_user@example.com',
            name: 'OAuth User',
            is_admin: false
          }
        }
      )
    end

    context 'when user does not exist' do
      it 'creates a new user' do
        expect do
          described_class.from_omniauth(auth)
        end.to change(described_class, :count).by(1)
      end

      it 'sets the provider and uid' do
        user = described_class.from_omniauth(auth)
        expect(user.provider).to eq('authentik')
        expect(user.uid).to eq('12345')
      end

      it 'sets the name from auth info' do
        user = described_class.from_omniauth(auth)
        expect(user.name).to eq('OAuth User')
      end
    end

    context 'when user already exists' do
      let!(:existing_user) { create(:user, :with_oauth, email: 'oauth_user@example.com', uid: '12345') }

      it 'does not create a new user' do
        expect do
          described_class.from_omniauth(auth)
        end.not_to change(described_class, :count)
      end

      it 'returns the existing user' do
        user = described_class.from_omniauth(auth)
        expect(user.id).to eq(existing_user.id)
      end
    end

    context 'role assignment (security-critical)' do
      it 'defaults to user role when is_admin is false' do
        user = described_class.from_omniauth(auth)
        expect(user.role).to eq('user')
        expect(user.admin?).to be false
      end

      it 'defaults to user role when is_admin claim is missing' do
        auth_without_admin = OmniAuth::AuthHash.new(
          provider: 'authentik',
          uid: '99999',
          info: { email: 'new_user@example.com', name: 'New User' },
          extra: { raw_info: { sub: '99999', email: 'new_user@example.com' } }
        )
        user = described_class.from_omniauth(auth_without_admin)
        expect(user.role).to eq('user')
        expect(user.admin?).to be false
      end

      it 'defaults to user role when extra is nil' do
        auth_no_extra = OmniAuth::AuthHash.new(
          provider: 'authentik',
          uid: '88888',
          info: { email: 'noextra@example.com', name: 'No Extra' }
        )
        user = described_class.from_omniauth(auth_no_extra)
        expect(user.role).to eq('user')
        expect(user.admin?).to be false
      end

      it 'defaults to user role when raw_info is nil' do
        auth_no_raw = OmniAuth::AuthHash.new(
          provider: 'authentik',
          uid: '77777',
          info: { email: 'noraw@example.com', name: 'No Raw' },
          extra: {}
        )
        user = described_class.from_omniauth(auth_no_raw)
        expect(user.role).to eq('user')
        expect(user.admin?).to be false
      end

      it 'sets admin role only when is_admin is boolean true' do
        auth_admin = OmniAuth::AuthHash.new(
          provider: 'authentik',
          uid: '66666',
          info: { email: 'admin@example.com', name: 'Admin User' },
          extra: { raw_info: { is_admin: true } }
        )
        user = described_class.from_omniauth(auth_admin)
        expect(user.role).to eq('admin')
        expect(user.admin?).to be true
      end

      it 'sets admin role when is_admin is string "true"' do
        auth_admin_string = OmniAuth::AuthHash.new(
          provider: 'authentik',
          uid: '55555',
          info: { email: 'admin_str@example.com', name: 'Admin String' },
          extra: { raw_info: { is_admin: 'true' } }
        )
        user = described_class.from_omniauth(auth_admin_string)
        expect(user.role).to eq('admin')
        expect(user.admin?).to be true
      end

      it 'does NOT set admin role for other truthy values' do
        # Security: only explicit true/\"true\" should grant admin
        auth_truthy = OmniAuth::AuthHash.new(
          provider: 'authentik',
          uid: '44444',
          info: { email: 'truthy@example.com', name: 'Truthy User' },
          extra: { raw_info: { is_admin: 1 } }
        )
        user = described_class.from_omniauth(auth_truthy)
        expect(user.role).to eq('user')
        expect(user.admin?).to be false
      end

      it 'does NOT set admin role for string "yes"' do
        auth_yes = OmniAuth::AuthHash.new(
          provider: 'authentik',
          uid: '33333',
          info: { email: 'yes@example.com', name: 'Yes User' },
          extra: { raw_info: { is_admin: 'yes' } }
        )
        user = described_class.from_omniauth(auth_yes)
        expect(user.role).to eq('user')
        expect(user.admin?).to be false
      end
    end

    context 'can_create_events assignment' do
      it 'sets can_create_events to true when is_event_host is boolean true' do
        auth_host = OmniAuth::AuthHash.new(
          provider: 'authentik',
          uid: '77777',
          info: { email: 'host@example.com', name: 'Event Host' },
          extra: { raw_info: { is_event_host: true } }
        )
        user = described_class.from_omniauth(auth_host)
        expect(user.role).to eq('user')
        expect(user.can_create_events).to be true
      end

      it 'sets can_create_events to true when is_event_host is string "true"' do
        auth_host = OmniAuth::AuthHash.new(
          provider: 'authentik',
          uid: '88888',
          info: { email: 'host_str@example.com', name: 'Event Host String' },
          extra: { raw_info: { is_event_host: 'true' } }
        )
        user = described_class.from_omniauth(auth_host)
        expect(user.can_create_events).to be true
      end

      it 'sets can_create_events to false when is_event_host is missing' do
        auth_no_host = OmniAuth::AuthHash.new(
          provider: 'authentik',
          uid: '99999',
          info: { email: 'nohost@example.com', name: 'No Host' },
          extra: { raw_info: {} }
        )
        user = described_class.from_omniauth(auth_no_host)
        expect(user.can_create_events).to be false
      end

      it 'sets can_create_events to true for admins regardless of is_event_host' do
        auth_admin = OmniAuth::AuthHash.new(
          provider: 'authentik',
          uid: '11111',
          info: { email: 'admin_nohost@example.com', name: 'Admin No Host' },
          extra: { raw_info: { is_admin: true, is_event_host: false } }
        )
        user = described_class.from_omniauth(auth_admin)
        expect(user.role).to eq('admin')
        expect(user.can_create_events).to be true
      end

      it 'does NOT set can_create_events for other truthy values' do
        auth_truthy = OmniAuth::AuthHash.new(
          provider: 'authentik',
          uid: '22222',
          info: { email: 'truthy_host@example.com', name: 'Truthy Host' },
          extra: { raw_info: { is_event_host: 1 } }
        )
        user = described_class.from_omniauth(auth_truthy)
        expect(user.can_create_events).to be false
      end
    end
  end

  describe 'default role' do
    it 'sets role to user by default' do
      user = create(:user)
      expect(user.role).to eq('user')
    end
  end

  describe 'email_reminders_enabled' do
    it 'defaults to true' do
      user = create(:user)
      expect(user.email_reminders_enabled).to be true
    end

    it 'can be set to false' do
      user = create(:user, email_reminders_enabled: false)
      expect(user.email_reminders_enabled).to be false
    end

    it 'has trait for disabled' do
      user = create(:user, :email_reminders_disabled)
      expect(user.email_reminders_enabled).to be false
    end
  end

  describe 'deletion' do
    # event_journals.user_id was NOT NULL, which made the association's
    # dependent: :nullify raise and blocked deleting anyone who had ever
    # edited an event. Creators are still held back by the events.user_id
    # foreign key, which is a separate question.
    let(:editor) { create(:user) }
    let(:someone_elses_event) { create(:event) }

    it 'succeeds for a user with journal entries' do
      create(:event_journal, event: someone_elses_event, user: editor)

      expect { editor.destroy! }.to change(User, :count).by(-1)
    end

    it 'leaves the journal entries behind' do
      entry = create(:event_journal, event: someone_elses_event, user: editor)

      editor.destroy!

      expect(entry.reload.user_id).to be_nil
    end
  end

  describe 'factory' do
    it 'creates a valid user' do
      user = build(:user)
      expect(user).to be_valid
    end

    it 'creates a valid admin user' do
      admin = build(:user, :admin)
      expect(admin).to be_valid
      expect(admin.admin?).to be true
    end

    it 'creates a valid oauth user' do
      oauth_user = build(:user, :with_oauth)
      expect(oauth_user).to be_valid
      expect(oauth_user.provider).to eq('authentik')
      expect(oauth_user.uid).to be_present
    end
  end
end
