defmodule UwBillingWeb.Router do
  use UwBillingWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {UwBillingWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json", "json-api"]
    plug UwBillingWeb.Plugs.ApiUsageLogger
  end

  pipeline :authenticate_api_key do
    plug UwBillingWeb.Plugs.AuthenticateApiKey
    plug UwBillingWeb.Plugs.EnforceRateLimit
  end

  # ── Stripe webhooks (no auth — Stripe signature is the guard) ────────────
  scope "/webhooks", UwBillingWeb do
    pipe_through :api
    post "/stripe", WebhookController, :stripe
  end

  # ── Setup / Stripe config (no auth — only usable before API key exists) ─
  scope "/api/setup", UwBillingWeb do
    pipe_through :api
    get    "/status",         SettingsController, :setup_status
    get    "/session",        SettingsController, :demo_session
    get    "/stripe",         SettingsController, :show_stripe
    post   "/stripe/verify",  SettingsController, :verify_stripe
    delete "/stripe",         SettingsController, :disable_stripe
    post   "/subscribe",      SettingsController, :demo_subscribe
  end

  # ── API routes (all require X-Api-Key) ──────────────────────────────────
  scope "/api", UwBillingWeb do
    pipe_through [:api, :authenticate_api_key]

    get "/usage/daily",           UsageController, :daily
    get "/usage/by_endpoint",     UsageController, :by_endpoint
    get "/usage/monthly_summary", UsageController, :monthly_summary
    get "/usage/latency",         UsageController, :latency

    get    "/plans",                    BillingController, :list_plans
    get    "/subscription",             BillingController, :subscription
    get    "/invoices",                 BillingController, :invoices
    post   "/billing/subscribe",          BillingController, :subscribe
    post   "/billing/seed_demo_invoices", BillingController, :seed_demo_invoices
    post   "/subscription/change_plan", BillingController, :change_plan
    post   "/subscription/pause",       BillingController, :pause
    post   "/subscription/resume",      BillingController, :resume
    delete "/subscription",             BillingController, :cancel

    get "/congress/recent",         CongressController, :recent
    get "/congress/search",         CongressController, :search
    get "/congress/summary",        CongressController, :summary
    get "/congress/ticker/:ticker", CongressController, :by_ticker

    get "/account", AccountController, :show

    get    "/settings/stripe",        SettingsController, :show_stripe
    post   "/settings/stripe/verify", SettingsController, :verify_stripe
    delete "/settings/stripe",        SettingsController, :disable_stripe
  end

  # ── AshJsonApi: JSON:API-compliant Plan + Subscription reads ────────────
  scope "/api" do
    pipe_through [:api, :authenticate_api_key]
    forward "/billing", UwBillingWeb.JsonApiRouter
  end

  # ── SPA catch-all: React Router handles all /dashboard, /billing, etc. ──
  scope "/", UwBillingWeb do
    pipe_through :browser
    get "/*path", PageController, :index
  end
end
