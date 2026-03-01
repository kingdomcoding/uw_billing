import React, { useEffect, useState } from "react"
import { Link } from "react-router-dom"
import { api, SubscriptionInfo } from "../api"
import StatusBadge from "../components/StatusBadge"

export default function BillingPage() {
  const [sub, setSub] = useState<SubscriptionInfo | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [acting, setActing] = useState(false)

  useEffect(() => {
    api.subscription()
      .then(s => { setSub(s); setLoading(false) })
      .catch(e => { setError((e as Error).message); setLoading(false) })
  }, [])

  const action = async (fn: () => Promise<SubscriptionInfo | void>) => {
    setActing(true)
    try {
      const result = await fn()
      if (result) setSub(result as SubscriptionInfo)
      else setSub(null)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setActing(false)
    }
  }

  if (loading) return <div className="p-8 text-gray-500">Loading...</div>
  if (error)   return <div className="p-8 text-red-500">Error: {error}</div>

  if (!sub) return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold text-gray-900">Billing</h1>
      <div className="bg-white rounded-lg border border-gray-200 p-6 text-gray-500">
        No active subscription. <Link to="/billing/plans" className="text-blue-600 underline">View plans →</Link>
      </div>
    </div>
  )

  const fmt = (s: string | null) =>
    s ? new Date(s).toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric" }) : "—"

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-semibold text-gray-900">Billing</h1>

      <div className="bg-white rounded-lg border border-gray-200 p-6 space-y-4">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-lg font-semibold">{sub.plan.name} plan</div>
            <div className="text-sm text-gray-500">
              {sub.plan.amount_cents === 0
                ? "Free"
                : `$${(sub.plan.amount_cents / 100).toFixed(2)} / ${sub.plan.interval}`}
            </div>
          </div>
          <StatusBadge status={sub.status} />
        </div>

        <div className="grid grid-cols-2 gap-4 text-sm">
          <div>
            <div className="text-gray-500">Current period</div>
            <div>{fmt(sub.current_period_start)} → {fmt(sub.current_period_end)}</div>
          </div>
          {sub.trial_end && (
            <div>
              <div className="text-gray-500">Trial ends</div>
              <div>{fmt(sub.trial_end)}</div>
            </div>
          )}
          {sub.plan.api_request_limit && (
            <div>
              <div className="text-gray-500">Monthly API limit</div>
              <div>{sub.plan.api_request_limit.toLocaleString()} requests</div>
            </div>
          )}
          {sub.cancel_at_period_end && (
            <div className="col-span-2">
              <span className="text-amber-700 bg-amber-50 px-2 py-1 rounded text-xs">
                Cancels at end of current period ({fmt(sub.current_period_end)})
              </span>
            </div>
          )}
        </div>

        <div className="flex flex-wrap gap-2 pt-2 border-t border-gray-100">
          <Link to="/billing/plans"
            className="px-3 py-1.5 text-sm bg-blue-600 text-white rounded hover:bg-blue-700">
            Change plan
          </Link>
          <Link to="/billing/invoices"
            className="px-3 py-1.5 text-sm border border-gray-200 rounded hover:bg-gray-50">
            Invoice history
          </Link>
          {sub.status === "active" && (
            <button
              disabled={acting}
              onClick={() => action(() => api.pauseSub())}
              className="px-3 py-1.5 text-sm border border-gray-200 rounded hover:bg-gray-50 disabled:opacity-50">
              Pause subscription
            </button>
          )}
          {sub.status === "paused" && (
            <button
              disabled={acting}
              onClick={() => action(() => api.resumeSub())}
              className="px-3 py-1.5 text-sm bg-green-600 text-white rounded hover:bg-green-700 disabled:opacity-50">
              Resume subscription
            </button>
          )}
          {sub.status !== "canceled" && (
            <button
              disabled={acting}
              onClick={() => { if (confirm("Cancel your subscription?")) action(() => api.cancelSub()) }}
              className="px-3 py-1.5 text-sm text-red-600 border border-red-200 rounded hover:bg-red-50 disabled:opacity-50 ml-auto">
              Cancel
            </button>
          )}
        </div>
      </div>
    </div>
  )
}
