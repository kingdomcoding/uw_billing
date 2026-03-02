defmodule UwBilling.Billing.Plan do
  use Ash.Resource,
    domain: UwBilling.Billing,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "plans"
    repo UwBilling.Repo
  end

  json_api do
    type "plan"

    routes do
      base "/plans"
      index :read
      get :read
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
    end

    attribute :tier, :atom do
      allow_nil? false
      constraints one_of: [:free, :pro, :premium]
    end

    attribute :stripe_price_id, :string do
      allow_nil? true
    end

    attribute :amount_cents, :integer do
      allow_nil? false
      default 0
    end

    attribute :interval, :string do
      allow_nil? true
    end

    attribute :api_request_limit, :integer do
      allow_nil? true
    end

    attribute :features, :map do
      default %{}
    end

    timestamps()
  end

  identities do
    identity :unique_stripe_price, [:stripe_price_id]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :tier, :stripe_price_id, :amount_cents, :interval, :api_request_limit, :features]
    end

    update :update do
      accept [:name, :amount_cents, :api_request_limit, :features, :stripe_price_id]
    end

    read :by_stripe_price do
      get? true
      filter expr(stripe_price_id == ^arg(:stripe_price_id))

      argument :stripe_price_id, :string do
        allow_nil? false
      end
    end

    read :by_tier do
      get? true
      filter expr(tier == ^arg(:tier))

      argument :tier, :atom do
        allow_nil? false
        constraints one_of: [:free, :pro, :premium]
      end
    end
  end
end
