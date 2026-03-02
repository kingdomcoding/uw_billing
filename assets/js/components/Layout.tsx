import React, { useState, useEffect, useCallback } from "react"
import { NavLink, Outlet, useNavigate, useLocation } from "react-router-dom"
import { api, StripeConfigStatus } from "../api"

const ALL_NAV = [
  { to: "/setup",     label: "Setup" },
  { to: "/dashboard", label: "Usage" },
  { to: "/billing",   label: "Billing" },
  { to: "/trades",    label: "Congress" },
  { to: "/account",   label: "Account" },
]

export default function Layout() {
  const [apiKey, setApiKey]             = useState(localStorage.getItem("uw_api_key") ?? "")
  const [email, setEmail]               = useState<string | null>(null)
  const [stripeStatus, setStripeStatus] = useState<StripeConfigStatus | null>(null)
  const [hasSub, setHasSub]             = useState<boolean | null>(null)
  const [ready, setReady]               = useState(false)
  const navigate = useNavigate()
  const location = useLocation()

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
        .then(info => { setEmail(info.email); setReady(true) })
        .catch(() => {
          localStorage.removeItem("uw_api_key")
          setApiKey("")
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

  const refreshSub = useCallback(() => {
    if (!apiKey) return
    api.subscription()
      .then(sub => setHasSub(!!sub))
      .catch(() => setHasSub(false))
  }, [apiKey])

  useEffect(() => {
    refreshSub()
  }, [refreshSub])

  useEffect(() => {
    if (stripeStatus === null || hasSub === null) return
    if (location.pathname === "/setup") return
    if (!stripeStatus.configured || !hasSub) {
      navigate("/setup", { replace: true })
    }
  }, [stripeStatus, hasSub, location.pathname, navigate])

  const stripeOk = stripeStatus?.configured === true && hasSub === true
  const navLinks = stripeOk ? ALL_NAV : ALL_NAV.slice(0, 1)
  const fullyReady = ready && hasSub !== null

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
        {email && <div className="ml-auto text-xs text-gray-500 font-mono">{email}</div>}
      </nav>

      <main className="max-w-5xl mx-auto p-6">
        {fullyReady
          ? <Outlet context={{ refreshStripe, refreshSub }} />
          : <div className="flex items-center justify-center h-32 text-sm text-gray-400">Loading…</div>
        }
      </main>
    </div>
  )
}
