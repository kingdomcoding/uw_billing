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
    case UwBilling.Congress.recent_trades(200) do
      {:ok, trades} ->
        summary =
          trades
          |> Enum.group_by(& &1.ticker)
          |> Enum.map(fn {ticker, t} ->
            latest = t |> Enum.map(& &1.filed_at) |> Enum.max(Date)
            %{ticker: ticker, trades: length(t), latest_filed: Date.to_iso8601(latest)}
          end)
          |> Enum.sort_by(& &1.trades, :desc)
          |> Enum.take(20)

        {:ok, summary}

      {:error, _} = err ->
        err
    end
  end
end
