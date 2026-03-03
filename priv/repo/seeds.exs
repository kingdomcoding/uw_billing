# Run via: mix run priv/repo/seeds.exs  (or automatically via mix setup)
# Idempotent: skips records that already exist.

alias UwBilling.{Accounts, Billing, Congress}

# ── Plans ────────────────────────────────────────────────────────────────────

plans = [
  %{
    name: "Free",
    tier: :free,
    amount_cents: 0,
    api_request_limit: 1_000
  },
  %{
    name: "Pro",
    tier: :pro,
    stripe_price_id: System.get_env("STRIPE_PRICE_PRO_MONTHLY", "price_pro_monthly_dev"),
    amount_cents: 4_900,
    interval: "month",
    api_request_limit: 100_000
  },
  %{
    name: "Premium",
    tier: :premium,
    stripe_price_id: System.get_env("STRIPE_PRICE_PREMIUM_MONTHLY", "price_premium_monthly_dev"),
    amount_cents: 9_900,
    interval: "month",
    api_request_limit: nil
  }
]

Enum.each(plans, fn attrs ->
  case Billing.get_plan_by_tier(attrs.tier) do
    {:ok, nil}       -> Billing.create_plan!(attrs)
    {:ok, _existing} -> :ok
    {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} ->
      Billing.create_plan!(attrs)
  end
end)

IO.puts("Seeded #{length(plans)} plans.")

# ── Demo user ─────────────────────────────────────────────────────────────────

demo_email = "demo@unusualwhales.dev"

demo_user =
  case Accounts.create_user(%{email: demo_email}) do
    {:ok, user} ->
      user

    {:error, _} ->
      # User already exists — list all and match by email
      {:ok, users} = Accounts.list_users()
      Enum.find(users, fn u -> to_string(u.email) == demo_email end)
  end

UwBilling.Usage.SeedDemo.seed_usage(demo_user.id)

IO.puts("""

Demo user ready:
  email:   #{demo_user.email}
  api_key: #{demo_user.api_key}

Auto-login will pick up the api_key when the app loads at http://localhost:4000
""")

# ── Congress trades ───────────────────────────────────────────────────────────

congress_trades = [
  %{trader_name: "Nancy Pelosi",       ticker: "NVDA", transaction_type: :purchase, amount_range: "$1M–$5M",   traded_at: ~D[2026-01-15], filed_at: ~D[2026-02-01]},
  %{trader_name: "Nancy Pelosi",       ticker: "AAPL", transaction_type: :sale,     amount_range: "$500K–$1M", traded_at: ~D[2026-01-20], filed_at: ~D[2026-02-05]},
  %{trader_name: "Nancy Pelosi",       ticker: "MSFT", transaction_type: :purchase, amount_range: "$250K–$500K", traded_at: ~D[2025-12-10], filed_at: ~D[2025-12-28]},
  %{trader_name: "Dan Crenshaw",       ticker: "XOM",  transaction_type: :purchase, amount_range: "$15K–$50K",  traded_at: ~D[2026-01-08], filed_at: ~D[2026-01-22]},
  %{trader_name: "Dan Crenshaw",       ticker: "CVX",  transaction_type: :purchase, amount_range: "$15K–$50K",  traded_at: ~D[2026-01-08], filed_at: ~D[2026-01-22]},
  %{trader_name: "Tommy Tuberville",   ticker: "LMT",  transaction_type: :purchase, amount_range: "$50K–$100K", traded_at: ~D[2025-11-20], filed_at: ~D[2025-12-05]},
  %{trader_name: "Tommy Tuberville",   ticker: "RTX",  transaction_type: :purchase, amount_range: "$50K–$100K", traded_at: ~D[2025-11-20], filed_at: ~D[2025-12-05]},
  %{trader_name: "Tommy Tuberville",   ticker: "NOC",  transaction_type: :sale,     amount_range: "$15K–$50K",  traded_at: ~D[2026-01-03], filed_at: ~D[2026-01-17]},
  %{trader_name: "Josh Gottheimer",    ticker: "GOOGL",transaction_type: :purchase, amount_range: "$100K–$250K",traded_at: ~D[2026-02-01], filed_at: ~D[2026-02-14]},
  %{trader_name: "Josh Gottheimer",    ticker: "META", transaction_type: :purchase, amount_range: "$50K–$100K", traded_at: ~D[2026-02-01], filed_at: ~D[2026-02-14]},
  %{trader_name: "Ro Khanna",          ticker: "TSLA", transaction_type: :sale,     amount_range: "$15K–$50K",  traded_at: ~D[2026-01-28], filed_at: ~D[2026-02-10]},
  %{trader_name: "Ro Khanna",          ticker: "AMZN", transaction_type: :purchase, amount_range: "$1K–$15K",   traded_at: ~D[2026-01-28], filed_at: ~D[2026-02-10]},
  %{trader_name: "Michael McCaul",     ticker: "BA",   transaction_type: :purchase, amount_range: "$250K–$500K",traded_at: ~D[2025-10-15], filed_at: ~D[2025-10-30]},
  %{trader_name: "Michael McCaul",     ticker: "GD",   transaction_type: :purchase, amount_range: "$100K–$250K",traded_at: ~D[2025-10-15], filed_at: ~D[2025-10-30]},
  %{trader_name: "Virginia Foxx",      ticker: "JPM",  transaction_type: :sale,     amount_range: "$50K–$100K", traded_at: ~D[2026-01-10], filed_at: ~D[2026-01-24]},
  %{trader_name: "Virginia Foxx",      ticker: "BAC",  transaction_type: :sale,     amount_range: "$50K–$100K", traded_at: ~D[2026-01-10], filed_at: ~D[2026-01-24]},
  %{trader_name: "David Schweikert",   ticker: "NVDA", transaction_type: :purchase, amount_range: "$100K–$250K",traded_at: ~D[2026-01-18], filed_at: ~D[2026-02-01]},
  %{trader_name: "David Schweikert",   ticker: "AMD",  transaction_type: :purchase, amount_range: "$50K–$100K", traded_at: ~D[2026-01-18], filed_at: ~D[2026-02-01]},
  %{trader_name: "Marjorie Taylor Greene", ticker: "PHMD", transaction_type: :purchase, amount_range: "$1K–$15K", traded_at: ~D[2025-12-01], filed_at: ~D[2025-12-20]},
  %{trader_name: "Marjorie Taylor Greene", ticker: "DIS",  transaction_type: :sale,    amount_range: "$1K–$15K", traded_at: ~D[2025-12-01], filed_at: ~D[2025-12-20]},
  %{trader_name: "Pete Sessions",      ticker: "AAPL", transaction_type: :purchase, amount_range: "$15K–$50K",  traded_at: ~D[2026-01-22], filed_at: ~D[2026-02-05]},
  %{trader_name: "Pete Sessions",      ticker: "MSFT", transaction_type: :purchase, amount_range: "$15K–$50K",  traded_at: ~D[2026-01-22], filed_at: ~D[2026-02-05]},
  %{trader_name: "John Curtis",        ticker: "AAPL", transaction_type: :sale,     amount_range: "$50K–$100K", traded_at: ~D[2025-12-15], filed_at: ~D[2026-01-05]},
  %{trader_name: "John Curtis",        ticker: "GOOGL",transaction_type: :sale,     amount_range: "$50K–$100K", traded_at: ~D[2025-12-15], filed_at: ~D[2026-01-05]},
  %{trader_name: "Greg Steube",        ticker: "TSLA", transaction_type: :purchase, amount_range: "$1K–$15K",   traded_at: ~D[2026-02-05], filed_at: ~D[2026-02-18]},
  %{trader_name: "Greg Steube",        ticker: "NVDA", transaction_type: :purchase, amount_range: "$1K–$15K",   traded_at: ~D[2026-02-05], filed_at: ~D[2026-02-18]},
  %{trader_name: "Austin Scott",       ticker: "DE",   transaction_type: :purchase, amount_range: "$15K–$50K",  traded_at: ~D[2025-11-10], filed_at: ~D[2025-11-25]},
  %{trader_name: "Austin Scott",       ticker: "ADM",  transaction_type: :purchase, amount_range: "$15K–$50K",  traded_at: ~D[2025-11-10], filed_at: ~D[2025-11-25]},
  %{trader_name: "Kevin Hern",         ticker: "AAPL", transaction_type: :purchase, amount_range: "$100K–$250K",traded_at: ~D[2026-01-05], filed_at: ~D[2026-01-20]},
  %{trader_name: "Kevin Hern",         ticker: "AMZN", transaction_type: :purchase, amount_range: "$100K–$250K",traded_at: ~D[2026-01-05], filed_at: ~D[2026-01-20]},
]

Enum.each(congress_trades, fn attrs ->
  Congress.upsert_trade(attrs)
end)

IO.puts("Seeded #{length(congress_trades)} congress trades.")
