import React, { useState, useEffect } from "react"
import { NavLink, Outlet, Link } from "react-router-dom"
import { api, StripeConfigStatus } from "../api"

const navLinks = [
  { to: "/setup",            label: "Setup" },
  { to: "/dashboard",        label: "Usage" },
  { to: "/billing",          label: "Billing" },
  { to: "/trades",           label: "Congress" },
  { to: "/account",          label: "Account" },
]

export default function Layout() {
  const [apiKey, setApiKey] = useState(localStorage.getItem("uw_api_key") ?? "")
  const [stripeStatus, setStripeStatus] = useState<StripeConfigStatus | null>(null)

  useEffect(() => {
    localStorage.setItem("uw_api_key", apiKey)
  }, [apiKey])

  useEffect(() => {
    if (!apiKey) return
    api.stripeConfig()
      .then(setStripeStatus)
      .catch(() => setStripeStatus({ configured: false, env_configured: false, custom_configured: false }))
  }, [apiKey])

  const stripeOk = stripeStatus?.configured === true

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white border-b border-gray-200 px-6 py-3 flex items-center gap-6">
        <span className="text-sm font-bold text-gray-900 mr-4">uw_billing</span>
        {navLinks.map(({ to, label }) => {
          const isSetup = to === "/setup"
          return (
            <NavLink
              key={to} to={to}
              className={({ isActive }) =>
                `text-sm font-medium flex items-center gap-1 ${isActive ? "text-blue-600" : "text-gray-500 hover:text-gray-900"}`}
            >
              {label}
              {isSetup && stripeStatus !== null && (
                <span className={`w-2 h-2 rounded-full ${stripeOk ? "bg-green-500" : "bg-amber-500"}`} />
              )}
            </NavLink>
          )
        })}
        <div className="ml-auto flex items-center gap-2">
          <span className="text-xs text-gray-500">API Key:</span>
          <input
            type="text"
            value={apiKey}
            onChange={e => setApiKey(e.target.value)}
            placeholder="Paste X-Api-Key here"
            className="text-xs text-gray-900 bg-white border border-gray-200 rounded px-2 py-1 w-56 font-mono"
          />
        </div>
      </nav>

      {stripeStatus !== null && !stripeOk && (
        <div className="bg-amber-50 border-b border-amber-200 px-6 py-2 flex items-center gap-3 text-sm text-amber-800">
          <span className="font-medium">Stripe credentials not configured.</span>
          <span className="text-amber-700">Billing features won't work until setup is complete.</span>
          <Link to="/setup" className="ml-auto font-medium underline hover:text-amber-900">
            Go to Setup →
          </Link>
        </div>
      )}

      <main className="max-w-5xl mx-auto p-6">
        <Outlet />
      </main>
    </div>
  )
}
