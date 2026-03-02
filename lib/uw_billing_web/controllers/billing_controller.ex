defmodule UwBillingWeb.BillingController do
  use UwBillingWeb, :controller

  require Logger

  def list_plans(conn, _params) do
    case UwBilling.Billing.list_plans() do
      {:ok, plans} -> json(conn, Enum.map(plans, &serialize_plan/1))
      {:error, _} -> json(conn, [])
    end
  end

  def subscription(conn, _params) do
    case fetch_active_sub(conn) do
      {:ok, sub} -> json(conn, serialize_subscription(sub))
      {:error, _} -> json(conn, nil)
    end
  end

  def invoices(conn, _params) do
    case fetch_active_sub(conn) do
      {:ok, sub} ->
        case UwBilling.Billing.get_invoices_for_subscription(sub.id) do
          {:ok, invs} -> json(conn, Enum.map(invs, &serialize_invoice/1))
          {:error, _} -> json(conn, [])
        end

      {:error, _} ->
        json(conn, [])
    end
  end

  def change_plan(conn, %{"plan_id" => plan_id} = params) do
    immediate = Map.get(params, "immediate", false)

    with {:ok, sub} <- fetch_active_sub(conn),
         {:ok, updated} <- UwBilling.Billing.change_plan(sub, plan_id, immediate) do
      json(conn, serialize_subscription(updated))
    else
      {:error, error} ->
        conn |> put_status(422) |> json(%{error: inspect(error)})
    end
  end

  def subscribe(conn, %{"plan_id" => plan_id}) do
    user = conn.assigns.current_user

    with {:ok, plan}  <- Ash.get(UwBilling.Billing.Plan, plan_id, domain: UwBilling.Billing),
         cid          when not is_nil(cid) <- user.stripe_customer_id,
         price_id     when not is_nil(price_id) <- plan.stripe_price_id,
         api_key      when not is_nil(api_key) <- UwBilling.StripeClient.secret_key(),
         {:ok, _sub}  <- Stripe.Subscription.create(
                           %{customer: cid, items: [%{price: price_id}]},
                           api_key: api_key
                         ) do
      send_resp(conn, 202, "")
    else
      nil ->
        conn |> put_status(422) |> json(%{error: "Missing Stripe customer, price, or API key"})
      {:error, %Stripe.Error{} = err} ->
        conn |> put_status(422) |> json(%{error: err.message})
      {:error, error} ->
        conn |> put_status(422) |> json(%{error: inspect(error)})
    end
  end

  def pause(conn, _params) do
    with {:ok, sub}     <- fetch_active_sub(conn),
         {:ok, _}       <- stripe_set_pause(sub, true),
         {:ok, updated} <- UwBilling.Billing.pause_subscription(sub) do
      json(conn, serialize_subscription(updated))
    else
      {:error, error} ->
        conn |> put_status(422) |> json(%{error: inspect(error)})
    end
  end

  def resume(conn, _params) do
    with {:ok, sub}     <- fetch_active_sub(conn),
         {:ok, _}       <- stripe_set_pause(sub, false),
         {:ok, updated} <- UwBilling.Billing.resume_subscription(sub) do
      json(conn, serialize_subscription(updated))
    else
      {:error, error} ->
        conn |> put_status(422) |> json(%{error: inspect(error)})
    end
  end

  def cancel(conn, _params) do
    with {:ok, sub} <- fetch_active_sub(conn),
         {:ok, _} <- UwBilling.Billing.cancel_subscription(sub) do
      send_resp(conn, 204, "")
    else
      {:error, error} ->
        conn |> put_status(422) |> json(%{error: inspect(error)})
    end
  end

  defp stripe_set_pause(%{stripe_subscription_id: nil}, _pause?), do: {:ok, :noop}

  defp stripe_set_pause(%{stripe_subscription_id: sid}, true) do
    case UwBilling.StripeClient.secret_key() do
      nil -> {:ok, :noop}
      key ->
        Stripe.Subscription.update(
          sid,
          %{pause_collection: %{behavior: "void"}},
          api_key: key
        )
    end
  end

  defp stripe_set_pause(%{stripe_subscription_id: sid}, false) do
    case UwBilling.StripeClient.secret_key() do
      nil -> {:ok, :noop}
      key ->
        Stripe.Subscription.update(
          sid,
          %{pause_collection: ""},
          api_key: key
        )
    end
  end

  defp fetch_active_sub(conn) do
    case UwBilling.Billing.get_active_subscription(conn.assigns.current_user_id) do
      {:ok, [sub | _]} -> {:ok, sub}
      {:ok, []}        -> {:error, :no_subscription}
      {:error, _} = err -> err
    end
  end

  defp serialize_plan(plan) do
    %{
      id: plan.id,
      name: plan.name,
      tier: plan.tier,
      amount_cents: plan.amount_cents,
      interval: plan.interval,
      api_request_limit: plan.api_request_limit,
      features: plan.features,
      stripe_price_id: plan.stripe_price_id
    }
  end

  defp serialize_subscription(nil), do: nil

  defp serialize_subscription(sub) do
    scheduled_plan =
      case sub.scheduled_plan do
        %UwBilling.Billing.Plan{} = p -> serialize_plan(p)
        _ -> nil
      end

    %{
      id: sub.id,
      status: sub.status,
      plan_id: sub.plan_id,
      plan: if(sub.plan, do: serialize_plan(sub.plan), else: nil),
      scheduled_plan_id: sub.scheduled_plan_id,
      scheduled_plan: scheduled_plan,
      stripe_subscription_id: sub.stripe_subscription_id,
      current_period_start: sub.current_period_start,
      current_period_end: sub.current_period_end,
      trial_end: sub.trial_end,
      cancel_at_period_end: sub.cancel_at_period_end,
      past_due_since: sub.past_due_since
    }
  end

  defp serialize_invoice(inv) do
    %{
      id: inv.id,
      stripe_invoice_id: inv.stripe_invoice_id,
      amount_cents: inv.amount_cents,
      status: inv.status,
      due_date: inv.due_date,
      paid_at: inv.paid_at,
      inserted_at: inv.inserted_at
    }
  end
end
