defmodule UwBilling.Billing.Changes.SyncWithStripe do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn cs ->
      subscription = cs.data

      case sync(subscription) do
        {:ok, updates} ->
          Enum.reduce(updates, cs, fn {k, v}, acc ->
            Ash.Changeset.force_change_attribute(acc, k, v)
          end)

        {:error, _reason} ->
          cs
      end
    end)
  end

  defp sync(%{stripe_subscription_id: nil}), do: {:ok, []}

  defp sync(subscription) do
    secret_key = UwBilling.StripeClient.secret_key()

    with {:ok, stripe_sub} <- Stripe.Subscription.retrieve(subscription.stripe_subscription_id, %{}, [api_key: secret_key]) do
      updates = build_updates(stripe_sub)
      {:ok, updates}
    end
  rescue
    _ -> {:error, :stripe_error}
  end

  defp build_updates(stripe_sub) do
    status = map_stripe_status(stripe_sub.status)

    period_end =
      case stripe_sub.current_period_end do
        nil -> nil
        ts -> DateTime.from_unix!(ts)
      end

    period_start =
      case stripe_sub.current_period_start do
        nil -> nil
        ts -> DateTime.from_unix!(ts)
      end

    [
      status: status,
      current_period_end: period_end,
      current_period_start: period_start
    ]
  end

  defp map_stripe_status("active"), do: :active
  defp map_stripe_status("trialing"), do: :trialing
  defp map_stripe_status("past_due"), do: :past_due
  defp map_stripe_status("canceled"), do: :canceled
  defp map_stripe_status("paused"), do: :paused
  defp map_stripe_status("unpaid"), do: :past_due
  defp map_stripe_status(_), do: :active
end
