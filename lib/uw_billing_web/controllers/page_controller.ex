defmodule UwBillingWeb.PageController do
  use UwBillingWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end
