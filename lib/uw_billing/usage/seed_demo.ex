defmodule UwBilling.Usage.SeedDemo do
  require Logger

  @endpoints [
    "/api/congress/recent",
    "/api/congress/ticker/:ticker",
    "/api/congress/summary",
    "/api/congress/search"
  ]

  @target_monthly 82_000

  # Synchronous. Called from demo_subscribe before the HTTP response is sent.
  # Idempotent — skips if the user already has rows in ClickHouse, guarding
  # against the webhook-timeout retry edge case.
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

    # Rows per day per endpoint to reach @target_monthly using days elapsed this month.
    # e.g. on March 3:  ceil(82_000 / (3 * 4)) = 6_834/day/endpoint × 4 × 3 = 82_008 ✓
    # e.g. on March 25: ceil(82_000 / (25 * 4)) = 820/day/endpoint × 4 × 25 = 82_000 ✓
    rows_this_month = ceil(@target_monthly / (today.day * length(@endpoints)))
    rows_history = 500

    rows =
      Enum.flat_map(29..0//-1, fn day_offset ->
        date = Date.add(today, -day_offset)

        count =
          if Date.compare(date, month_start) != :lt,
            do: rows_this_month,
            else: rows_history

        for endpoint <- @endpoints, _ <- 1..count do
          ts = DateTime.new!(date, ~T[12:00:00])
          latency = 18.0 + :rand.uniform(40) * 1.0
          error = if :rand.uniform(100) <= 2, do: 1, else: 0
          status = if error == 1, do: 500, else: 200
          [user_int, "pro", "GET", endpoint, status, latency, error, ts]
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
