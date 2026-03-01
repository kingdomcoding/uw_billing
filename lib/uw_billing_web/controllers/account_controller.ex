defmodule UwBillingWeb.AccountController do
  use UwBillingWeb, :controller

  def show(conn, _params) do
    user = conn.assigns.current_user
    json(conn, %{email: to_string(user.email), api_key: user.api_key})
  end
end
