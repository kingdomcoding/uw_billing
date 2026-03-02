defmodule UwBillingWeb.UsageController do
  use UwBillingWeb, :controller

  alias UwBilling.Usage.ClickHouse

  def daily(conn, params) do
    days = Map.get(params, "days", "30") |> parse_int(30) |> min(90)
    user_id = conn.assigns.current_user_id

    case ClickHouse.daily_counts(user_id, days) do
      {:ok, data} -> json(conn, data)
      {:error, _} -> json(conn, [])
    end
  end

  def by_endpoint(conn, _params) do
    case ClickHouse.by_endpoint(conn.assigns.current_user_id) do
      {:ok, data} -> json(conn, data)
      {:error, _} -> json(conn, [])
    end
  end

  def monthly_summary(conn, _params) do
    user_id = conn.assigns.current_user_id

    sub = case UwBilling.Billing.get_active_subscription(user_id) do
      {:ok, [s | _]} -> s
      _              -> nil
    end

    with {:ok, count} <- ClickHouse.monthly_count(user_id) do
      limit = sub && sub.plan && sub.plan.api_request_limit
      near_limit = limit != nil && count >= limit * 0.8
      usage_pct = if limit && limit > 0, do: Float.round(count / limit * 100, 1), else: nil

      json(conn, %{
        count: count,
        limit: limit,
        usage_pct: usage_pct,
        near_limit: near_limit,
        plan_tier: conn.assigns.plan_tier
      })
    else
      _ -> json(conn, %{count: 0, limit: nil, usage_pct: nil, near_limit: false, plan_tier: conn.assigns.plan_tier})
    end
  end

  def latency(conn, params) do
    days = Map.get(params, "days", "7") |> parse_int(7) |> min(30)

    case ClickHouse.latency_percentiles(conn.assigns.current_user_id, days) do
      {:ok, data} -> json(conn, data)
      {:error, _} -> json(conn, %{p50: 0.0, p95: 0.0})
    end
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
