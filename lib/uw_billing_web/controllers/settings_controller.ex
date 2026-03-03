defmodule UwBillingWeb.SettingsController do
  use UwBillingWeb, :controller

  require Logger

  def setup_status(conn, _params) do
    configured = UwBilling.StripeClient.configured?()

    has_subscription =
      case UwBilling.Accounts.list_users() do
        {:ok, [user | _]} ->
          case UwBilling.Billing.get_active_subscription(user.id) do
            {:ok, [_ | _]} -> true
            _              -> false
          end
        _ -> false
      end

    json(conn, %{configured: configured, has_subscription: has_subscription})
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
        custom_configured = config.enabled and config.user_provided

        json(conn, %{
          env_configured: env_configured,
          custom_configured: custom_configured,
          configured: custom_configured || env_configured,
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
      "secret_key"     => secret_key,
      "webhook_secret" => webhook_secret
    } = params

    errors = validate_credentials(secret_key, webhook_secret)

    if map_size(errors) == 0 do
      {price_id_pro, price_id_premium} =
        case reuse_existing_prices(secret_key) do
          {:ok, pro, premium} -> {pro, premium}
          :provision ->
            case provision_stripe_prices(secret_key) do
              {:ok, pro, premium} -> {pro, premium}
              {:error, err} ->
                conn |> put_status(422) |> json(%{error: "Failed to create Stripe prices: #{err}"})
                throw(:responded)
            end
        end

      case UwBilling.Config.save_user_provided_stripe_config(%{
             secret_key:       secret_key,
             webhook_secret:   webhook_secret,
             price_id_pro:     price_id_pro,
             price_id_premium: price_id_premium,
             verified_at:      DateTime.utc_now()
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
  catch
    :responded -> conn
  end

  def disable_stripe(conn, _params) do
    case UwBilling.Config.get_stripe_config_any() do
      {:ok, config} when not is_nil(config) ->
        case UwBilling.Config.disable_stripe_config(config) do
          {:ok, _}    -> :ok
          {:error, e} -> Logger.warning("disable_stripe_config failed: #{inspect(e)}")
        end

      _ ->
        :ok
    end

    json(conn, %{configured: env_configured?()})
  end

  def demo_subscribe(conn, _params) do
    secret_key = UwBilling.StripeClient.secret_key()
    price_id   = UwBilling.StripeClient.price_id(:pro)

    # If price IDs are missing (env-only key/webhook, no prior verify_stripe),
    # provision products/prices now and save them to the DB config.
    price_id =
      if is_nil(price_id) or price_id == "" do
        case provision_stripe_prices(secret_key) do
          {:ok, pro_id, premium_id} ->
            sync_plan_price_ids(pro_id, premium_id)
            webhook_secret = UwBilling.StripeClient.webhook_secret()
            UwBilling.Config.save_stripe_config(%{
              secret_key:       secret_key,
              webhook_secret:   webhook_secret,
              price_id_pro:     pro_id,
              price_id_premium: premium_id,
              verified_at:      DateTime.utc_now()
            })
            pro_id
          {:error, _} -> nil
        end
      else
        price_id
      end

    # Ensure the demo customer exists in Stripe (may be missing on env-only first run)
    provision_demo_customer(secret_key)

    with {:ok, [user | _]} <- UwBilling.Accounts.list_users(),
         true              <- not is_nil(user.stripe_customer_id),
         false             <- is_nil(price_id),
         {:ok, _sub}       <- Stripe.Subscription.create(
                                %{
                                  customer: user.stripe_customer_id,
                                  items: [%{price: price_id}]
                                },
                                api_key: secret_key
                              ) do
      %{} |> UwBilling.Workers.CongressTradePoller.new() |> Oban.insert()
      json(conn, %{ok: true})
    else
      false ->
        conn |> put_status(422) |> json(%{error: "No Stripe customer provisioned — save credentials first"})
      true ->
        conn |> put_status(422) |> json(%{error: "Could not resolve Stripe price ID"})
      {:error, %Stripe.Error{} = err} ->
        conn |> put_status(422) |> json(%{error: err.message})
      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: inspect(reason)})
    end
  end

  defp validate_credentials(secret_key, webhook_secret) do
    errors = %{}

    errors =
      case Stripe.Balance.retrieve(%{}, api_key: secret_key) do
        {:ok, _}    -> errors
        {:error, _} -> Map.put(errors, "secret_key", "Invalid secret key — could not connect to Stripe")
      end

    errors =
      if String.starts_with?(webhook_secret, "whsec_") do
        errors
      else
        Map.put(errors, "webhook_secret", "Must start with whsec_")
      end

    errors
  end

  defp reuse_existing_prices(secret_key) do
    case UwBilling.Config.get_stripe_config_any() do
      {:ok, config}
      when not is_nil(config) and
           not is_nil(config.price_id_pro) and
           not is_nil(config.price_id_premium) ->
        stored_prefix = String.slice(config.secret_key || "", 0, 12)
        incoming_prefix = String.slice(secret_key, 0, 12)

        if stored_prefix == incoming_prefix do
          {:ok, config.price_id_pro, config.price_id_premium}
        else
          :provision
        end

      _ ->
        :provision
    end
  end

  defp provision_stripe_prices(secret_key) do
    with {:ok, pro_product}     <- Stripe.Product.create(%{name: "Pro"}, api_key: secret_key),
         {:ok, pro_price}       <- Stripe.Price.create(
                                     %{unit_amount: 4900, currency: "usd",
                                       recurring: %{interval: "month"}, product: pro_product.id},
                                     api_key: secret_key
                                   ),
         {:ok, premium_product} <- Stripe.Product.create(%{name: "Premium"}, api_key: secret_key),
         {:ok, premium_price}   <- Stripe.Price.create(
                                     %{unit_amount: 9900, currency: "usd",
                                       recurring: %{interval: "month"}, product: premium_product.id},
                                     api_key: secret_key
                                   ) do
      {:ok, pro_price.id, premium_price.id}
    else
      {:error, %Stripe.Error{} = err} -> {:error, err.message}
      {:error, reason}                -> {:error, inspect(reason)}
    end
  end

  defp sync_plan_price_ids(price_id_pro, price_id_premium) do
    with {:ok, pro}     <- UwBilling.Billing.get_plan_by_tier(:pro),
         {:ok, premium} <- UwBilling.Billing.get_plan_by_tier(:premium) do
      UwBilling.Billing.update_plan(pro, %{stripe_price_id: price_id_pro})
      UwBilling.Billing.update_plan(premium, %{stripe_price_id: price_id_premium})
    else
      error -> Logger.warning("Could not sync plan price IDs: #{inspect(error)}")
    end
  end

  defp provision_demo_customer(secret_key) do
    with {:ok, [user | _]} <- UwBilling.Accounts.list_users() do
      if user.stripe_customer_id do
        user.stripe_customer_id
      else
        create_stripe_customer(user, secret_key)
      end
    else
      error ->
        Logger.warning("Could not fetch demo user: #{inspect(error)}")
        nil
    end
  end

  defp create_stripe_customer(user, secret_key) do
    with {:ok, customer}  <- Stripe.Customer.create(%{email: to_string(user.email)}, api_key: secret_key),
         {:ok, pm}        <- Stripe.PaymentMethod.attach(
                               "pm_card_visa",
                               %{customer: customer.id},
                               api_key: secret_key
                             ),
         {:ok, _customer} <- Stripe.Customer.update(
                               customer.id,
                               %{invoice_settings: %{default_payment_method: pm.id}},
                               api_key: secret_key
                             ),
         {:ok, _updated}  <- UwBilling.Accounts.update_user(user, %{stripe_customer_id: customer.id}) do
      customer.id
    else
      error ->
        Logger.warning("Could not provision Stripe demo customer: #{inspect(error)}")
        nil
    end
  end

  def show_uw(conn, _params) do
    configured =
      case UwBilling.Config.get_app_config() do
        {:ok, %{uw_api_key: key}} when is_binary(key) and byte_size(key) > 0 -> true
        _ -> false
      end

    json(conn, %{
      configured: configured,
      env_configured: not is_nil(System.get_env("UW_API_KEY"))
    })
  end

  def save_uw(conn, %{"uw_api_key" => key}) when byte_size(key) > 0 do
    case UwBilling.Config.save_app_config(%{uw_api_key: key}) do
      {:ok, _} -> json(conn, %{ok: true})
      {:error, _} -> conn |> put_status(422) |> json(%{error: "Failed to save key"})
    end
  end

  def save_uw(conn, _params) do
    conn |> put_status(422) |> json(%{error: "uw_api_key required"})
  end

  def clear_uw(conn, _params) do
    case UwBilling.Config.get_app_config() do
      {:ok, config} -> UwBilling.Config.clear_uw_api_key(config)
      _ -> :ok
    end

    json(conn, %{ok: true})
  end

  defp env_configured? do
    [
      System.get_env("STRIPE_SECRET_KEY"),
      System.get_env("STRIPE_WEBHOOK_SECRET")
    ]
    |> Enum.all?(&(not is_nil(&1) and &1 != ""))
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
