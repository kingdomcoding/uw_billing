const BASE = "/api"

export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly body: Record<string, unknown> | null
  ) {
    super((body?.error as string) ?? `API error: ${status}`)
    this.name = "ApiError"
  }
}

// ── Usage types ─────────────────────────────────────────────────────────────
export interface DailyCount    { date: string; total: number; errors: number }
export interface EndpointCount { endpoint: string; total: number }
export interface MonthlySummary {
  count: number; limit: number | null; usage_pct: number | null
  plan_tier: string; near_limit: boolean; plan_unlimited: boolean
}
export interface Latency { p50: number; p95: number }

// ── Billing types ───────────────────────────────────────────────────────────
export interface Plan {
  id: string; name: string; tier: string
  amount_cents: number; interval: string | null
  api_request_limit: number | null; features: Record<string, unknown>
}
export interface SubscriptionInfo {
  id: string; status: string; plan: Plan
  current_period_start: string; current_period_end: string
  trial_end: string | null; cancel_at_period_end: boolean
  scheduled_plan: Plan | null
}
export interface Invoice {
  id: string; stripe_invoice_id: string; amount_cents: number
  status: string; paid_at: string | null; inserted_at: string
}

// ── Account types ───────────────────────────────────────────────────────────
export interface AccountInfo { email: string; api_key: string }

// ── UW config types ─────────────────────────────────────────────────────────
export interface UwConfigStatus {
  configured: boolean
  env_configured: boolean
}

// ── Settings types ──────────────────────────────────────────────────────────
export interface StripeConfigStatus {
  env_configured: boolean
  custom_configured: boolean
  configured: boolean
  secret_key?: string
  webhook_secret?: string
  price_id_pro?: string
  price_id_premium?: string
  verified_at?: string
}
export interface StripeCredentials {
  secret_key: string
  webhook_secret: string
}
export type StripeVerifyResult =
  | { configured: true; stripe_customer_id: string | null; price_id_pro: string }
  | { errors: Record<string, string> }

// ── Congress types ──────────────────────────────────────────────────────────
export interface CongressTrade {
  id: string
  trader_name: string
  ticker: string
  transaction_type: "purchase" | "sale" | "exchange"
  amount_range: string | null
  filed_at: string | null
  traded_at: string | null
  inserted_at: string
  politician_id: string | null
  issuer: "self" | "spouse" | "joint" | "child" | "undisclosed" | null
  member_type: "house" | "senate" | null
}
export interface CongressSummary { ticker: string; trades: number; latest_filed: string }

// ── HTTP helpers ────────────────────────────────────────────────────────────

function apiKey(): string {
  return localStorage.getItem("uw_api_key") ?? ""
}

async function get<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    headers: { Accept: "application/json", "X-Api-Key": apiKey() }
  })
  if (!res.ok) {
    let body: Record<string, unknown> | null = null
    try { body = await res.json() } catch {}
    throw new ApiError(res.status, body)
  }
  return res.json() as Promise<T>
}

async function post<T>(path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Api-Key": apiKey() },
    body: body ? JSON.stringify(body) : undefined
  })
  if (!res.ok) {
    let b: Record<string, unknown> | null = null
    try { b = await res.json() } catch {}
    throw new ApiError(res.status, b)
  }
  return res.json() as Promise<T>
}

async function del(path: string): Promise<void> {
  const res = await fetch(`${BASE}${path}`, {
    method: "DELETE",
    headers: { "X-Api-Key": apiKey() }
  })
  if (!res.ok && res.status !== 204) {
    let body: Record<string, unknown> | null = null
    try { body = await res.json() } catch {}
    throw new ApiError(res.status, body)
  }
}

async function publicGet<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE}${path}`, { headers: { Accept: "application/json" } })
  if (!res.ok) {
    let body: Record<string, unknown> | null = null
    try { body = await res.json() } catch {}
    throw new ApiError(res.status, body)
  }
  return res.json() as Promise<T>
}

async function publicPost<T>(path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) {
    let b: Record<string, unknown> | null = null
    try { b = await res.json() } catch {}
    throw new ApiError(res.status, b)
  }
  return res.json() as Promise<T>
}

async function publicDel(path: string): Promise<void> {
  const res = await fetch(`${BASE}${path}`, { method: "DELETE", headers: { Accept: "application/json" } })
  if (!res.ok && res.status !== 204) {
    let body: Record<string, unknown> | null = null
    try { body = await res.json() } catch {}
    throw new ApiError(res.status, body)
  }
}

export const api = {
  dailyCounts:    (days = 30) => get<DailyCount[]>(`/usage/daily?days=${days}`),
  byEndpoint:     ()          => get<EndpointCount[]>("/usage/by_endpoint"),
  monthlySummary: ()          => get<MonthlySummary>("/usage/monthly_summary"),
  latency:        (days = 7)  => get<Latency>(`/usage/latency?days=${days}`),

  listPlans:  ()                       => get<Plan[]>("/plans"),
  subscription: ()                     => get<SubscriptionInfo | null>("/subscription"),
  invoices:   ()                       => get<Invoice[]>("/invoices"),
  subscribe:  (plan_id: string) => post<void>("/billing/subscribe", { plan_id }),
  changePlan: (plan_id: string, immediate: boolean) =>
                post<SubscriptionInfo>("/subscription/change_plan", { plan_id, immediate }),
  pauseSub:   () => post<SubscriptionInfo>("/subscription/pause"),
  resumeSub:  () => post<SubscriptionInfo>("/subscription/resume"),
  cancelSub:  () => del("/subscription"),

  account: () => get<AccountInfo>("/account"),

  demoSession:  ()                         => publicGet<{ api_key: string; email: string }>("/setup/session"),
  stripeConfig: ()                         => publicGet<StripeConfigStatus>("/setup/stripe"),
  verifyStripe: (creds: StripeCredentials) => publicPost<StripeVerifyResult>("/setup/stripe/verify", creds),
  disableStripe: ()                        => publicDel("/setup/stripe"),
  demoSubscribe:      ()  => publicPost<{ ok: boolean }>("/setup/subscribe"),
  seedDemoInvoices:   ()  => post<Invoice[]>("/billing/seed_demo_invoices"),

  recentTrades:   (limit = 20)        => get<CongressTrade[]>(`/congress/recent?limit=${limit}`),
  tradesByTicker: (ticker: string)    => get<CongressTrade[]>(`/congress/ticker/${ticker}`),
  tradeSummary:   ()                  => get<CongressSummary[]>("/congress/summary"),
  searchTrades:   (q: string)         => get<CongressTrade[]>(`/congress/search?q=${encodeURIComponent(q)}`),
  refreshTrades:  ()                  => post<{ ok: boolean }>("/congress/refresh"),

  uwConfig:   ()                        => publicGet<UwConfigStatus>("/setup/uw"),
  saveUwKey:  (uw_api_key: string)      => publicPost<{ ok: boolean }>("/setup/uw/save", { uw_api_key }),
  clearUwKey: ()                        => publicDel("/setup/uw"),
}
