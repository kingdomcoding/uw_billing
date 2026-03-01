defmodule UwBillingWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :uw_billing

  @session_options [
    store: :cookie,
    key: "_uw_billing_key",
    signing_salt: "M8m7xPUY",
    same_site: "Lax"
  ]

  plug Plug.Static,
    at: "/",
    from: :uw_billing,
    gzip: not code_reloading?,
    only: UwBillingWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :uw_billing
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    body_reader: {UwBillingWeb.Plugs.CacheBodyReader, :read_body, []}

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug UwBillingWeb.Router
end
