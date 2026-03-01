defmodule UwBilling.Accounts.User do
  use Ash.Resource,
    domain: UwBilling.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "users"
    repo UwBilling.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
    end

    attribute :api_key, :string do
      allow_nil? false
    end

    attribute :stripe_customer_id, :string do
      allow_nil? true
    end

    timestamps()
  end

  identities do
    identity :unique_email, [:email]
    identity :unique_api_key, [:api_key]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:email]

      change fn changeset, _ ->
        api_key = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
        Ash.Changeset.force_change_attribute(changeset, :api_key, api_key)
      end
    end

    update :update do
      accept [:stripe_customer_id]
    end

    read :by_api_key do
      get? true
      filter expr(api_key == ^arg(:api_key))

      argument :api_key, :string do
        allow_nil? false
      end
    end

    read :by_stripe_customer do
      get? true
      filter expr(stripe_customer_id == ^arg(:stripe_customer_id))

      argument :stripe_customer_id, :string do
        allow_nil? false
      end
    end
  end
end
