defmodule UwBilling.Workers.StripeWebhookWorker do
  use Oban.Worker,
    queue: :billing,
    unique: [keys: [:stripe_event_id], period: :infinity],
    max_attempts: 5

  alias UwBilling.{Billing, Accounts}
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
    args: %{
      "stripe_event_id" => event_id,
      "event_type"      => event_type,
      "payload"         => payload
    },
    attempt: attempt
  }) do
    Logger.metadata(stripe_event_id: event_id, event_type: event_type)

    case Billing.record_stripe_event(%{
      stripe_event_id: event_id,
      event_type: event_type,
      payload: payload
    }) do
      {:ok, _} ->
        Logger.info("Processing Stripe event attempt=#{attempt}")
        dispatch(event_type, payload)

      {:error, %Ash.Error.Invalid{errors: [%{field: :stripe_event_id} | _]}} ->
        Logger.info("Skipping already-processed Stripe event")
        :ok

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  # ── Dispatch ─────────────────────────────────────────────────────────────

  defp dispatch("customer.subscription.created", payload) do
    with {:ok, user} <- find_user(payload["customer"]),
         {:ok, plan} <- find_plan(payload) do
      case Billing.create_subscription(%{
        user_id:                user.id,
        plan_id:                plan.id,
        stripe_subscription_id: payload["id"],
        stripe_customer_id:     payload["customer"],
        current_period_start:   parse_unix(extract_period_start(payload)),
        current_period_end:     parse_unix(extract_period_end(payload)),
        trial_end:              parse_unix(payload["trial_end"]),
        cancel_at_period_end:   payload["cancel_at_period_end"] || false
      }) do
        {:ok, sub} ->
          status = infer_initial_status(payload["status"], payload["trial_end"])
          transition_new_subscription(sub, status)

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    else
      {:error, :user_not_found} -> {:snooze, 30}
      {:error, :plan_not_found} -> {:error, "unknown Stripe price ID"}
    end
  end

  defp dispatch("customer.subscription.updated", payload) do
    with {:ok, sub}  <- find_subscription(payload["id"]),
         {:ok, plan} <- find_plan(payload) do
      new_status = infer_initial_status(payload["status"], payload["trial_end"])

      period_attrs = %{
        plan_id:              plan.id,
        current_period_start: parse_unix(extract_period_start(payload)),
        current_period_end:   parse_unix(extract_period_end(payload)),
        cancel_at_period_end: payload["cancel_at_period_end"] || false
      }

      result =
        case {sub.status, new_status} do
          {:active, :active} -> Billing.update_subscription_periods(sub, period_attrs)
          {s, s}             -> {:ok, sub}
          {_, :active}       -> Billing.activate_subscription(sub, period_attrs)
          {_, :past_due}     -> Billing.fail_payment(sub)
          {_, :canceled}     -> Billing.cancel_subscription(sub)
          {_, :paused}       -> Billing.pause_subscription(sub)
          {_, :trialing}     -> Billing.start_trial(sub)
          _                  -> {:ok, sub}
        end

      case result do
        {:ok, _}         -> :ok
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, :not_found} -> {:snooze, 30}
      {:error, reason}     -> {:error, inspect(reason)}
    end
  end

  defp dispatch("customer.subscription.deleted", payload) do
    case find_subscription(payload["id"]) do
      {:ok, sub}           -> Billing.cancel_subscription(sub) |> ok_or_error()
      {:error, :not_found} -> :ok
    end
  end

  defp dispatch("customer.subscription.paused", payload) do
    case find_subscription(payload["id"]) do
      {:ok, sub}           -> Billing.pause_subscription(sub) |> ok_or_error()
      {:error, :not_found} -> :ok
    end
  end

  defp dispatch("customer.subscription.resumed", payload) do
    case find_subscription(payload["id"]) do
      {:ok, sub}           -> Billing.resume_subscription(sub) |> ok_or_error()
      {:error, :not_found} -> :ok
    end
  end

  defp dispatch("invoice.payment_failed", %{"subscription" => nil}), do: :ok
  defp dispatch("invoice.payment_failed", payload) do
    case find_subscription(payload["subscription"]) do
      {:ok, sub}           -> Billing.fail_payment(sub) |> ok_or_error()
      {:error, :not_found} -> :ok
    end
  end

  defp dispatch("invoice.payment_succeeded", %{"subscription" => nil}), do: :ok
  defp dispatch("invoice.payment_succeeded", payload) do
    case find_subscription(payload["subscription"]) do
      {:ok, sub} ->
        if sub.status == :past_due do
          Billing.recover_payment(sub) |> ok_or_error()
        else
          :ok
        end

      {:error, :not_found} ->
        :ok
    end
  end

  defp dispatch("invoice.finalized", payload) do
    case find_subscription(payload["subscription"]) do
      {:ok, sub} ->
        Billing.upsert_invoice(%{
          stripe_invoice_id: payload["id"],
          subscription_id:   sub.id,
          amount_cents:      payload["amount_due"] || 0,
          status:            :open,
          due_date:          parse_date(payload["due_date"])
        }) |> ok_or_error()

      {:error, :not_found} ->
        :ok
    end
  end

  defp dispatch("invoice.paid", payload) do
    with {:ok, sub}     <- find_subscription(payload["subscription"]),
         {:ok, invoice} <- Billing.upsert_invoice(%{
           stripe_invoice_id: payload["id"],
           subscription_id:   sub.id,
           amount_cents:      payload["amount_paid"] || 0,
           status:            :open
         }) do
      Billing.mark_invoice_paid(invoice) |> ok_or_error()
    else
      {:error, :not_found} -> :ok
      {:error, reason}     -> {:error, inspect(reason)}
    end
  end

  defp dispatch(type, _payload) do
    Logger.debug("Unhandled Stripe event type=#{type}")
    :ok
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp transition_new_subscription(sub, :active),  do: Billing.activate_subscription(sub, %{}) |> ok_or_error()
  defp transition_new_subscription(sub, :trialing), do: Billing.start_trial(sub) |> ok_or_error()
  defp transition_new_subscription(sub, :past_due), do: Billing.fail_payment(sub) |> ok_or_error()
  defp transition_new_subscription(sub, :canceled), do: Billing.cancel_subscription(sub) |> ok_or_error()
  defp transition_new_subscription(_sub, _),        do: :ok

  defp find_user(customer_id) do
    case Accounts.get_user_by_stripe_customer(customer_id) do
      {:ok, nil}  -> {:error, :user_not_found}
      {:ok, user} -> {:ok, user}
      {:error, _} -> {:error, :user_not_found}
    end
  end

  defp find_subscription(nil), do: {:error, :not_found}
  defp find_subscription(stripe_id) do
    case Billing.get_subscription_by_stripe_id(stripe_id) do
      {:ok, nil}  -> {:error, :not_found}
      {:ok, sub}  -> {:ok, sub}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp find_plan(%{"items" => %{"data" => [%{"price" => %{"id" => price_id}} | _]}}) do
    case Billing.get_plan_by_stripe_price(price_id) do
      {:ok, nil}   -> {:error, :plan_not_found}
      {:ok, plan}  -> {:ok, plan}
      {:error, _}  -> {:error, :plan_not_found}
    end
  end
  defp find_plan(_), do: {:error, :plan_not_found}

  defp infer_initial_status("trialing", _),                              do: :trialing
  defp infer_initial_status(_, trial_end) when not is_nil(trial_end),   do: :trialing
  defp infer_initial_status("active",   _),                              do: :active
  defp infer_initial_status("past_due", _),                              do: :past_due
  defp infer_initial_status("canceled", _),                              do: :canceled
  defp infer_initial_status("paused",   _),                              do: :paused
  defp infer_initial_status("unpaid",   _),                              do: :past_due
  defp infer_initial_status(_, _),                                       do: :active

  # Stripe API 2025+ moved current_period_start/end to items[0] in some event types.
  # Fall back to items when the top-level fields are absent.
  defp extract_period_start(%{"current_period_start" => ts}) when not is_nil(ts), do: ts
  defp extract_period_start(payload),
    do: get_in(payload, ["items", "data", Access.at(0), "current_period_start"])

  defp extract_period_end(%{"current_period_end" => ts}) when not is_nil(ts), do: ts
  defp extract_period_end(payload),
    do: get_in(payload, ["items", "data", Access.at(0), "current_period_end"])

  defp parse_unix(nil), do: nil
  defp parse_unix(ts) when is_integer(ts), do: DateTime.from_unix!(ts) |> DateTime.truncate(:second)

  defp parse_date(nil), do: nil
  defp parse_date(ts) when is_integer(ts), do: DateTime.from_unix!(ts) |> DateTime.to_date()

  defp ok_or_error({:ok, _}),         do: :ok
  defp ok_or_error({:error, reason}), do: {:error, inspect(reason)}
end
