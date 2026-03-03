defmodule UwBilling.Congress.CongressTrade do
  use Ash.Resource,
    domain: UwBilling.Congress,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "congress_trades"
    repo UwBilling.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :trader_name, :string do
      allow_nil? false
    end

    attribute :ticker, :string do
      allow_nil? false
    end

    attribute :transaction_type, :atom do
      allow_nil? false
      constraints one_of: [:purchase, :sale, :exchange]
    end

    attribute :amount_range, :string do
      allow_nil? true
    end

    attribute :filed_at, :date do
      allow_nil? true
    end

    attribute :traded_at, :date do
      allow_nil? true
    end

    create_timestamp :inserted_at
  end

  identities do
    identity :unique_disclosure, [:trader_name, :ticker, :traded_at, :transaction_type]
  end

  actions do
    create :from_disclosure do
      accept [:trader_name, :ticker, :transaction_type, :amount_range, :filed_at, :traded_at]
      upsert? true
      upsert_identity :unique_disclosure
      upsert_fields [:filed_at, :amount_range]
    end

    read :recent do
      argument :limit, :integer do
        default 20
      end

      prepare fn query, _ ->
        limit = Ash.Query.get_argument(query, :limit) || 20
        query
        |> Ash.Query.sort(filed_at: :desc, inserted_at: :desc)
        |> Ash.Query.limit(limit)
      end
    end

    read :by_ticker do
      argument :ticker, :string do
        allow_nil? false
      end

      argument :limit, :integer do
        default 200
      end

      filter expr(ticker == ^arg(:ticker))

      prepare fn query, _ ->
        limit = Ash.Query.get_argument(query, :limit) || 200
        query
        |> Ash.Query.sort(traded_at: :desc)
        |> Ash.Query.limit(limit)
      end
    end

    read :search do
      argument :q, :string, allow_nil?: false, constraints: [min_length: 1]

      filter expr(
        contains(ticker, ^arg(:q)) or contains(trader_name, ^arg(:q))
      )

      prepare fn query, _ ->
        query
        |> Ash.Query.sort(filed_at: :desc)
        |> Ash.Query.limit(50)
      end
    end
  end
end
