defmodule UwBilling.Billing.StripeEvent do
  use Ash.Resource,
    domain: UwBilling.Billing,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "stripe_events"
    repo UwBilling.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :stripe_event_id, :string do
      allow_nil? false
    end

    attribute :event_type, :string do
      allow_nil? false
    end

    attribute :payload, :map do
      allow_nil? false
    end

    attribute :processed_at, :utc_datetime do
      allow_nil? true
    end

    attribute :error, :string do
      allow_nil? true
    end

    create_timestamp :inserted_at
  end

  identities do
    identity :unique_event, [:stripe_event_id]
  end

  actions do
    defaults [:read]

    create :record do
      accept [:stripe_event_id, :event_type, :payload]
      change set_attribute(:processed_at, &DateTime.utc_now/0)
    end
  end
end
