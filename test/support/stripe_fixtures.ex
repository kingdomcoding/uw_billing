defmodule UwBilling.StripeFixtures do
  def subscription_created(overrides \\ %{}) do
    Map.merge(%{
      "id"                   => "sub_test_#{:rand.uniform(999_999)}",
      "object"               => "subscription",
      "customer"             => "cus_test_123",
      "status"               => "active",
      "current_period_start" => DateTime.to_unix(DateTime.utc_now()),
      "current_period_end"   => DateTime.to_unix(DateTime.add(DateTime.utc_now(), 30 * 86_400)),
      "trial_end"            => nil,
      "cancel_at_period_end" => false,
      "items"                => %{"data" => [%{"price" => %{"id" => "price_test_pro_monthly"}}]}
    }, overrides)
  end

  def subscription_deleted(id),          do: %{"id" => id, "status" => "canceled"}
  def invoice_payment_failed(sub_id),    do: %{"id" => "in_#{:rand.uniform(999_999)}", "subscription" => sub_id, "status" => "open"}
  def invoice_payment_succeeded(sub_id), do: %{"id" => "in_#{:rand.uniform(999_999)}", "subscription" => sub_id, "status" => "paid", "amount_paid" => 4900}
end
