# Run via: mix run priv/repo/seeds.exs
# Idempotent: skips plans that already exist.

alias UwBilling.Billing

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
