defmodule UwBillingWeb.SettingsController do
  use UwBillingWeb, :controller

  require Logger

  def setup_status(conn, _params) do
    json(conn, %{configured: UwBilling.StripeClient.configured?()})
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
          json(conn, %{configured: true})

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
