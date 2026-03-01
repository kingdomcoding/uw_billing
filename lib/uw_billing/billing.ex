defmodule UwBilling.Billing do
  use Ash.Domain

  resources do
    resource UwBilling.Billing.Plan do
      define :create_plan, action: :create
      define :update_plan, action: :update
      define :list_plans, action: :read
      define :get_plan_by_stripe_price, action: :by_stripe_price, args: [:stripe_price_id]
      define :get_plan_by_tier, action: :by_tier, args: [:tier]
    end

    resource UwBilling.Billing.Subscription do
      define :create_subscription, action: :create
      define :start_trial, action: :start_trial
      define :activate_subscription, action: :activate
      define :fail_payment, action: :fail_payment
      define :recover_payment, action: :recover_payment
      define :cancel_subscription, action: :cancel
      define :pause_subscription, action: :pause
      define :resume_subscription, action: :resume
      define :change_plan, action: :change_plan, args: [:plan_id, :immediate]
      define :apply_scheduled_plan, action: :apply_scheduled_plan
      define :sync_subscription_with_stripe, action: :sync_with_stripe
      define :get_active_subscription, action: :active_for_user, args: [:user_id]
      define :get_subscription_by_stripe_id, action: :by_stripe_id, args: [:stripe_subscription_id]
    end

    resource UwBilling.Billing.StripeEvent do
      define :record_stripe_event, action: :record
      define :list_stripe_events, action: :read
    end

    resource UwBilling.Billing.Invoice do
      define :upsert_invoice, action: :upsert
      define :mark_invoice_paid, action: :mark_paid
      define :void_invoice, action: :void
      define :get_invoices_for_subscription, action: :for_subscription, args: [:subscription_id]
      define :list_invoices, action: :read
    end
  end
end
