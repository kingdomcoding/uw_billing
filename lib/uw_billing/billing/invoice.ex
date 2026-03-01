defmodule UwBilling.Billing.Invoice do
  use Ash.Resource,
    domain: UwBilling.Billing,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "invoices"
    repo UwBilling.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :stripe_invoice_id, :string do
      allow_nil? false
    end

    attribute :amount_cents, :integer do
      allow_nil? false
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:draft, :open, :paid, :uncollectible, :void]
    end

    attribute :due_date, :date do
      allow_nil? true
    end

    attribute :paid_at, :utc_datetime do
      allow_nil? true
    end

    timestamps()
  end

  identities do
    identity :unique_stripe_invoice, [:stripe_invoice_id]
  end

  relationships do
    belongs_to :subscription, UwBilling.Billing.Subscription do
      allow_nil? false
      attribute_type :uuid
    end
  end

  actions do
    defaults [:read]

    create :upsert do
      accept [:stripe_invoice_id, :subscription_id, :amount_cents, :status, :due_date, :paid_at]
      upsert? true
      upsert_identity :unique_stripe_invoice
    end

    update :mark_paid do
      change set_attribute(:status, :paid)
      change set_attribute(:paid_at, &DateTime.utc_now/0)
    end

    update :void do
      change set_attribute(:status, :void)
    end

    read :for_subscription do
      argument :subscription_id, :uuid do
        allow_nil? false
      end

      filter expr(subscription_id == ^arg(:subscription_id))

      prepare fn query, _ ->
        Ash.Query.sort(query, inserted_at: :desc)
      end
    end
  end
end
