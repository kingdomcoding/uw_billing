defmodule UwBillingWeb.BillingController do
  use UwBillingWeb, :controller

  def list_plans(conn, _params) do
    case UwBilling.Billing.list_plans() do
      {:ok, plans} -> json(conn, Enum.map(plans, &serialize_plan/1))
      {:error, _} -> json(conn, [])
    end
  end

  def subscription(conn, _params) do
    case UwBilling.Billing.get_active_subscription(conn.assigns.current_user_id) do
      {:ok, sub} -> json(conn, serialize_subscription(sub))
      {:error, _} -> json(conn, nil)
    end
  end

  def invoices(conn, _params) do
    case UwBilling.Billing.get_active_subscription(conn.assigns.current_user_id) do
      {:ok, sub} when not is_nil(sub) ->
        case UwBilling.Billing.get_invoices_for_subscription(sub.id) do
          {:ok, invs} -> json(conn, Enum.map(invs, &serialize_invoice/1))
          {:error, _} -> json(conn, [])
        end

      _ ->
        json(conn, [])
    end
  end

  def change_plan(conn, %{"plan_id" => plan_id} = params) do
    immediate = Map.get(params, "immediate", false)

    with {:ok, sub} <- UwBilling.Billing.get_active_subscription(conn.assigns.current_user_id),
         {:ok, updated} <- UwBilling.Billing.change_plan(sub, plan_id, immediate) do
      json(conn, serialize_subscription(updated))
    else
      {:error, error} ->
        conn |> put_status(422) |> json(%{error: inspect(error)})
    end
  end

  def pause(conn, _params) do
    with {:ok, sub} <- UwBilling.Billing.get_active_subscription(conn.assigns.current_user_id),
         {:ok, updated} <- UwBilling.Billing.pause_subscription(sub) do
      json(conn, serialize_subscription(updated))
    else
      {:error, error} ->
        conn |> put_status(422) |> json(%{error: inspect(error)})
    end
  end

  def resume(conn, _params) do
    with {:ok, sub} <- UwBilling.Billing.get_active_subscription(conn.assigns.current_user_id),
         {:ok, updated} <- UwBilling.Billing.resume_subscription(sub) do
      json(conn, serialize_subscription(updated))
    else
      {:error, error} ->
        conn |> put_status(422) |> json(%{error: inspect(error)})
    end
  end

  def cancel(conn, _params) do
    with {:ok, sub} <- UwBilling.Billing.get_active_subscription(conn.assigns.current_user_id),
         {:ok, _} <- UwBilling.Billing.cancel_subscription(sub) do
      send_resp(conn, 204, "")
    else
      {:error, error} ->
        conn |> put_status(422) |> json(%{error: inspect(error)})
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
    %{
      id: sub.id,
      status: sub.status,
      plan_id: sub.plan_id,
      plan: if(sub.plan, do: serialize_plan(sub.plan), else: nil),
      scheduled_plan_id: sub.scheduled_plan_id,
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
