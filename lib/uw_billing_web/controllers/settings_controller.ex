defmodule UwBillingWeb.SettingsController do
  use UwBillingWeb, :controller

  require Logger

  def setup_status(conn, _params) do
    json(conn, %{configured: UwBilling.StripeClient.configured?()})
  end

  def demo_session(conn, _params) do
    case UwBilling.Accounts.list_users() do
      {:ok, [user | _]} -> json(conn, %{api_key: user.api_key, email: to_string(user.email)})
      _                 -> conn |> put_status(404) |> json(%{error: "No users seeded yet"})
    end
  end

  def show_stripe(conn, _params) do
    env_configured = env_configured?()

    case UwBilling.Config.get_stripe_config_any() do
      {:ok, config} when not is_nil(config) ->
        json(conn, %{
          env_configured: env_configured,
          custom_configured: config.enabled,
          configured: config.enabled || env_configured,
          secret_key: mask(config.secret_key),
          webhook_secret: mask(config.webhook_secret),
          price_id_pro: config.price_id_pro,
          price_id_premium: config.price_id_premium,
          verified_at: config.verified_at
        })

      _ ->
        json(conn, %{
          env_configured: env_configured,
          custom_configured: false,
          configured: env_configured
        })
    end
  end

  def verify_stripe(conn, params) do
    %{
      "secret_key" => secret_key,
      "webhook_secret" => webhook_secret,
      "price_id_pro" => price_id_pro,
      "price_id_premium" => price_id_premium
    } = params

    errors = %{}

    errors =
      case Stripe.Balance.retrieve(%{}, api_key: secret_key) do
        {:ok, _} -> errors
        {:error, _} -> Map.put(errors, "secret_key", "Invalid secret key — could not connect to Stripe")
      end

    errors = validate_price(errors, secret_key, "price_id_pro", price_id_pro)
    errors = validate_price(errors, secret_key, "price_id_premium", price_id_premium)

    errors =
      if String.starts_with?(webhook_secret, "whsec_") do
        errors
      else
        Map.put(errors, "webhook_secret", "Must start with whsec_")
      end

    if map_size(errors) == 0 do
      case UwBilling.Config.save_stripe_config(%{
             secret_key: secret_key,
             webhook_secret: webhook_secret,
             price_id_pro: price_id_pro,
             price_id_premium: price_id_premium,
             verified_at: DateTime.utc_now()
           }) do
        {:ok, _} ->
          sync_plan_price_ids(price_id_pro, price_id_premium)
          customer_id = provision_demo_customer(secret_key)
          json(conn, %{configured: true, stripe_customer_id: customer_id, price_id_pro: price_id_pro})

        {:error, error} ->
          conn |> put_status(422) |> json(%{error: inspect(error)})
      end
    else
      conn |> put_status(422) |> json(%{errors: errors})
    end
  end

  def disable_stripe(conn, _params) do
    case UwBilling.Config.get_stripe_config_any() do
      {:ok, config} when not is_nil(config) ->
        UwBilling.Config.disable_stripe_config(config)

      _ ->
        :ok
    end

    json(conn, %{configured: env_configured?()})
  end

  defp env_configured? do
    [
      System.get_env("STRIPE_SECRET_KEY"),
      System.get_env("STRIPE_WEBHOOK_SECRET"),
      System.get_env("STRIPE_PRICE_PRO_MONTHLY"),
      System.get_env("STRIPE_PRICE_PREMIUM_MONTHLY")
    ]
    |> Enum.all?(&(not is_nil(&1) and &1 != ""))
  end

  defp validate_price(errors, _secret_key, field, nil), do: Map.put(errors, field, "Required")
  defp validate_price(errors, _secret_key, field, ""), do: Map.put(errors, field, "Required")

  defp validate_price(errors, secret_key, field, price_id) do
    case Stripe.Price.retrieve(price_id, %{}, api_key: secret_key) do
      {:ok, _} -> errors
      {:error, _} -> Map.put(errors, field, "Price ID not found in Stripe: #{price_id}")
    end
  end

  # Creates a real Stripe subscription for the demo user so the webhook
  # pipeline can be tested end-to-end without needing CLI flag workarounds.
  def demo_subscribe(conn, _params) do
    with {:ok, config}  <- UwBilling.Config.get_stripe_config_any(),
         {:ok, [user | _]} <- UwBilling.Accounts.list_users(),
         true           <- not is_nil(user.stripe_customer_id),
         {:ok, _sub}    <- Stripe.Subscription.create(
                             %{
                               customer: user.stripe_customer_id,
                               items: [%{price: config.price_id_pro}]
                             },
                             api_key: config.secret_key
                           ) do
      json(conn, %{ok: true})
    else
      false ->
        conn |> put_status(422) |> json(%{error: "No Stripe customer provisioned — save credentials first"})
      {:error, %Stripe.Error{} = err} ->
        conn |> put_status(422) |> json(%{error: err.message})
      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: inspect(reason)})
    end
  end

  # Updates Pro and Premium plans with the real Stripe price IDs so that
  # find_plan in the webhook worker can match incoming subscription events.
  defp sync_plan_price_ids(price_id_pro, price_id_premium) do
    with {:ok, pro}     <- UwBilling.Billing.get_plan_by_tier(:pro),
         {:ok, premium} <- UwBilling.Billing.get_plan_by_tier(:premium) do
      UwBilling.Billing.update_plan(pro, %{stripe_price_id: price_id_pro})
      UwBilling.Billing.update_plan(premium, %{stripe_price_id: price_id_premium})
    else
      error -> Logger.warning("Could not sync plan price IDs: #{inspect(error)}")
    end
  end

  # Creates a Stripe customer for the demo user, attaches the standard Stripe
  # test payment method so that `stripe trigger` can create subscriptions
  # against it, and stores the customer ID for webhook matching.
  defp provision_demo_customer(secret_key) do
    with {:ok, [user | _]} <- UwBilling.Accounts.list_users(),
         {:ok, customer}   <- Stripe.Customer.create(%{email: to_string(user.email)}, api_key: secret_key),
         {:ok, pm}         <- Stripe.PaymentMethod.attach(
                                "pm_card_visa",
                                %{customer: customer.id},
                                api_key: secret_key
                              ),
         {:ok, _customer}  <- Stripe.Customer.update(
                                customer.id,
                                %{invoice_settings: %{default_payment_method: pm.id}},
                                api_key: secret_key
                              ),
         {:ok, _updated}   <- UwBilling.Accounts.update_user(user, %{stripe_customer_id: customer.id}) do
      customer.id
    else
      error ->
        Logger.warning("Could not provision Stripe demo customer: #{inspect(error)}")
        nil
    end
  end

  defp mask(nil), do: nil
  defp mask(""), do: ""

  defp mask(str) when byte_size(str) <= 8 do
    String.duplicate("*", byte_size(str))
  end

  defp mask(str) do
    visible = String.slice(str, 0, 7)
    "#{visible}***"
  end
end
