defmodule UwBilling.Billing.SubscriptionTest do
  use UwBilling.DataCase, async: true

  alias UwBilling.{Accounts, Billing}

  setup do
    {:ok, user} = Accounts.create_user(%{email: "sub_#{System.unique_integer([:positive])}@example.com"})

    {:ok, plan} = Billing.create_plan(%{
      name: "Pro",
      tier: :pro,
      amount_cents: 4900,
      interval: "month",
      api_request_limit: 100_000
    })

    {:ok, sub} = Billing.create_subscription(%{user_id: user.id, plan_id: plan.id})

    %{user: user, plan: plan, sub: sub}
  end

  describe "initial state" do
    test "new subscription starts as :free", %{sub: sub} do
      assert sub.status == :free
    end
  end

  describe "start_trial/1" do
    test "transitions :free → :trialing", %{sub: sub} do
      assert {:ok, trialing} = Billing.start_trial(sub)
      assert trialing.status == :trialing
    end

    test "cannot transition from :active", %{sub: sub} do
      {:ok, active} = Billing.activate_subscription(sub, %{})
      assert {:error, _} = Billing.start_trial(active)
    end
  end

  describe "activate_subscription/2" do
    test "transitions :free → :active", %{sub: sub} do
      assert {:ok, active} = Billing.activate_subscription(sub, %{})
      assert active.status == :active
    end

    test "transitions :trialing → :active", %{sub: sub} do
      {:ok, trialing} = Billing.start_trial(sub)
      assert {:ok, active} = Billing.activate_subscription(trialing, %{})
      assert active.status == :active
    end

    test "transitions :past_due → :active", %{sub: sub} do
      {:ok, active} = Billing.activate_subscription(sub, %{})
      {:ok, past_due} = Billing.fail_payment(active)
      assert {:ok, recovered} = Billing.activate_subscription(past_due, %{})
      assert recovered.status == :active
    end
  end

  describe "fail_payment/1" do
    test "transitions :active → :past_due and stamps past_due_since", %{sub: sub} do
      {:ok, active} = Billing.activate_subscription(sub, %{})
      assert {:ok, past_due} = Billing.fail_payment(active)
      assert past_due.status == :past_due
      assert past_due.past_due_since != nil
    end

    test "cannot transition from :free", %{sub: sub} do
      assert {:error, _} = Billing.fail_payment(sub)
    end
  end

  describe "recover_payment/1" do
    test "transitions :past_due → :active and clears past_due_since", %{sub: sub} do
      {:ok, active} = Billing.activate_subscription(sub, %{})
      {:ok, past_due} = Billing.fail_payment(active)
      assert {:ok, recovered} = Billing.recover_payment(past_due)
      assert recovered.status == :active
      assert recovered.past_due_since == nil
    end
  end

  describe "cancel_subscription/1" do
    test "transitions :active → :canceled", %{sub: sub} do
      {:ok, active} = Billing.activate_subscription(sub, %{})
      assert {:ok, canceled} = Billing.cancel_subscription(active)
      assert canceled.status == :canceled
    end

    test "canceled is terminal — cannot activate", %{sub: sub} do
      {:ok, active} = Billing.activate_subscription(sub, %{})
      {:ok, canceled} = Billing.cancel_subscription(active)
      assert {:error, _} = Billing.activate_subscription(canceled, %{})
    end

    test "can cancel from :free", %{sub: sub} do
      assert {:ok, canceled} = Billing.cancel_subscription(sub)
      assert canceled.status == :canceled
    end
  end

  describe "pause_subscription/1 and resume_subscription/1" do
    test "pause → resume round trip", %{sub: sub} do
      {:ok, active} = Billing.activate_subscription(sub, %{})
      assert {:ok, paused} = Billing.pause_subscription(active)
      assert paused.status == :paused
      assert {:ok, resumed} = Billing.resume_subscription(paused)
      assert resumed.status == :active
    end

    test "cannot pause from :free", %{sub: sub} do
      assert {:error, _} = Billing.pause_subscription(sub)
    end
  end

  describe "change_plan/3" do
    test "immediate=true swaps plan_id at once", %{sub: sub} do
      {:ok, premium} = Billing.create_plan(%{name: "Premium", tier: :premium, amount_cents: 9900, interval: "month"})
      {:ok, active} = Billing.activate_subscription(sub, %{})
      assert {:ok, changed} = Billing.change_plan(active, premium.id, true)
      assert changed.plan_id == premium.id
      assert changed.scheduled_plan_id == nil
    end

    test "immediate=false sets scheduled_plan_id without changing plan_id", %{sub: sub, plan: plan} do
      {:ok, premium} = Billing.create_plan(%{name: "Premium", tier: :premium, amount_cents: 9900, interval: "month"})
      {:ok, active} = Billing.activate_subscription(sub, %{})
      assert {:ok, changed} = Billing.change_plan(active, premium.id, false)
      assert changed.plan_id == plan.id
      assert changed.scheduled_plan_id == premium.id
    end
  end
end
