defmodule UwBillingWeb.Plugs.ApiUsageLogger do
  @behaviour Plug

  import Plug.Conn

  @internal_prefixes [
    "/api/usage",
    "/api/billing",
    "/api/subscription",
    "/api/plans",
    "/api/account",
    "/api/invoices",
    "/api/settings",
    "/api/setup",
    "/webhooks"
  ]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    start = System.monotonic_time(:millisecond)

    register_before_send(conn, fn conn ->
      if metered_path?(conn.request_path) do
        duration_ms = System.monotonic_time(:millisecond) - start
        user_id = conn.assigns[:current_user_id] || 0
        plan_tier = conn.assigns[:plan_tier] || "unknown"
        path = normalize_path(conn.request_path)
        error = conn.status >= 500

        event = %{
          user_id: user_id,
          plan_tier: plan_tier,
          method: conn.method,
          path: path,
          status_code: conn.status,
          duration_ms: duration_ms * 1.0,
          error: error
        }

        UwBilling.Usage.BufferServer.push(event)
      end

      conn
    end)
  end

  defp metered_path?(path) do
    not Enum.any?(@internal_prefixes, &String.starts_with?(path, &1))
  end

  defp normalize_path(path) do
    path
    |> String.split("/")
    |> Enum.map(&normalize_segment/1)
    |> Enum.join("/")
  end

  defp normalize_segment(seg) do
    cond do
      seg =~ ~r/^\d+$/ -> ":id"
      seg =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i -> ":uuid"
      seg =~ ~r/^[A-Z]{1,5}$/ -> ":ticker"
      true -> seg
    end
  end
end
