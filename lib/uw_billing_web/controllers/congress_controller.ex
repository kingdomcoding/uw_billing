defmodule UwBillingWeb.CongressController do
  use UwBillingWeb, :controller

  def recent(conn, params) do
    limit = Map.get(params, "limit", "50") |> parse_int(50) |> min(100)

    case UwBilling.Congress.recent_trades(limit) do
      {:ok, trades} -> json(conn, Enum.map(trades, &serialize/1))
      {:error, _} -> json(conn, [])
    end
  end

  def by_ticker(conn, %{"ticker" => ticker}) do
    ticker = String.upcase(ticker)

    case UwBilling.Congress.trades_by_ticker(ticker) do
      {:ok, trades} -> json(conn, Enum.map(trades, &serialize/1))
      {:error, _} -> json(conn, [])
    end
  end

  def summary(conn, _params) do
    case UwBilling.Congress.recent_summary() do
      {:ok, data} -> json(conn, data)
      {:error, _} -> json(conn, [])
    end
  end

  defp serialize(trade) do
    %{
      id: trade.id,
      trader_name: trade.trader_name,
      ticker: trade.ticker,
      transaction_type: trade.transaction_type,
      amount_range: trade.amount_range,
      filed_at: trade.filed_at,
      traded_at: trade.traded_at,
      inserted_at: trade.inserted_at
    }
  end

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(n, _default) when is_integer(n), do: n
  defp parse_int(_, default), do: default
end
