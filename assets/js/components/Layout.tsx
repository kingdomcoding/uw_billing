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
  const [email, setEmail] = useState<string | null>(null)
  const [stripeStatus, setStripeStatus] = useState<StripeConfigStatus | null>(null)
  const [ready, setReady] = useState(false)

  useEffect(() => {
    const stored = localStorage.getItem("uw_api_key") ?? ""

    const refreshFromDemo = () =>
      api.demoSession()
        .then(({ api_key, email: e }) => {
          localStorage.setItem("uw_api_key", api_key)
          setApiKey(api_key)
          setEmail(e)
        })
        .catch(() => {})
        .finally(() => setReady(true))

    if (stored) {
      api.account()
        .then(info => {
          setEmail(info.email)
          setReady(true)
        })
        .catch(() => {
          localStorage.removeItem("uw_api_key")
          setApiKey("")
          refreshFromDemo()
        })
    } else {
      refreshFromDemo()
    }
  }, [])

  useEffect(() => {
    if (!apiKey) return
    api.stripeConfig()
      .then(setStripeStatus)
      .catch(() => setStripeStatus({ configured: false, env_configured: false, custom_configured: false }))
  }, [apiKey])

  const stripeOk = stripeStatus?.configured === true
  const setupTitle = stripeOk
    ? "Stripe configured"
    : "Stripe not configured — billing features disabled"

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
                <span
                  title={setupTitle}
                  className={`w-2 h-2 rounded-full cursor-help ${stripeOk ? "bg-green-500" : "bg-amber-500"}`}
                />
              )}
            </NavLink>
          )
        })}
        {email && (
          <div className="ml-auto text-xs text-gray-500 font-mono">{email}</div>
        )}
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
        {ready ? <Outlet /> : null}
      </main>
    </div>
  )
}
