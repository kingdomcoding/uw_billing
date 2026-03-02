defmodule UwBilling.StripeClient do
  def secret_key, do: db_config(:secret_key) || System.get_env("STRIPE_SECRET_KEY")
  def webhook_secret, do: db_config(:webhook_secret) || System.get_env("STRIPE_WEBHOOK_SECRET")
  def price_id(:pro), do: db_config(:price_id_pro) || System.get_env("STRIPE_PRICE_PRO_MONTHLY")
  def price_id(:premium), do: db_config(:price_id_premium) || System.get_env("STRIPE_PRICE_PREMIUM_MONTHLY")

  def configured? do
    [secret_key(), webhook_secret()]
    |> Enum.all?(&(not blank?(&1)))
  end

  defp db_config(field) do
    case UwBilling.Config.get_stripe_config() do
      {:ok, %{^field => value}} when not is_nil(value) and value != "" -> value
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end
