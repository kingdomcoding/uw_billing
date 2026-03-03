defmodule UwBilling.Congress do
  use Ash.Domain

  resources do
    resource UwBilling.Congress.CongressTrade do
      define :upsert_trade, action: :from_disclosure
      define :recent_trades, action: :recent, args: [{:optional, :limit}]
      define :trades_by_ticker, action: :by_ticker, args: [:ticker]
      define :search_trades, action: :search, args: [:q]
    end
  end

  def recent_summary do
    case UwBilling.Congress.CongressTrade
         |> Ash.Query.new()
         |> Ash.Query.sort(inserted_at: :desc)
         |> Ash.Query.limit(200)
         |> Ash.read(domain: __MODULE__) do
      {:ok, trades} ->
        summary =
          trades
          |> Enum.group_by(& &1.ticker)
          |> Enum.map(fn {ticker, t} -> %{ticker: ticker, count: length(t)} end)
          |> Enum.sort_by(& &1.count, :desc)
          |> Enum.take(20)

        {:ok, summary}

      {:error, _} = err ->
        err
    end
  end
end
