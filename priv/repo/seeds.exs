# Run via: mix run priv/repo/seeds.exs  (or automatically via mix setup)
# Idempotent: skips records that already exist.

alias UwBilling.{Accounts, Billing}

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
