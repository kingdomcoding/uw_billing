defmodule UwBilling.Usage.SeedDemo do
  require Logger

  @endpoints [
    "/api/congress/recent",
    "/api/congress/ticker/:ticker",
    "/api/congress/summary",
    "/api/congress/search"
  ]

  # Relative popularity per endpoint — most to least. Must sum to 1.0.
  @endpoint_weights [0.40, 0.30, 0.20, 0.10]

  @target_monthly 82_000

  # Idempotent — skips if the user already has rows in ClickHouse.
  def seed_usage(user_id) do
    user_int = to_user_int(user_id)

    case Ch.query(
           UwBilling.CH,
           "SELECT count() FROM uw_billing.api_requests WHERE user_id = {uid:UInt64}",
           %{uid: user_int}
         ) do
      {:ok, %{rows: [[n]]}} when n > 0 ->
        Logger.info("SeedDemo: #{n} rows already exist for user #{user_id}, skipping")
        :ok

      _ ->
        do_seed(user_int)
    end
  end

  defp do_seed(user_int) do
    today = Date.utc_today()
    month_start = Date.new!(today.year, today.month, 1)

    # Random total-requests-per-day for current month, scaled so sum ≈ @target_monthly.
    raw_day_weights = Enum.map(1..today.day, fn _ -> :rand.uniform() end)
    weight_sum = Enum.sum(raw_day_weights)

    day_totals =
      raw_day_weights
      |> Enum.map(&round(@target_monthly * &1 / weight_sum))
      |> Enum.with_index(1)
      |> Map.new(fn {count, day} -> {day, count} end)

    endpoint_pairs = Enum.zip(@endpoints, @endpoint_weights)

    rows =
      Enum.flat_map(29..0//-1, fn day_offset ->
        date = Date.add(today, -day_offset)
        ts = DateTime.new!(date, ~T[12:00:00])

        if Date.compare(date, month_start) != :lt do
          day_total = Map.get(day_totals, date.day, 0)

          Enum.flat_map(endpoint_pairs, fn {endpoint, weight} ->
            count = max(1, round(day_total * weight))

            for _ <- 1..count do
              latency = 18.0 + :rand.uniform(40) * 1.0
              error = if :rand.uniform(100) <= 2, do: 1, else: 0
              status = if error == 1, do: 500, else: 200
              [user_int, "pro", "GET", endpoint, status, latency, error, ts]
            end
          end)
        else
          # History: randomize ±50% around 500 per day, with same endpoint weighting.
          day_total = round(250 + :rand.uniform(500))

          Enum.flat_map(endpoint_pairs, fn {endpoint, weight} ->
            count = max(1, round(day_total * weight))

            for _ <- 1..count do
              latency = 18.0 + :rand.uniform(40) * 1.0
              error = if :rand.uniform(100) <= 2, do: 1, else: 0
              status = if error == 1, do: 500, else: 200
              [user_int, "pro", "GET", endpoint, status, latency, error, ts]
            end
          end)
        end
      end)

    query = "INSERT INTO uw_billing.api_requests FORMAT RowBinaryWithNamesAndTypes"
    names = ["user_id", "plan_tier", "method", "path", "status_code", "duration_ms", "error", "timestamp"]
    types = ["UInt64", "LowCardinality(String)", "LowCardinality(String)", "LowCardinality(String)", "UInt16", "Float32", "UInt8", "DateTime"]

    case Ch.query(UwBilling.CH, query, rows, names: names, types: types) do
      {:ok, _} ->
        Logger.info("SeedDemo: inserted #{length(rows)} rows for user_int #{user_int}")

      {:error, reason} ->
        Logger.warning("SeedDemo: insert failed: #{inspect(reason)}")
    end
  end

  defp to_user_int(id) when is_integer(id), do: id

  defp to_user_int(id) when is_binary(id) do
    <<_::64, low::unsigned-64>> = Base.decode16!(String.replace(id, "-", ""), case: :mixed)
    low
  end
end
