defmodule UwBilling.Workers.StripeWebhookWorkerTest do
  use UwBilling.DataCase, async: false

  alias UwBilling.{Accounts, Billing}
  alias UwBilling.Workers.StripeWebhookWorker
  alias UwBilling.StripeFixtures

  @customer_id "cus_test_123"
  @price_id "price_test_pro_monthly"

  setup do
    {:ok, user} = Accounts.create_user(%{email: "whtest_#{System.unique_integer([:positive])}@example.com"})
    {:ok, user} = Accounts.update_user(user, %{stripe_customer_id: @customer_id})

    {:ok, plan} = Billing.create_plan(%{
      name: "Pro",
      tier: :pro,
      stripe_price_id: @price_id,
      amount_cents: 4900,
      interval: "month",
      api_request_limit: 100_000
    })

    %{user: user, plan: plan}
  end

  defp perform(event_id, event_type, payload) do
    StripeWebhookWorker.perform(%Oban.Job{
      args: %{
        "stripe_event_id" => event_id,
        "event_type"      => event_type,
        "payload"         => payload
      },
      attempt: 1
    })
  end

  describe "customer.subscription.created" do
    test "creates and activates subscription for a known customer", %{user: user} do
      fixture = StripeFixtures.subscription_created()

      assert :ok = perform("evt_c_#{System.unique_integer()}", "customer.subscription.created", fixture)

      {:ok, [sub]} = Billing.get_active_subscription(user.id)
      assert sub.status == :active
      assert sub.stripe_subscription_id == fixture["id"]
    end

    test "idempotency: second perform with same event_id returns :ok without error", %{} do
      fixture  = StripeFixtures.subscription_created()
      event_id = "evt_idem_#{System.unique_integer()}"

      assert :ok = perform(event_id, "customer.subscription.created", fixture)
      assert :ok = perform(event_id, "customer.subscription.created", fixture)
    end

    test "snoozes when Stripe customer not found in DB", %{} do
      fixture = StripeFixtures.subscription_created(%{"customer" => "cus_unknown_xyz"})

      result = perform("evt_unk_#{System.unique_integer()}", "customer.subscription.created", fixture)
      assert {:snooze, _} = result
    end
  end

  describe "customer.subscription.deleted" do
    test "cancels an existing active subscription", %{} do
      fixture = StripeFixtures.subscription_created()
      :ok = perform("evt_c_#{System.unique_integer()}", "customer.subscription.created", fixture)

      del = StripeFixtures.subscription_deleted(fixture["id"])
      assert :ok = perform("evt_d_#{System.unique_integer()}", "customer.subscription.deleted", del)

      {:ok, sub} = Billing.get_subscription_by_stripe_id(fixture["id"])
      assert sub.status == :canceled
    end

    test "no-op when subscription stripe_id is unknown", %{} do
      del = StripeFixtures.subscription_deleted("sub_nonexistent_000")
      assert :ok = perform("evt_noop_#{System.unique_integer()}", "customer.subscription.deleted", del)
    end
  end

  describe "invoice.payment_failed" do
    test "transitions active subscription to :past_due", %{} do
      fixture = StripeFixtures.subscription_created()
      :ok = perform("evt_c_#{System.unique_integer()}", "customer.subscription.created", fixture)

      failed = StripeFixtures.invoice_payment_failed(fixture["id"])
      assert :ok = perform("evt_pf_#{System.unique_integer()}", "invoice.payment_failed", failed)

      {:ok, sub} = Billing.get_subscription_by_stripe_id(fixture["id"])
      assert sub.status == :past_due
    end
  end

  describe "invoice.payment_succeeded" do
    test "recovers :past_due subscription back to :active", %{} do
      fixture = StripeFixtures.subscription_created()
      :ok = perform("evt_c_#{System.unique_integer()}", "customer.subscription.created", fixture)

      failed = StripeFixtures.invoice_payment_failed(fixture["id"])
      :ok = perform("evt_pf_#{System.unique_integer()}", "invoice.payment_failed", failed)

      succeeded = StripeFixtures.invoice_payment_succeeded(fixture["id"])
      assert :ok = perform("evt_ps_#{System.unique_integer()}", "invoice.payment_succeeded", succeeded)

      {:ok, sub} = Billing.get_subscription_by_stripe_id(fixture["id"])
      assert sub.status == :active
    end

    test "no-op when subscription is already :active (not :past_due)", %{} do
      fixture = StripeFixtures.subscription_created()
      :ok = perform("evt_c_#{System.unique_integer()}", "customer.subscription.created", fixture)

      succeeded = StripeFixtures.invoice_payment_succeeded(fixture["id"])
      assert :ok = perform("evt_ps_#{System.unique_integer()}", "invoice.payment_succeeded", succeeded)

      {:ok, sub} = Billing.get_subscription_by_stripe_id(fixture["id"])
      assert sub.status == :active
    end
  end
end
