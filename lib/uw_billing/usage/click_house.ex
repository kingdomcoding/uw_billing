defmodule UwBilling.Usage.ClickHouse do
  def daily_counts(user_id, days) do
    query = """
    SELECT
      date,
      sumMerge(request_count) AS request_count,
      sumMerge(error_count)   AS error_count
    FROM uw_billing.api_requests_daily
    WHERE user_id = {user_id:UInt64}
      AND date >= today() - {days:UInt32}
    GROUP BY date
    ORDER BY date ASC
    """

    case Ch.query(UwBilling.CH, query, %{user_id: to_user_int(user_id), days: days}) do
      {:ok, %{rows: rows, headers: headers}} -> {:ok, to_maps(headers, rows)}
      {:error, _} = err -> err
    end
  end

  def by_endpoint(user_id) do
    query = """
    SELECT
      path,
      sumMerge(request_count) AS request_count
    FROM uw_billing.api_requests_daily
    WHERE user_id = {user_id:UInt64}
      AND date >= toStartOfMonth(today())
    GROUP BY path
    ORDER BY request_count DESC
    LIMIT 20
    """

    case Ch.query(UwBilling.CH, query, %{user_id: to_user_int(user_id)}) do
      {:ok, %{rows: rows, headers: headers}} -> {:ok, to_maps(headers, rows)}
      {:error, _} = err -> err
    end
  end

  def monthly_count(user_id) do
    query = """
    SELECT sumMerge(request_count) AS total
    FROM uw_billing.api_requests_daily
    WHERE user_id = {user_id:UInt64}
      AND date >= toStartOfMonth(today())
    """

    case Ch.query(UwBilling.CH, query, %{user_id: to_user_int(user_id)}) do
      {:ok, %{rows: [[total]]}} -> {:ok, total || 0}
      {:ok, %{rows: []}} -> {:ok, 0}
      {:error, _} = err -> err
    end
  end

  def latency_percentiles(user_id, days) do
    query = """
    SELECT
      avgMerge(p50_ms) AS p50_ms,
      avgMerge(p95_ms) AS p95_ms
    FROM uw_billing.api_requests_daily
    WHERE user_id = {user_id:UInt64}
      AND date >= today() - {days:UInt32}
    """

    case Ch.query(UwBilling.CH, query, %{user_id: to_user_int(user_id), days: days}) do
      {:ok, %{rows: [[p50, p95]]}} -> {:ok, %{p50: p50 || 0.0, p95: p95 || 0.0}}
      {:ok, %{rows: []}} -> {:ok, %{p50: 0.0, p95: 0.0}}
      {:error, _} = err -> err
    end
  end

  defp to_maps(headers, rows) do
    Enum.map(rows, fn row ->
      Enum.zip(headers, row) |> Map.new()
    end)
  end

  defp to_user_int(user_id) when is_binary(user_id) do
    <<int::unsigned-128>> = Base.decode16!(String.replace(user_id, "-", ""), case: :mixed)
    int
  end

  defp to_user_int(user_id) when is_integer(user_id), do: user_id
end
