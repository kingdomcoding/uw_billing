# Idempotent Stripe setup for the demo. Called from bin/reset after seeds.exs.
#
# Steps (all idempotent, safe to run multiple times):
#   1. Provision Stripe products/prices → store in DB config and Plan records
#   2. Ensure demo Stripe customer exists
#   3. Create demo subscription → write directly to DB (no webhook needed)
#   4. Seed demo invoices
#   5. Live-only: register webhook endpoint in Stripe

require Logger

secret_key =
  System.get_env("STRIPE_SECRET_KEY") ||
    raise "STRIPE_SECRET_KEY must be set before running this script"

parse_unix = fn
  nil -> nil
  ts when is_integer(ts) -> DateTime.from_unix!(ts) |> DateTime.truncate(:second)
end

# ── Step 1: Provision prices ──────────────────────────────────────────────────

{price_id_pro, price_id_premium} =
  case UwBilling.Config.get_stripe_config_any() do
    {:ok, config}
    when not is_nil(config) and
           not is_nil(config.price_id_pro) and
           not is_nil(config.price_id_premium) ->
      Logger.info("SetupStripe: prices already provisioned, skipping")
      {config.price_id_pro, config.price_id_premium}

    _ ->
      Logger.info("SetupStripe: provisioning Stripe products and prices...")

      with {:ok, pro_product} <-
             Stripe.Product.create(%{name: "Pro"}, api_key: secret_key),
           {:ok, pro_price} <-
             Stripe.Price.create(
               %{unit_amount: 4900, currency: "usd", recurring: %{interval: "month"}, product: pro_product.id},
               api_key: secret_key
             ),
           {:ok, premium_product} <-
             Stripe.Product.create(%{name: "Premium"}, api_key: secret_key),
           {:ok, premium_price} <-
             Stripe.Price.create(
               %{unit_amount: 9900, currency: "usd", recurring: %{interval: "month"}, product: premium_product.id},
               api_key: secret_key
             ) do
        webhook_secret = System.get_env("STRIPE_WEBHOOK_SECRET")

        UwBilling.Config.save_stripe_config(%{
          secret_key:       secret_key,
          webhook_secret:   webhook_secret,
          price_id_pro:     pro_price.id,
          price_id_premium: premium_price.id,
          verified_at:      DateTime.utc_now()
        })

        with {:ok, pro}     <- UwBilling.Billing.get_plan_by_tier(:pro),
             {:ok, premium} <- UwBilling.Billing.get_plan_by_tier(:premium) do
          UwBilling.Billing.update_plan(pro, %{stripe_price_id: pro_price.id})
          UwBilling.Billing.update_plan(premium, %{stripe_price_id: premium_price.id})
        end

        Logger.info("SetupStripe: prices provisioned — pro=#{pro_price.id}, premium=#{premium_price.id}")
        {pro_price.id, premium_price.id}
      else
        {:error, %Stripe.Error{} = err} -> raise "Stripe price provisioning failed: #{err.message}"
        {:error, reason}                -> raise "Stripe price provisioning failed: #{inspect(reason)}"
      end
  end

# ── Step 2: Ensure demo customer ──────────────────────────────────────────────

{:ok, [user | _]} = UwBilling.Accounts.list_users()

user =
  if user.stripe_customer_id do
    Logger.info("SetupStripe: Stripe customer already exists (#{user.stripe_customer_id}), skipping")
    user
  else
    Logger.info("SetupStripe: creating Stripe customer...")

    with {:ok, customer} <-
           Stripe.Customer.create(%{email: to_string(user.email)}, api_key: secret_key),
         {:ok, pm} <-
           Stripe.PaymentMethod.attach("pm_card_visa", %{customer: customer.id}, api_key: secret_key),
         {:ok, _} <-
           Stripe.Customer.update(
             customer.id,
             %{invoice_settings: %{default_payment_method: pm.id}},
             api_key: secret_key
           ),
         {:ok, updated} <-
           UwBilling.Accounts.update_user(user, %{stripe_customer_id: customer.id}) do
      Logger.info("SetupStripe: customer created — #{customer.id}")
      updated
    else
      {:error, %Stripe.Error{} = err} -> raise "Stripe customer creation failed: #{err.message}"
      {:error, reason}                -> raise "Stripe customer creation failed: #{inspect(reason)}"
    end
  end

# ── Step 3: Create demo subscription ─────────────────────────────────────────

case UwBilling.Billing.get_active_subscription(user.id) do
  {:ok, [_existing | _]} ->
    Logger.info("SetupStripe: subscription already in DB, skipping")

  {:ok, []} ->
    Logger.info("SetupStripe: checking for existing subscription in Stripe...")

    stripe_sub =
      case Stripe.Subscription.list(%{customer: user.stripe_customer_id, limit: 1}, api_key: secret_key) do
        {:ok, %{data: [existing | _]}} ->
          Logger.info("SetupStripe: found existing subscription in Stripe — #{existing.id}")
          existing

        _ ->
          Logger.info("SetupStripe: creating subscription in Stripe...")

          case Stripe.Subscription.create(
                 %{customer: user.stripe_customer_id, items: [%{price: price_id_pro}]},
                 api_key: secret_key
               ) do
            {:ok, new_sub} ->
              Logger.info("SetupStripe: subscription created — #{new_sub.id}")
              new_sub

            {:error, %Stripe.Error{} = err} ->
              raise "Stripe subscription creation failed: #{err.message}"

            {:error, reason} ->
              raise "Stripe subscription creation failed: #{inspect(reason)}"
          end
      end

    {:ok, plan} = UwBilling.Billing.get_plan_by_tier(:pro)

    {:ok, sub_record} =
      UwBilling.Billing.create_subscription(%{
        user_id:                user.id,
        plan_id:                plan.id,
        stripe_subscription_id: stripe_sub.id,
        stripe_customer_id:     stripe_sub.customer,
        current_period_start:   parse_unix.(stripe_sub.current_period_start),
        current_period_end:     parse_unix.(stripe_sub.current_period_end),
        cancel_at_period_end:   stripe_sub.cancel_at_period_end || false
      })

    UwBilling.Billing.activate_subscription(sub_record, %{})
    Logger.info("SetupStripe: subscription written to DB and activated")

  {:error, reason} ->
    raise "Could not check existing subscriptions: #{inspect(reason)}"
end

# ── Step 4: Seed demo invoices ────────────────────────────────────────────────

{:ok, [user_fresh | _]} = UwBilling.Accounts.list_users()

case UwBilling.Billing.get_active_subscription(user_fresh.id) do
  {:ok, [sub | _]} ->
    case UwBilling.Billing.get_invoices_for_subscription(sub.id) do
      {:ok, [_ | _]} ->
        Logger.info("SetupStripe: invoices already seeded, skipping")

      {:ok, []} ->
        Logger.info("SetupStripe: seeding demo invoices...")
        {:ok, pro_plan} = UwBilling.Billing.get_plan_by_tier(:pro)
        now = DateTime.utc_now()

        for months_ago <- [3, 2, 1] do
          paid_at = DateTime.add(now, -(months_ago * 30 * 24 * 3600), :second)

          UwBilling.Billing.upsert_invoice(%{
            stripe_invoice_id: "in_demo_hist_#{months_ago}mo",
            subscription_id:   sub.id,
            amount_cents:      pro_plan.amount_cents,
            status:            :paid,
            due_date:          DateTime.to_date(paid_at),
            paid_at:           paid_at
          })
        end

        Logger.info("SetupStripe: seeded 3 demo invoices")

      {:error, reason} ->
        Logger.warning("SetupStripe: could not check invoices: #{inspect(reason)}")
    end

  _ ->
    Logger.warning("SetupStripe: no active subscription found, skipping invoice seeding")
end

# ── Step 6: Fetch initial congress trades ────────────────────────────────────

congress_trades_exist =
  case UwBilling.Congress.recent_trades(1) do
    {:ok, [_ | _]} -> true
    _              -> false
  end

if congress_trades_exist do
  Logger.info("SetupStripe: congress trades already in DB, skipping")
else
  Logger.info("SetupStripe: fetching congress trades from EDGAR...")

  case UwBilling.Workers.CongressTradePoller.perform(struct(Oban.Job, %{})) do
    :ok ->
      Logger.info("SetupStripe: congress trades loaded")

    {:error, reason} ->
      Logger.warning(
        "SetupStripe: trade fetch failed (#{inspect(reason)}); " <>
          "the 6-hour cron will retry automatically"
      )
  end
end

# ── Step 5: Live-only webhook endpoint registration ───────────────────────────

phx_host = System.get_env("PHX_HOST") || "localhost"

if phx_host not in ["localhost", "127.0.0.1"] do
  webhook_url = "https://#{phx_host}/webhooks/stripe"
  Logger.info("SetupStripe: checking for webhook endpoint at #{webhook_url}...")

  case Stripe.WebhookEndpoint.list(%{}, api_key: secret_key) do
    {:ok, %{data: endpoints}} ->
      already_registered = Enum.any?(endpoints, &(&1.url == webhook_url))

      if already_registered do
        Logger.info("SetupStripe: webhook endpoint already registered, skipping")
      else
        case Stripe.WebhookEndpoint.create(
               %{
                 url: webhook_url,
                 enabled_events: [
                   "customer.subscription.created",
                   "customer.subscription.updated",
                   "customer.subscription.deleted",
                   "customer.subscription.paused",
                   "customer.subscription.resumed",
                   "invoice.finalized",
                   "invoice.paid",
                   "invoice.payment_failed",
                   "invoice.payment_succeeded"
                 ]
               },
               api_key: secret_key
             ) do
          {:ok, endpoint} ->
            IO.puts("""

            ==> Stripe webhook endpoint created.
                Set on your server: STRIPE_WEBHOOK_SECRET=#{endpoint.secret}
            """)

          {:error, %Stripe.Error{} = err} ->
            Logger.warning("SetupStripe: failed to create webhook endpoint: #{err.message}")

          {:error, reason} ->
            Logger.warning("SetupStripe: failed to create webhook endpoint: #{inspect(reason)}")
        end
      end

    {:error, reason} ->
      Logger.warning("SetupStripe: could not list webhook endpoints: #{inspect(reason)}")
  end
else
  Logger.info("SetupStripe: local environment, skipping webhook endpoint registration")
end

Logger.info("SetupStripe: done")
