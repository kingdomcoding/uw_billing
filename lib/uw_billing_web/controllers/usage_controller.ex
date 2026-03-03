defmodule UwBillingWeb.UsageController do
  use UwBillingWeb, :controller

  require Logger

  alias UwBilling.Usage.ClickHouse

  def daily(conn, params) do
    days = Map.get(params, "days", "30") |> parse_int(30) |> min(90)
    user_id = conn.assigns.current_user_id

    case ClickHouse.daily_counts(user_id, days) do
      {:ok, rows} ->
        json(conn, Enum.map(rows, fn r ->
          %{"date" => r["date"], "total" => r["request_count"], "errors" => r["error_count"]}
        end))

      {:error, reason} ->
        Logger.warning("ClickHouse daily_counts failed: #{inspect(reason)}")
        conn |> put_status(502) |> json(%{error: "Usage data unavailable"})
    end
  end

  def by_endpoint(conn, _params) do
    case ClickHouse.by_endpoint(conn.assigns.current_user_id) do
      {:ok, rows} ->
        json(conn, Enum.map(rows, fn r ->
          %{"endpoint" => r["path"], "total" => r["request_count"]}
        end))

      {:error, reason} ->
        Logger.warning("ClickHouse by_endpoint failed: #{inspect(reason)}")
        conn |> put_status(502) |> json(%{error: "Usage data unavailable"})
    end
  end

  def monthly_summary(conn, _params) do
    user_id = conn.assigns.current_user_id
    plan_tier = conn.assigns.plan_tier

    sub =
      case UwBilling.Billing.get_active_subscription(user_id) do
        {:ok, [s | _]} -> s
        _ -> nil
      end

    case ClickHouse.monthly_count(user_id) do
      {:ok, count} ->
        limit = sub && sub.plan && sub.plan.api_request_limit
        near_limit = limit != nil && count >= limit * 0.8
        usage_pct = if limit && limit > 0, do: Float.round(count / limit * 100, 1), else: nil

        json(conn, %{
          count: count,
          limit: limit,
          usage_pct: usage_pct,
          near_limit: near_limit,
          plan_tier: plan_tier,
          plan_unlimited: is_nil(limit)
        })

      {:error, reason} ->
        Logger.warning("ClickHouse monthly_count failed: #{inspect(reason)}")
        conn |> put_status(502) |> json(%{error: "Usage data unavailable"})
    end
  end

  def latency(conn, params) do
    days = Map.get(params, "days", "7") |> parse_int(7) |> min(30)

    case ClickHouse.latency_percentiles(conn.assigns.current_user_id, days) do
      {:ok, data} ->
        json(conn, data)

      {:error, reason} ->
        Logger.warning("ClickHouse latency_percentiles failed: #{inspect(reason)}")
        conn |> put_status(502) |> json(%{error: "Usage data unavailable"})
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
