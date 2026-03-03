defmodule UwBilling.Config.StripeConfig do
  use Ash.Resource,
    domain: UwBilling.Config,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "stripe_configs"
    repo UwBilling.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :singleton_key, :string do
      allow_nil? false
      default "default"
    end

    attribute :secret_key, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :webhook_secret, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :price_id_pro, :string do
      allow_nil? false
    end

    attribute :price_id_premium, :string do
      allow_nil? false
    end

    attribute :enabled, :boolean do
      allow_nil? false
      default true
    end

    attribute :user_provided, :boolean do
      allow_nil? false
      default false
    end

    attribute :verified_at, :utc_datetime do
      allow_nil? true
    end

    timestamps()
  end

  identities do
    identity :singleton, [:singleton_key]
  end

  actions do
    read :current do
      get? true
      filter expr(singleton_key == "default" and enabled == true)
    end

    read :current_any do
      get? true
      filter expr(singleton_key == "default")
    end

    create :save do
      accept [:secret_key, :webhook_secret, :price_id_pro, :price_id_premium, :verified_at]
      upsert? true
      upsert_identity :singleton

      change set_attribute(:enabled, true)
      change set_attribute(:user_provided, false)
      change set_attribute(:singleton_key, "default")
    end

    create :save_user_provided do
      accept [:secret_key, :webhook_secret, :price_id_pro, :price_id_premium, :verified_at]
      upsert? true
      upsert_identity :singleton

      change set_attribute(:enabled, true)
      change set_attribute(:user_provided, true)
      change set_attribute(:singleton_key, "default")
    end

    update :disable do
      require_atomic? false
      change set_attribute(:enabled, false)
      change set_attribute(:user_provided, false)
    end
  end
end
