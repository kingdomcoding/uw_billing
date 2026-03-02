defmodule UwBillingWeb.WebhookController do
  use UwBillingWeb, :controller

  require Logger

  def stripe(conn, _params) do
    raw_body = conn.assigns[:raw_body] || ""
    sig_header = get_req_header(conn, "stripe-signature") |> List.first()
    webhook_secret = UwBilling.StripeClient.webhook_secret()

    case Stripe.Webhook.construct_event(raw_body, sig_header, webhook_secret) do
      {:ok, _event} ->
        # Signature verified. Parse the raw body directly — avoids needing
        # Jason.Encoder on %Stripe.Event{} and gives us string-keyed maps
        # that the worker expects (e.g. payload["customer"], payload["id"]).
        %{"id" => stripe_event_id, "type" => event_type} = event_map = Jason.decode!(raw_body)
        payload = get_in(event_map, ["data", "object"]) || %{}

        %{stripe_event_id: stripe_event_id, event_type: event_type, payload: payload}
        |> UwBilling.Workers.StripeWebhookWorker.new()
        |> Oban.insert()

        json(conn, %{ok: true})

      {:error, reason} ->
        Logger.warning("Stripe webhook signature verification failed: #{inspect(reason)}")

        conn
        |> put_status(400)
        |> json(%{error: "Invalid signature"})
    end
  end
end
