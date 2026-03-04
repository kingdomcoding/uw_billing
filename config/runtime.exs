import Config

if System.get_env("PHX_SERVER") do
  config :uw_billing, UwBillingWeb.Endpoint, server: true
end

stripe_secret_key =
  System.get_env("STRIPE_SECRET_KEY") ||
    raise "STRIPE_SECRET_KEY is required. Copy .env.example to .env and fill in your credentials."

System.get_env("STRIPE_WEBHOOK_SECRET") ||
  raise "STRIPE_WEBHOOK_SECRET is required. Run: stripe listen --forward-to localhost:4000/webhooks/stripe"

config :stripity_stripe, api_key: stripe_secret_key

# Optional DATABASE_URL override — applies in all envs when set.
# In dev without Docker, dev.exs hardcoded config takes precedence (this block is skipped).
# In Docker (local or prod), DATABASE_URL is set by the compose file.
if database_url = System.get_env("DATABASE_URL") do
  config :uw_billing, UwBilling.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: if(System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: [])
end

# Optional ClickHouse host override — applies in all envs when CLICKHOUSE_HOST is set.
if clickhouse_host = System.get_env("CLICKHOUSE_HOST") do
  config :uw_billing, :clickhouse,
    hostname: clickhouse_host,
    port: String.to_integer(System.get_env("CLICKHOUSE_PORT") || "8123"),
    database: System.get_env("CLICKHOUSE_DB") || "uw_billing",
    username: System.get_env("CLICKHOUSE_USER"),
    password: System.get_env("CLICKHOUSE_PASS"),
    pool_size: String.to_integer(System.get_env("CLICKHOUSE_POOL_SIZE") || "5")
end

if config_env() == :prod do
  System.get_env("DATABASE_URL") ||
    raise """
    environment variable DATABASE_URL is missing.
    For example: ecto://USER:PASS@HOST/DATABASE
    """

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :uw_billing, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :uw_billing, UwBillingWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
end
