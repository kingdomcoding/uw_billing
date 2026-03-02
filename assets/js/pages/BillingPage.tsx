import React, { useEffect, useState } from "react"
import { Link } from "react-router-dom"
import { api, Plan, SubscriptionInfo, Invoice } from "../api"
import StatusBadge from "../components/StatusBadge"

interface State {
  plans: Plan[]
  sub: SubscriptionInfo | null
  invoices: Invoice[]
  loading: boolean
  error: string | null
}

export default function BillingPage() {
  const [state, setState] = useState<State>({
    plans: [], sub: null, invoices: [], loading: true, error: null
  })
  const [acting, setActing] = useState<string | null>(null)

  const load = () =>
    Promise.all([api.listPlans(), api.subscription(), api.invoices()])
      .then(([plans, sub, invoices]) =>
        setState({ plans, sub, invoices, loading: false, error: null }))
      .catch(err => setState(s => ({ ...s, loading: false, error: (err as Error).message })))

  useEffect(() => { load() }, [])

  const doAction = async (key: string, fn: () => Promise<SubscriptionInfo | void>) => {
    setActing(key)
    try {
      await fn()
      await load()
    } catch (e) {
      setState(s => ({ ...s, error: (e as Error).message }))
    } finally {
      setActing(null)
    }
  }

  const fmt = (s: string | null) =>
    s ? new Date(s).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" }) : "—"

  if (state.loading) return <div className="p-8 text-gray-500">Loading...</div>
  if (state.error)   return <div className="p-8 text-red-500">Error: {state.error}</div>

  const { sub, invoices } = state
  const tiers = ["free", "pro", "premium"]
  const plans = [...state.plans].sort((a, b) => tiers.indexOf(a.tier) - tiers.indexOf(b.tier))

  return (
    <div className="space-y-10">
      <h1 className="text-2xl font-semibold text-gray-900">Billing</h1>

      {/* ── Current subscription ─────────────────────────────── */}
      <div className="bg-white rounded-lg border border-gray-200 p-6">
        {!sub ? (
          <div className="text-sm text-gray-500">
            No active subscription.{" "}
            <Link to="/setup" className="text-blue-600 underline">Complete setup</Link>
            {" "}to create one.
          </div>
        ) : (
          <div className="space-y-4">
            <div className="flex items-start justify-between gap-4">
              <div>
                <div className="text-lg font-semibold text-gray-900">{sub.plan.name} plan</div>
                <div className="text-sm text-gray-500 mt-0.5">
                  {sub.plan.amount_cents === 0
                    ? "Free"
                    : `$${(sub.plan.amount_cents / 100).toFixed(2)} / ${sub.plan.interval}`}
                  {" · "}
                  {fmt(sub.current_period_start)} – {fmt(sub.current_period_end)}
                </div>
                {sub.plan.api_request_limit && (
                  <div className="text-sm text-gray-500 mt-0.5">
                    {sub.plan.api_request_limit.toLocaleString()} API requests / month
                  </div>
                )}
              </div>
              <StatusBadge status={sub.status} />
            </div>

            {sub.trial_end && (
              <div className="text-sm text-amber-700 bg-amber-50 rounded px-3 py-2">
                Trial ends {fmt(sub.trial_end)}
              </div>
            )}
            {sub.cancel_at_period_end && (
              <div className="text-sm text-amber-700 bg-amber-50 rounded px-3 py-2">
                Cancels at end of current period ({fmt(sub.current_period_end)})
              </div>
            )}

            <div className="flex flex-wrap items-center gap-2 pt-3 border-t border-gray-100">
              {sub.status === "active" && (
                <button
                  disabled={!!acting}
                  onClick={() => doAction("pause", () => api.pauseSub())}
                  className="px-3 py-1.5 text-sm text-gray-700 border border-gray-200 rounded hover:bg-gray-50 disabled:opacity-50">
                  {acting === "pause" ? "Pausing..." : "Pause subscription"}
                </button>
              )}
              {sub.status === "paused" && (
                <button
                  disabled={!!acting}
                  onClick={() => doAction("resume", () => api.resumeSub())}
                  className="px-3 py-1.5 text-sm bg-green-600 text-white rounded hover:bg-green-700 disabled:opacity-50">
                  {acting === "resume" ? "Resuming..." : "Resume subscription"}
                </button>
              )}
              {sub.status !== "canceled" && !sub.cancel_at_period_end && (
                <button
                  disabled={!!acting}
                  onClick={() => {
                    if (confirm("Cancel your subscription? It will remain active until the end of the billing period."))
                      doAction("cancel", () => api.cancelSub())
                  }}
                  className="px-3 py-1.5 text-sm text-red-600 border border-red-200 rounded hover:bg-red-50 disabled:opacity-50 ml-auto">
                  Cancel subscription
                </button>
              )}
            </div>
          </div>
        )}
      </div>

      {/* ── Plans ─────────────────────────────────────────────── */}
      <div>
        <h2 className="text-base font-semibold text-gray-900 mb-4">Plans</h2>
        <div className="grid grid-cols-3 gap-4">
          {plans.map(plan => {
            const isCurrent = sub?.plan.id === plan.id
            const isUpgrade = !!sub && plan.amount_cents > sub.plan.amount_cents

            return (
              <div key={plan.id}
                className={`bg-white rounded-lg border p-5 flex flex-col gap-4 ${
                  isCurrent ? "border-blue-400 ring-1 ring-blue-400" : "border-gray-200"
                }`}>
                <div>
                  <div className="text-base font-semibold capitalize text-gray-900">{plan.name}</div>
                  <div className="text-2xl font-bold text-gray-900 mt-1">
                    {plan.amount_cents === 0 ? "Free" : `$${(plan.amount_cents / 100).toFixed(0)}`}
                    {plan.interval && (
                      <span className="text-sm font-normal text-gray-500"> /{plan.interval}</span>
                    )}
                  </div>
                </div>
                <ul className="text-sm text-gray-600 space-y-1 flex-1">
                  <li>
                    {plan.api_request_limit
                      ? `${plan.api_request_limit.toLocaleString()} requests / month`
                      : "Unlimited requests"}
                  </li>
                  {Object.entries(plan.features ?? {}).map(([k, v]) => (
                    <li key={k}>{String(v)}</li>
                  ))}
                </ul>
                {isCurrent ? (
                  <div className="text-sm text-blue-600 font-medium text-center py-1.5">
                    Current plan
                  </div>
                ) : (
                  <button
                    disabled={!!acting || !sub}
                    onClick={() =>
                      doAction(`plan-${plan.id}`, () => api.changePlan(plan.id, isUpgrade))
                    }
                    className={`w-full py-1.5 text-sm rounded disabled:opacity-50 ${
                      isUpgrade
                        ? "bg-blue-600 text-white hover:bg-blue-700"
                        : "border border-gray-300 text-gray-700 hover:bg-gray-50"
                    }`}>
                    {acting === `plan-${plan.id}`
                      ? "Switching..."
                      : isUpgrade ? "Upgrade →" : "Downgrade"}
                  </button>
                )}
              </div>
            )
          })}
        </div>
        <p className="text-xs text-gray-500 mt-3">
          Upgrades apply immediately and Stripe prorates the difference.
          Downgrades take effect at the end of the current billing period.
        </p>
      </div>

      {/* ── Invoice history ───────────────────────────────────── */}
      <div>
        <h2 className="text-base font-semibold text-gray-900 mb-4">Invoice History</h2>
        {invoices.length === 0 ? (
          <div className="bg-white rounded-lg border border-gray-200 p-6 text-sm text-gray-500">
            No invoices yet.
          </div>
        ) : (
          <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="text-left p-4 text-gray-500 font-medium">Invoice</th>
                  <th className="text-right p-4 text-gray-500 font-medium">Amount</th>
                  <th className="text-center p-4 text-gray-500 font-medium">Status</th>
                  <th className="text-right p-4 text-gray-500 font-medium">Date</th>
                </tr>
              </thead>
              <tbody>
                {invoices.map((inv, i) => (
                  <tr key={inv.id} className={i % 2 === 0 ? "bg-white" : "bg-gray-50"}>
                    <td className="p-4 font-mono text-xs text-gray-600">{inv.stripe_invoice_id}</td>
                    <td className="p-4 text-right font-medium text-gray-900">
                      ${(inv.amount_cents / 100).toFixed(2)}
                    </td>
                    <td className="p-4 text-center">
                      <StatusBadge status={inv.status} />
                    </td>
                    <td className="p-4 text-right text-gray-500">{fmt(inv.paid_at ?? inv.inserted_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
