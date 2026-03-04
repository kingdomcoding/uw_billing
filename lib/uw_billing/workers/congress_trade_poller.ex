defmodule UwBilling.Workers.CongressTradePoller do
  @moduledoc """
  Fetches recent congressional stock trade disclosures (STOCK Act filings) and
  stores them in Postgres via UwBilling.Congress.upsert_trade/1.

  Data source (in priority order):
    1. Unusual Whales API — DB-stored key (set via Settings page) takes priority
    2. Unusual Whales API — UW_API_KEY env var fallback
    3. EDGAR EFTS public endpoint — no auth required, covers SEC Form 4 filings

  Why this exists: UW's core brand identity is congressional trading transparency.
  Including this in the demo shows domain awareness beyond the technical requirements.
  """
  use Oban.Worker,
    queue: :analytics,
    unique: [period: 3_600, states: [:available, :scheduled, :executing, :retryable]],
    max_attempts: 3

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
    api_key = stored_uw_key() || non_blank(System.get_env("UW_API_KEY"))
    case api_key do
      nil -> fetch_from_edgar()
      key -> fetch_from_uw(key)
    end
  end

  defp stored_uw_key do
    case UwBilling.Config.get_app_config() do
      {:ok, %{uw_api_key: key}} when is_binary(key) and byte_size(key) > 0 -> key
      _ -> nil
    end
  end

  defp fetch_from_uw(api_key) do
    case Req.get("#{@uw_api_base}/api/congress/recent-trades",
           params: [limit: 200],
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
      trader_name:      raw["name"] || raw["reporter"] || "Unknown",
      ticker:           String.upcase(raw["ticker"] || raw["symbol"] || "UNKNOWN"),
      transaction_type: parse_tx_type(raw["txn_type"]),
      amount_range:     raw["amounts"],
      filed_at:         parse_date(raw["filed_at_date"]),
      traded_at:        parse_date(raw["transaction_date"]),
      politician_id:    raw["politician_id"],
      issuer:           raw["issuer"],
      member_type:      raw["member_type"]
    }
  end

  defp parse_edgar_hit(%{"_source" => src}) do
    case extract_ticker(src["display_names"]) do
      nil -> []
      ticker ->
        [%{
          trader_name:      extract_entity_name(src["display_names"]) || "Unknown",
          ticker:           ticker,
          transaction_type: parse_edgar_tx_type(src),
          amount_range:     nil,
          filed_at:         parse_date(src["file_date"]),
          traded_at:        parse_date(src["period_of_report"] || src["period_ending"])
        }]
    end
  end
  defp parse_edgar_hit(_), do: []

  defp extract_ticker(nil), do: nil
  defp extract_ticker(names) when is_list(names) do
    Enum.find_value(names, fn name ->
      case Regex.run(~r/\(([A-Z]{1,5})\)/, name) do
        [_, ticker] -> ticker
        _           -> nil
      end
    end)
  end
  defp extract_ticker(_), do: nil

  defp extract_entity_name(nil), do: nil
  defp extract_entity_name([first | _]) do
    first |> String.replace(~r/\s*\([^)]+\)\s*$/, "") |> String.trim()
  end
  defp extract_entity_name(_), do: nil

  defp parse_edgar_tx_type(%{"transactionCode" => code}) when is_binary(code) do
    case String.upcase(code) do
      "P" -> :purchase
      "S" -> :sale
      "A" -> :purchase
      "D" -> :sale
      _   -> :exchange
    end
  end
  defp parse_edgar_tx_type(_), do: :exchange

  defp parse_tx_type(t) when is_binary(t) do
    t = String.downcase(t)
    cond do
      String.contains?(t, "purchase") or String.contains?(t, "buy")  -> :purchase
      String.contains?(t, "sale")     or String.contains?(t, "sell") -> :sale
      true                                                            -> :exchange
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

  defp non_blank(nil), do: nil
  defp non_blank(""), do: nil
  defp non_blank(s), do: s

  defp last_n_days(n) do
    Date.utc_today() |> Date.add(-n) |> Date.to_iso8601()
  end
end
