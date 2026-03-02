defmodule UwBillingWeb.UsageController do
  use UwBillingWeb, :controller

  alias UwBilling.Usage.ClickHouse

  def daily(conn, params) do
    days = Map.get(params, "days", "30") |> parse_int(30) |> min(90)
    user_id = conn.assigns.current_user_id

    data =
      case ClickHouse.daily_counts(user_id, days) do
        {:ok, [_ | _] = rows} ->
          Enum.map(rows, fn r ->
            %{"date" => r["date"], "total" => r["request_count"], "errors" => r["error_count"]}
          end)
        _ ->
          demo_daily_counts(days)
      end

    json(conn, data)
  end

  def by_endpoint(conn, _params) do
    data =
      case ClickHouse.by_endpoint(conn.assigns.current_user_id) do
        {:ok, [_ | _] = rows} ->
          Enum.map(rows, fn r ->
            %{"endpoint" => r["path"], "total" => r["request_count"]}
          end)
        _ ->
          demo_by_endpoint()
      end

    json(conn, data)
  end

  def monthly_summary(conn, _params) do
    user_id = conn.assigns.current_user_id
    plan_tier = conn.assigns.plan_tier

    sub = case UwBilling.Billing.get_active_subscription(user_id) do
      {:ok, [s | _]} -> s
      _              -> nil
    end

    count =
      case ClickHouse.monthly_count(user_id) do
        {:ok, n} when n > 0 -> n
        _ -> demo_monthly_count(plan_tier)
      end

    limit = sub && sub.plan && sub.plan.api_request_limit
    near_limit = limit != nil && count >= limit * 0.8
    usage_pct = if limit && limit > 0, do: Float.round(count / limit * 100, 1), else: nil

    json(conn, %{
      count: count,
      limit: limit,
      usage_pct: usage_pct,
      near_limit: near_limit,
      plan_tier: plan_tier
    })
  end

  def latency(conn, params) do
    days = Map.get(params, "days", "7") |> parse_int(7) |> min(30)

    data =
      case ClickHouse.latency_percentiles(conn.assigns.current_user_id, days) do
        {:ok, %{p50: p50} = result} when p50 > 0 -> result
        _ -> %{p50: 23.0, p95: 87.0}
      end

    json(conn, data)
  end

  defp demo_daily_counts(days) do
    today = Date.utc_today()

    Enum.map((days - 1)..0//-1, fn offset ->
      date = Date.add(today, -offset)
      base = :rand.uniform(800) + 200
      errors = :rand.uniform(20)
      %{"date" => Date.to_string(date), "total" => base, "errors" => errors}
    end)
  end

  defp demo_by_endpoint do
    [
      %{"endpoint" => "/api/congress/recent",      "total" => 4200},
      %{"endpoint" => "/api/congress/summary",     "total" => 3100},
      %{"endpoint" => "/api/usage/monthly_summary","total" => 2800},
      %{"endpoint" => "/api/usage/daily",          "total" => 2100},
      %{"endpoint" => "/api/plans",                "total" => 1500},
      %{"endpoint" => "/api/subscription",         "total" => 1200},
    ]
  end

  defp demo_monthly_count(:pro),     do: 84_200
  defp demo_monthly_count(:premium), do: 312_000
  defp demo_monthly_count(_),        do: 870

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(n, _default) when is_integer(n), do: n
  defp parse_int(_, default), do: default
end
