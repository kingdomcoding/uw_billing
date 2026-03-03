import React, { useState, useEffect, useCallback } from "react"
import { NavLink, Outlet } from "react-router-dom"
import { api, StripeConfigStatus } from "../api"

const ALL_NAV = [
  { to: "/trades",   label: "Trades" },
  { to: "/usage",    label: "API Usage" },
  { to: "/billing",  label: "Billing" },
  { to: "/settings", label: "Settings" },
]

export default function Layout() {
  const [email, setEmail]               = useState<string | null>(null)
  const [stripeStatus, setStripeStatus] = useState<StripeConfigStatus | null>(null)
  const [ready, setReady]               = useState(false)

  useEffect(() => {
    const stored = localStorage.getItem("uw_api_key") ?? ""
    const refreshFromDemo = () =>
      api.demoSession()
        .then(({ api_key, email: e }) => {
          localStorage.setItem("uw_api_key", api_key)
          setEmail(e)
        })
        .catch(() => {})
        .finally(() => setReady(true))

    if (stored) {
      api.account()
        .then(info => { setEmail(info.email); setReady(true) })
        .catch(() => {
          localStorage.removeItem("uw_api_key")
          refreshFromDemo()
        })
    } else {
      refreshFromDemo()
    }
  }, [])

  const refreshStripe = useCallback(() => {
    api.stripeConfig()
      .then(setStripeStatus)
      .catch(() => setStripeStatus({ configured: false, env_configured: false, custom_configured: false }))
  }, [])

  useEffect(() => {
    refreshStripe()
  }, [refreshStripe])

  useEffect(() => {
    if (!ready || !stripeStatus?.configured) return
    api.subscription()
      .then(sub => { if (!sub) api.demoSubscribe().catch(() => {}) })
      .catch(() => {})
  }, [ready, stripeStatus])

  const stripeOk = stripeStatus?.custom_configured === true
  const initials = email ? email.split("@")[0].slice(0, 2).toUpperCase() : ""

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white border-b border-gray-200">
        <div className="max-w-5xl mx-auto px-6 flex items-stretch h-12">

          <div className="flex-1 flex items-center">
            <span className="text-base font-bold text-gray-900 tracking-tight">
              Unusual Whales
            </span>
          </div>

          <div className="flex items-stretch gap-6">
            {ALL_NAV.map(({ to, label }) => {
              const isStripeSetup = to === "/settings"
              return (
                <NavLink
                  key={to} to={to}
                  className={({ isActive }) =>
                    `flex items-center gap-1.5 text-sm font-medium border-b-2 -mb-px px-1 ` +
                    (isActive
                      ? "text-blue-600 border-blue-600"
                      : "text-gray-500 border-transparent hover:text-gray-900")}
                >
                  {label}
                  {isStripeSetup && stripeStatus !== null && (
                    <span
                      title={stripeOk ? "Using your Stripe credentials" : "Using app default credentials"}
                      className={`w-1.5 h-1.5 rounded-full shrink-0 ${stripeOk ? "bg-green-500" : "bg-amber-400"}`}
                    />
                  )}
                </NavLink>
              )
            })}
          </div>

          <div className="flex-1 flex items-center justify-end">
            {email && (
              <div className="flex items-center gap-2">
                <div className="w-7 h-7 rounded-full bg-blue-600 flex items-center justify-center text-white text-xs font-semibold shrink-0">
                  {initials}
                </div>
                <span className="text-sm text-gray-700">{email}</span>
              </div>
            )}
          </div>

        </div>
      </nav>

      <main className="max-w-5xl mx-auto p-6">
        {ready
          ? <Outlet context={{ refreshStripe, refreshSub: () => {} }} />
          : <div className="flex items-center justify-center h-32 text-sm text-gray-400">Loading…</div>
        }
      </main>
    </div>
  )
}
