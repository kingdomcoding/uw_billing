import React, { useEffect, useState } from "react"
import { useNavigate } from "react-router-dom"
import { api, Plan, SubscriptionInfo } from "../api"

export default function PlansPage() {
  const [plans, setPlans] = useState<Plan[]>([])
  const [sub, setSub] = useState<SubscriptionInfo | null>(null)
  const [loading, setLoading] = useState(true)
  const [acting, setActing] = useState<string | null>(null)
  const navigate = useNavigate()

  useEffect(() => {
    Promise.all([api.listPlans(), api.subscription()])
      .then(([p, s]) => { setPlans(p); setSub(s); setLoading(false) })
      .catch(() => setLoading(false))
  }, [])

  const selectPlan = async (plan: Plan) => {
    if (!sub) return
    const immediate = plan.amount_cents >= (sub.plan.amount_cents ?? 0)
    setActing(plan.id)
    try {
      await api.changePlan(plan.id, immediate)
      navigate("/billing")
    } finally {
      setActing(null)
    }
  }

  if (loading) return <div className="p-8 text-gray-500">Loading...</div>

  const tiers = ["free", "pro", "premium"]
  const sorted = [...(plans ?? [])].sort((a, b) => tiers.indexOf(a.tier) - tiers.indexOf(b.tier))

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-semibold text-gray-900">Plans</h1>
      <div className="grid grid-cols-3 gap-6">
        {sorted.map(plan => {
          const isCurrent = sub?.plan.id === plan.id
          return (
            <div key={plan.id}
              className={`bg-white rounded-lg border p-6 flex flex-col gap-4 ${
                isCurrent ? "border-blue-400 ring-1 ring-blue-400" : "border-gray-200"}`}>
              <div>
                <div className="text-lg font-semibold capitalize text-gray-900">{plan.name}</div>
                <div className="text-2xl font-bold text-gray-900 mt-1">
                  {plan.amount_cents === 0
                    ? "Free"
                    : `$${(plan.amount_cents / 100).toFixed(0)}`}
                  {plan.interval && <span className="text-sm font-normal text-gray-500"> /{plan.interval}</span>}
                </div>
              </div>
              <ul className="text-sm text-gray-600 space-y-1 flex-1">
                <li>
                  {plan.api_request_limit
                    ? `${plan.api_request_limit.toLocaleString()} API requests/month`
                    : "Unlimited API requests"}
                </li>
                {Object.entries(plan.features ?? {}).map(([k, v]) => (
                  <li key={k}>{String(v)}</li>
                ))}
              </ul>
              {isCurrent ? (
                <div className="text-sm text-blue-600 font-medium text-center py-2">Current plan</div>
              ) : (
                <button
                  disabled={!!acting || !sub}
                  onClick={() => selectPlan(plan)}
                  className="w-full py-2 text-sm bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50">
                  {acting === plan.id ? "Switching..." : "Select"}
                </button>
              )}
            </div>
          )
        })}
      </div>
      <p className="text-xs text-gray-500">
        Upgrades take effect immediately (Stripe prorates the difference).
        Downgrades take effect at the end of your current billing period.
      </p>
    </div>
  )
}
