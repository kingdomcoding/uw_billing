defmodule UwBilling.Config.AppConfig do
  use Ash.Resource,
    domain: UwBilling.Config,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "app_configs"
    repo UwBilling.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :singleton_key, :string do
      allow_nil? false
      default "default"
    end

    attribute :uw_api_key, :string do
      allow_nil? true
      sensitive? true
    end

    timestamps()
  end

  identities do
    identity :singleton, [:singleton_key]
  end

  actions do
    read :current do
      get? true
      filter expr(singleton_key == "default")
    end

    create :save do
      accept [:uw_api_key]
      upsert? true
      upsert_identity :singleton
      change set_attribute(:singleton_key, "default")
    end

    update :clear_uw_key do
      require_atomic? false
      change set_attribute(:uw_api_key, nil)
    end
  end
end
