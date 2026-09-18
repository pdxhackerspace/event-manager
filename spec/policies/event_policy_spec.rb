require 'rails_helper'

RSpec.describe EventPolicy, type: :policy do
  let(:creator) { create(:user, role: 'admin') }
  let(:event) { create(:event, user: creator, visibility: 'public') }

  describe 'permissions' do
    context 'for a guest user' do
      let(:policy) { described_class.new(nil, event) }

      context 'with a public event' do
        it 'allows viewing' do
          expect(policy.show?).to be true
          expect(policy.index?).to be true
        end

        it 'denies creating' do
          new_event = build(:event)
          new_policy = described_class.new(nil, new_event)
          expect(new_policy.create?).to be false
          expect(new_policy.new?).to be false
        end

        it 'denies management actions' do
          expect(policy.edit?).to be false
          expect(policy.update?).to be false
          expect(policy.destroy?).to be false
          expect(policy.postpone?).to be false
          expect(policy.cancel?).to be false
          expect(policy.reactivate?).to be false
        end
      end

      context 'with a members-only event' do
        let(:event) { create(:event, :members_only, user: creator) }
        let(:policy) { described_class.new(nil, event) }

        it 'denies viewing' do
          expect(policy.show?).to be false
        end
      end

      context 'with a private event' do
        let(:event) { create(:event, :private, user: creator) }
        let(:policy) { described_class.new(nil, event) }

        it 'denies viewing' do
          expect(policy.show?).to be false
        end
      end
    end

    context 'for a regular user (not creator or host)' do
      let(:user) { create(:user) }
      let(:policy) { described_class.new(user, event) }

      context 'with a public event' do
        it 'allows viewing but not creating' do
          expect(policy.show?).to be true
          expect(policy.index?).to be true

          new_event = build(:event)
          new_policy = described_class.new(user, new_event)
          expect(new_policy.create?).to be false
        end

        it 'denies management actions' do
          expect(policy.edit?).to be false
          expect(policy.update?).to be false
          expect(policy.destroy?).to be false
          expect(policy.postpone?).to be false
          expect(policy.cancel?).to be false
          expect(policy.reactivate?).to be false
        end
      end

      context 'with a members-only event' do
        let(:event) { create(:event, :members_only, user: creator) }

        it 'allows viewing' do
          expect(policy.show?).to be true
        end
      end

      context 'with a private event' do
        let(:event) { create(:event, :private, user: creator) }

        it 'denies viewing' do
          expect(policy.show?).to be false
        end
      end
    end

    context 'for the event creator' do
      let(:policy) { described_class.new(creator, event) }

      it 'allows all actions' do
        expect(policy.show?).to be true
        expect(policy.index?).to be true
        expect(policy.create?).to be true
        expect(policy.new?).to be true
        expect(policy.edit?).to be true
        expect(policy.update?).to be true
        expect(policy.destroy?).to be true
        expect(policy.postpone?).to be true
        expect(policy.cancel?).to be true
        expect(policy.reactivate?).to be true
      end

      context 'with a private event' do
        let(:event) { create(:event, :private, user: creator) }

        it 'allows viewing and editing own private event' do
          expect(policy.show?).to be true
          expect(policy.edit?).to be true
        end
      end
    end

    context 'for an event host (not creator)' do
      let(:host_user) { create(:user) }
      let(:policy) { described_class.new(host_user, event) }

      before do
        event.add_host(host_user)
      end

      it 'allows management but not deletion' do
        expect(policy.show?).to be true
        expect(policy.edit?).to be true
        expect(policy.update?).to be true
        expect(policy.postpone?).to be true
        expect(policy.cancel?).to be true
        expect(policy.reactivate?).to be true
      end

      it 'denies deletion' do
        expect(policy.destroy?).to be false
      end

      context 'with a draft event' do
        let(:draft_event) { create(:event, draft: true, visibility: 'public', user: creator) }
        let(:policy) { described_class.new(host_user, draft_event) }

        before do
          draft_event.add_host(host_user)
        end

        it 'allows viewing a draft event they host' do
          expect(policy.show?).to be true
        end

        it 'allows editing' do
          expect(policy.edit?).to be true
          expect(policy.update?).to be true
        end
      end

      context 'with a private event' do
        let(:private_event) { create(:event, :private, user: creator) }
        let(:policy) { described_class.new(host_user, private_event) }

        before do
          private_event.add_host(host_user)
        end

        it 'allows viewing a private event they host' do
          expect(policy.show?).to be true
        end

        it 'allows editing' do
          expect(policy.edit?).to be true
          expect(policy.update?).to be true
        end
      end
    end

    context 'for a user with can_create_events permission' do
      let(:event_creator_user) { create(:user, :can_create_events) }
      let(:policy) { described_class.new(event_creator_user, event) }

      it 'allows viewing and creating but not editing others events' do
        expect(policy.show?).to be true
        expect(policy.index?).to be true

        new_event = build(:event)
        new_policy = described_class.new(event_creator_user, new_event)
        expect(new_policy.create?).to be true
        expect(new_policy.new?).to be true
      end

      it 'denies management of others events' do
        expect(policy.edit?).to be false
        expect(policy.update?).to be false
        expect(policy.destroy?).to be false
        expect(policy.postpone?).to be false
        expect(policy.cancel?).to be false
        expect(policy.reactivate?).to be false
      end
    end

    context 'for an admin user' do
      let(:admin) { create(:user, :admin) }
      let(:policy) { described_class.new(admin, event) }

      it 'allows all actions' do
        expect(policy.show?).to be true
        expect(policy.index?).to be true
        expect(policy.create?).to be true
        expect(policy.new?).to be true
        expect(policy.edit?).to be true
        expect(policy.update?).to be true
        expect(policy.destroy?).to be true
        expect(policy.postpone?).to be true
        expect(policy.cancel?).to be true
        expect(policy.reactivate?).to be true
      end

      context 'with a private event' do
        let(:event) { create(:event, :private, user: creator) }

        it 'allows viewing and editing any private event' do
          expect(policy.show?).to be true
          expect(policy.edit?).to be true
        end
      end
    end
  end

  describe 'draft event visibility' do
    let(:draft_creator) { create(:user, :can_create_events) }
    let(:draft_event) { create(:event, draft: true, visibility: 'public', user: draft_creator) }

    context 'for a guest user' do
      let(:policy) { described_class.new(nil, draft_event) }

      it 'denies viewing draft events' do
        expect(policy.show?).to be false
      end
    end

    context 'for a regular user' do
      let(:user) { create(:user) }
      let(:policy) { described_class.new(user, draft_event) }

      it 'denies viewing draft events' do
        expect(policy.show?).to be false
      end
    end

    context 'for the draft creator' do
      let(:policy) { described_class.new(draft_creator, draft_event) }

      it 'allows viewing own draft events' do
        expect(policy.show?).to be true
      end

      it 'allows editing own draft events' do
        expect(policy.edit?).to be true
        expect(policy.update?).to be true
      end
    end

    context 'for an admin' do
      let(:admin) { create(:user, :admin) }
      let(:policy) { described_class.new(admin, draft_event) }

      it 'allows viewing any draft event' do
        expect(policy.show?).to be true
      end

      it 'allows editing any draft event' do
        expect(policy.edit?).to be true
        expect(policy.update?).to be true
      end
    end

    context 'for a non-creator host' do
      let(:host_user) { create(:user) }
      let(:policy) { described_class.new(host_user, draft_event) }

      before do
        draft_event.add_host(host_user)
      end

      it 'allows viewing' do
        expect(policy.show?).to be true
      end

      it 'allows editing' do
        expect(policy.edit?).to be true
      end
    end

    context 'for a signed-in user who does not host the draft' do
      let(:other_user) { create(:user) }
      let(:policy) { described_class.new(other_user, draft_event) }

      it 'denies viewing' do
        expect(policy.show?).to be false
      end
    end
  end

  describe 'Scope' do
    let!(:public_event) { create(:event, visibility: 'public') }
    let!(:members_event) { create(:event, :members_only) }
    let!(:private_event) { create(:event, :private) }
    let(:user) { create(:user) }
    let(:admin) { create(:user, :admin) }

    context 'for a guest' do
      it 'returns only public events' do
        scope = Pundit.policy_scope!(nil, Event)
        expect(scope).to include(public_event)
        expect(scope).not_to include(members_event, private_event)
      end

      it 'excludes draft events' do
        draft_event = create(:event, visibility: 'public', draft: true)
        scope = Pundit.policy_scope!(nil, Event)
        expect(scope).not_to include(draft_event)
      end
    end

    context 'for a regular user' do
      it 'returns public and members events' do
        scope = Pundit.policy_scope!(user, Event)
        expect(scope).to include(public_event, members_event)
        expect(scope).not_to include(private_event)
      end

      it 'excludes other users draft events' do
        other_user = create(:user)
        other_draft = create(:event, visibility: 'public', draft: true, user: other_user)
        scope = Pundit.policy_scope!(user, Event)
        expect(scope).not_to include(other_draft)
      end

      it 'includes their own draft events' do
        own_draft = create(:event, visibility: 'public', draft: true, user: user)
        scope = Pundit.policy_scope!(user, Event)
        expect(scope).to include(own_draft)
      end
    end

    context 'for an admin' do
      it 'returns all events' do
        scope = Pundit.policy_scope!(admin, Event)
        expect(scope).to include(public_event, members_event, private_event)
      end

      it 'includes all draft events' do
        other_user = create(:user)
        other_draft = create(:event, visibility: 'public', draft: true, user: other_user)
        scope = Pundit.policy_scope!(admin, Event)
        expect(scope).to include(other_draft)
      end
    end

    context 'for a user who hosts a private event' do
      let(:user_private_event) { create(:event, :private, user: user) }

      it 'includes their hosted private event' do
        user_private_event # Create it
        scope = Pundit.policy_scope!(user, Event)
        expect(scope).to include(user_private_event)
      end
    end

    context 'for a non-creator host' do
      let(:creator) { create(:user) }
      let(:host_user) { create(:user) }
      let!(:hosted_draft) { create(:event, visibility: 'public', draft: true, user: creator) }
      let!(:hosted_private) { create(:event, :private, user: creator) }

      before do
        hosted_draft.add_host(host_user)
        hosted_private.add_host(host_user)
      end

      it 'includes draft events they host but did not create' do
        scope = Pundit.policy_scope!(host_user, Event)
        expect(scope).to include(hosted_draft)
      end

      it 'includes private events they host but did not create' do
        scope = Pundit.policy_scope!(host_user, Event)
        expect(scope).to include(hosted_private)
      end

      it 'still excludes drafts and private events they do not host' do
        other_draft = create(:event, visibility: 'public', draft: true, user: creator)
        other_private = create(:event, :private, user: creator)

        scope = Pundit.policy_scope!(host_user, Event)
        expect(scope).not_to include(other_draft, other_private)
      end

      it 'returns each event once' do
        scope = Pundit.policy_scope!(host_user, Event)
        expect(scope.where(id: hosted_draft.id).count).to eq(1)
      end
    end
  end
end
