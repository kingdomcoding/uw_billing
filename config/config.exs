# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :uw_billing,
  ecto_repos: [UwBilling.Repo],
  generators: [timestamp_type: :utc_datetime]

config :mime, :types, %{"application/vnd.api+json" => ["json-api"]}

config :ash, :domains, [
  UwBilling.Accounts,
  UwBilling.Billing,
  UwBilling.Congress,
  UwBilling.Config
]

config :uw_billing, ash_domains: [
  UwBilling.Accounts,
  UwBilling.Billing,
  UwBilling.Congress,
  UwBilling.Config
]

config :uw_billing, Oban,
  engine: Oban.Engines.Basic,
  queues: [billing: 10, analytics: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 604_800},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 */6 * * *", UwBilling.Workers.CongressTradePoller},
       {"0 * * * *",   UwBilling.Workers.Schedulers.ReapPastDueScheduler},
       {"0 2 * * *",   UwBilling.Workers.Schedulers.SyncFromStripeScheduler},
       {"0 * * * *",   UwBilling.Workers.Schedulers.ApplyScheduledPlanScheduler}
     ]}
  ],
  repo: UwBilling.Repo

config :stripity_stripe,
  api_key: System.get_env("STRIPE_SECRET_KEY")

# Configures the endpoint
config :uw_billing, UwBillingWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: UwBillingWeb.ErrorHTML, json: UwBillingWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: UwBilling.PubSub,
  live_view: [signing_salt: "/mHGF7VM"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  uw_billing: [
    args:
      ~w(js/app.tsx --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../assets/node_modules", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  uw_billing: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
