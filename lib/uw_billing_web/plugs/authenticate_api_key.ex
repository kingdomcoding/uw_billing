defmodule UwBillingWeb.Plugs.AuthenticateApiKey do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    with [api_key] <- get_req_header(conn, "x-api-key"),
         {:ok, user} <- UwBilling.Accounts.get_user_by_api_key(api_key),
         {:ok, sub} <- get_subscription(user.id) do
      plan_tier  = if sub, do: to_string(sub.plan.tier), else: "free"
      plan_limit = if sub, do: sub.plan.api_request_limit, else: 1_000

      conn
      |> assign(:current_user, user)
      |> assign(:current_user_id, user.id)
      |> assign(:plan_tier, plan_tier)
      |> assign(:plan_limit, plan_limit)
    else
      _ ->
        conn
        |> put_status(401)
        |> json(%{error: "Invalid or missing API key"})
        |> halt()
    end
  end

  defp get_subscription(user_id) do
    case UwBilling.Billing.get_active_subscription(user_id) do
      {:ok, [sub | _]} -> {:ok, sub}
      {:ok, []}        -> {:ok, nil}
      {:error, _}      -> {:ok, nil}
    end
  end
end
