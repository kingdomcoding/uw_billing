defmodule UwBilling.Billing.Subscription do
  use Ash.Resource,
    domain: UwBilling.Billing,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine, AshOban, AshJsonApi.Resource]

  postgres do
    table "subscriptions"
    repo UwBilling.Repo

    custom_indexes do
      index [:user_id], where: "status != 'canceled'", name: "subscriptions_active_user_idx"
      index [:status], where: "status IN ('active', 'past_due', 'trialing')", name: "subscriptions_billable_status_idx"
    end
  end

  json_api do
    type "subscription"
  end

  state_machine do
    state_attribute :status
    initial_states [:free]
    default_initial_state :free

    transitions do
      transition :start_trial, from: :free, to: :trialing
      transition :activate, from: [:free, :trialing, :past_due], to: :active
      transition :fail_payment, from: :active, to: :past_due
      transition :recover_payment, from: :past_due, to: :active
      transition :cancel, from: [:free, :trialing, :active, :past_due, :paused], to: :canceled
      transition :pause, from: :active, to: :paused
      transition :resume, from: :paused, to: :active
    end
  end

  oban do
    triggers do
      trigger :reap_past_due do
        action :cancel
        scheduler_cron "0 * * * *"
        where expr(status == :past_due and past_due_since <= ago(7, :day))
        queue :billing
        max_attempts 3
        scheduler_module_name UwBilling.Workers.Schedulers.ReapPastDueScheduler
        worker_module_name UwBilling.Workers.ReapPastDueWorker
      end

      trigger :sync_from_stripe do
        action :sync_with_stripe
        scheduler_cron "0 2 * * *"
        where expr(
          status not in [:canceled, :free] and
            not is_nil(stripe_subscription_id)
        )
        queue :billing
        max_attempts 3
        scheduler_module_name UwBilling.Workers.Schedulers.SyncFromStripeScheduler
        worker_module_name UwBilling.Workers.SyncFromStripeWorker
      end

      trigger :apply_scheduled_plan_changes do
        action :apply_scheduled_plan
        scheduler_cron "0 * * * *"
        where expr(
          not is_nil(scheduled_plan_id) and
            current_period_end <= now()
        )
        queue :billing
        max_attempts 3
        scheduler_module_name UwBilling.Workers.Schedulers.ApplyScheduledPlanScheduler
        worker_module_name UwBilling.Workers.ApplyScheduledPlanWorker
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :stripe_subscription_id, :string do
      allow_nil? true
    end

    attribute :stripe_customer_id, :string do
      allow_nil? true
    end

    attribute :current_period_start, :utc_datetime do
      allow_nil? true
    end

    attribute :current_period_end, :utc_datetime do
      allow_nil? true
    end

    attribute :trial_end, :utc_datetime do
      allow_nil? true
    end

    attribute :cancel_at_period_end, :boolean do
      default false
    end

    attribute :past_due_since, :utc_datetime do
      allow_nil? true
    end

    timestamps()
  end

  identities do
    identity :unique_stripe_subscription, [:stripe_subscription_id]
  end

  relationships do
    belongs_to :user, UwBilling.Accounts.User do
      allow_nil? false
      attribute_type :uuid
    end

    belongs_to :plan, UwBilling.Billing.Plan do
      allow_nil? false
      attribute_type :uuid
    end

    belongs_to :scheduled_plan, UwBilling.Billing.Plan do
      allow_nil? true
      attribute_type :uuid
      source_attribute :scheduled_plan_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :stripe_subscription_id,
        :stripe_customer_id,
        :current_period_start,
        :current_period_end,
        :trial_end,
        :cancel_at_period_end,
        :user_id,
        :plan_id
      ]
    end

    update :start_trial do
      change transition_state(:trialing)
    end

    update :activate do
      accept [:current_period_start, :current_period_end, :plan_id, :stripe_subscription_id, :stripe_customer_id]
      change transition_state(:active)
    end

    update :fail_payment do
      require_atomic? false
      change transition_state(:past_due)

      change fn changeset, _ ->
        if Ash.Changeset.get_attribute(changeset, :past_due_since) do
          changeset
        else
          Ash.Changeset.force_change_attribute(changeset, :past_due_since, DateTime.utc_now())
        end
      end
    end

    update :recover_payment do
      accept [:current_period_end]
      change transition_state(:active)
      change set_attribute(:past_due_since, nil)
    end

    update :cancel do
      change transition_state(:canceled)
    end

    update :pause do
      change transition_state(:paused)
    end

    update :resume do
      change transition_state(:active)
    end

    update :change_plan do
      require_atomic? false

      argument :plan_id, :uuid do
        allow_nil? false
      end

      argument :immediate, :boolean do
        default false
      end

      change fn changeset, _ ->
        plan_id = Ash.Changeset.get_argument(changeset, :plan_id)
        immediate = Ash.Changeset.get_argument(changeset, :immediate)

        if immediate do
          changeset
          |> Ash.Changeset.force_change_attribute(:plan_id, plan_id)
          |> Ash.Changeset.force_change_attribute(:scheduled_plan_id, nil)
        else
          Ash.Changeset.force_change_attribute(changeset, :scheduled_plan_id, plan_id)
        end
      end
    end

    update :apply_scheduled_plan do
      require_atomic? false

      change fn changeset, _ ->
        scheduled = Ash.Changeset.get_attribute(changeset, :scheduled_plan_id)

        changeset
        |> Ash.Changeset.force_change_attribute(:plan_id, scheduled)
        |> Ash.Changeset.force_change_attribute(:scheduled_plan_id, nil)
      end
    end

    update :sync_with_stripe do
      require_atomic? false
      change UwBilling.Billing.Changes.SyncWithStripe
    end

    read :active_for_user do
      argument :user_id, :uuid do
        allow_nil? false
      end

      filter expr(user_id == ^arg(:user_id) and status != :canceled)
      prepare fn query, _ -> Ash.Query.load(query, :plan) end
    end

    read :by_stripe_id do
      get? true
      filter expr(stripe_subscription_id == ^arg(:stripe_subscription_id))

      argument :stripe_subscription_id, :string do
        allow_nil? false
      end
    end
  end
end
