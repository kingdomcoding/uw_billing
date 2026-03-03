defmodule UwBillingWeb.Plugs.EnforceRateLimit do
  @behaviour Plug

  import Plug.Conn

  alias UwBilling.Usage.ClickHouse

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
    if metered_path?(conn.request_path) do
      enforce(conn)
    else
      conn
    end
  end

  defp enforce(conn) do
    plan_tier = conn.assigns[:plan_tier]

    if plan_tier == "premium" do
      conn
    else
      limit = conn.assigns[:plan_limit]

      if is_nil(limit) do
        conn
      else
        user_id = conn.assigns[:current_user_id]

        case ClickHouse.monthly_count(user_id) do
          {:ok, count} when count >= limit ->
            conn
            |> put_status(429)
            |> put_resp_content_type("application/json")
            |> send_resp(
              429,
              Jason.encode!(%{
                error: "Monthly request limit exceeded",
                limit: limit,
                message: "Upgrade to Premium for unlimited requests."
              })
            )
            |> halt()

          _ ->
            conn
        end
      end
    end
  end

  defp metered_path?(path) do
    not Enum.any?(@internal_prefixes, &String.starts_with?(path, &1))
  end
end
