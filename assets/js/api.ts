const BASE = "/api"

// ── Usage types ─────────────────────────────────────────────────────────────
export interface DailyCount    { date: string; total: number; errors: number }
export interface EndpointCount { endpoint: string; total: number }
export interface MonthlySummary {
  count: number; limit: number | null; usage_pct: number | null
  plan_tier: string; near_limit: boolean
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
}
export interface Invoice {
  id: string; stripe_invoice_id: string; amount_cents: number
  status: string; paid_at: string | null; inserted_at: string
}

// ── Account types ───────────────────────────────────────────────────────────
export interface AccountInfo { email: string; api_key: string }

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
  price_id_pro: string
  price_id_premium: string
}
export type StripeVerifyResult =
  | { configured: true; stripe_customer_id: string | null }
  | { errors: Record<string, string> }

// ── Congress types ──────────────────────────────────────────────────────────
export interface CongressTrade {
  id: string; trader_name: string; ticker: string
  transaction_type: string; amount_range: string | null
  traded_at: string | null; filed_at: string
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
  if (!res.ok) throw new Error(`API error: ${res.status}`)
  return await res.json() as T
}

async function post<T>(path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Api-Key": apiKey() },
    body: body ? JSON.stringify(body) : undefined
  })
  if (!res.ok) throw new Error(`API error: ${res.status}`)
  return await res.json() as T
}

async function del(path: string): Promise<void> {
  const res = await fetch(`${BASE}${path}`, {
    method: "DELETE",
    headers: { "X-Api-Key": apiKey() }
  })
  if (!res.ok && res.status !== 204) throw new Error(`API error: ${res.status}`)
}

async function publicGet<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE}${path}`, { headers: { Accept: "application/json" } })
  if (!res.ok) throw new Error(`API error: ${res.status}`)
  return await res.json() as T
}

async function publicPost<T>(path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) throw new Error(`API error: ${res.status}`)
  return await res.json() as T
}

async function publicDel(path: string): Promise<void> {
  const res = await fetch(`${BASE}${path}`, { method: "DELETE", headers: { Accept: "application/json" } })
  if (!res.ok && res.status !== 204) throw new Error(`API error: ${res.status}`)
}

export const api = {
  dailyCounts:    (days = 30) => get<DailyCount[]>(`/usage/daily?days=${days}`),
  byEndpoint:     ()          => get<EndpointCount[]>("/usage/by_endpoint"),
  monthlySummary: ()          => get<MonthlySummary>("/usage/monthly_summary"),
  latency:        ()          => get<Latency>("/usage/latency"),

  listPlans:  ()                       => get<Plan[]>("/plans"),
  subscription: ()                     => get<SubscriptionInfo | null>("/subscription"),
  invoices:   ()                       => get<Invoice[]>("/invoices"),
  changePlan: (plan_id: string, immediate: boolean) =>
                post<SubscriptionInfo>("/subscription/change_plan", { plan_id, immediate }),
  pauseSub:   () => post<SubscriptionInfo>("/subscription/pause"),
  resumeSub:  () => post<SubscriptionInfo>("/subscription/resume"),
  cancelSub:  () => del("/subscription"),

  account: () => get<AccountInfo>("/account"),

  setupStatus:  ()                         => publicGet<{ configured: boolean }>("/setup/status"),
  demoSession:  ()                         => publicGet<{ api_key: string; email: string }>("/setup/session"),
  stripeConfig: ()                         => publicGet<StripeConfigStatus>("/setup/stripe"),
  verifyStripe: (creds: StripeCredentials) => publicPost<StripeVerifyResult>("/setup/stripe/verify", creds),
  disableStripe: ()                        => publicDel("/setup/stripe"),

  recentTrades:   (limit = 20)        => get<CongressTrade[]>(`/congress/recent?limit=${limit}`),
  tradesByTicker: (ticker: string)    => get<CongressTrade[]>(`/congress/ticker/${ticker}`),
  tradeSummary:   ()                  => get<CongressSummary[]>("/congress/summary"),
}
