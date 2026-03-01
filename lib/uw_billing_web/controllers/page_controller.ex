defmodule UwBillingWeb.PageController do
  use UwBillingWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
