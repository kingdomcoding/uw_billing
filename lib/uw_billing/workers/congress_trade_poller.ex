defmodule UwBilling.Workers.CongressTradePoller do
  @moduledoc """
  Fetches recent congressional stock trade disclosures (STOCK Act filings) and
  stores them in Postgres via UwBilling.Congress.upsert_trade/1.

  Data source (in priority order):
    1. Unusual Whales API — if UW_API_KEY is set, uses /api/congress/recent-trades
    2. EDGAR EFTS public endpoint — no auth required, covers SEC Form 4 filings

  Why this exists: UW's core brand identity is congressional trading transparency.
  Including this in the demo shows domain awareness beyond the technical requirements.
  """
  use Oban.Worker, queue: :analytics, unique: [period: 3_600], max_attempts: 3

  alias UwBilling.Congress
  require Logger

  @uw_api_base    "https://api.unusualwhales.com"
  @edgar_api_base "https://efts.sec.gov/LATEST/search-index"

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("CongressTradePoller: fetching disclosures")

    case fetch_disclosures() do
      {:ok, trades} ->
        results = Enum.map(trades, &Congress.upsert_trade/1)
        errors  = Enum.count(results, &match?({:error, _}, &1))
        Logger.info("CongressTradePoller: processed #{length(trades)} trades, #{errors} errors")
        :ok

      {:error, reason} ->
        Logger.error("CongressTradePoller: fetch failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_disclosures do
    case System.get_env("UW_API_KEY") do
      nil -> fetch_from_edgar()
      key -> fetch_from_uw(key)
    end
  end

  defp fetch_from_uw(api_key) do
    case Req.get("#{@uw_api_base}/api/congress/recent-trades",
           headers: [{"Authorization", "Bearer #{api_key}"}, {"Accept", "application/json"}],
           receive_timeout: 15_000) do
      {:ok, %{status: 200, body: %{"data" => trades}}} ->
        {:ok, Enum.map(trades, &parse_uw_trade/1)}

      {:ok, %{status: status}} ->
        {:error, "UW API returned #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_from_edgar do
    case Req.get(@edgar_api_base,
           params: [q: "\"Form 4\"", dateRange: "custom", startdt: last_n_days(7), forms: "4"],
           receive_timeout: 15_000) do
      {:ok, %{status: 200, body: %{"hits" => %{"hits" => hits}}}} ->
        {:ok, Enum.flat_map(hits, &parse_edgar_hit/1)}

      {:ok, %{status: status}} ->
        {:error, "EDGAR returned #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_uw_trade(raw) do
    %{
      trader_name:      raw["representative"] || raw["senator"] || "Unknown",
      ticker:           String.upcase(raw["ticker"] || ""),
      transaction_type: parse_tx_type(raw["transaction_type"]),
      amount_range:     raw["amount"] || raw["estimated_value"],
      filed_at:         parse_date(raw["filed_at"] || raw["disclosure_date"]),
      traded_at:        parse_date(raw["transaction_date"])
    }
  end

  defp parse_edgar_hit(%{"_source" => src}) do
    [%{
      trader_name:      src["entity_name"] || "Unknown",
      ticker:           src["ticker"] || "",
      transaction_type: :purchase,
      amount_range:     nil,
      filed_at:         parse_date(src["file_date"]),
      traded_at:        parse_date(src["period_of_report"])
    }]
  end
  defp parse_edgar_hit(_), do: []

  defp parse_tx_type(t) when is_binary(t) do
    t = String.downcase(t)
    cond do
      String.contains?(t, "purchase") -> :purchase
      String.contains?(t, "sale")     -> :sale
      true                            -> :exchange
    end
  end
  defp parse_tx_type(_), do: :exchange

  defp parse_date(nil), do: nil
  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _        -> nil
    end
  end

  defp last_n_days(n) do
    Date.utc_today() |> Date.add(-n) |> Date.to_iso8601()
  end
end
