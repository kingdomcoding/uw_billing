defmodule UwBillingWeb.PageControllerTest do
  use UwBillingWeb.ConnCase

  test "GET / serves the SPA shell", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ ~s(<div id="app"></div>)
  end
end
