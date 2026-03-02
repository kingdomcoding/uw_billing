import React, { useEffect, useState } from "react"
import { createRoot } from "react-dom/client"
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom"
import { api } from "./api"
import Layout from "./components/Layout"
import SetupPage from "./pages/SetupPage"
import UsagePage from "./pages/UsagePage"
import BillingPage from "./pages/BillingPage"
import AccountPage from "./pages/AccountPage"
import TradesPage from "./pages/TradesPage"

function RootRedirect() {
  const [dest, setDest] = useState<string | null>(null)

  useEffect(() => {
    api.setupStatus()
      .then(({ configured, has_subscription }) => {
        if (!configured || !has_subscription) setDest("/setup")
        else                                  setDest("/dashboard")
      })
      .catch(() => setDest("/setup"))
  }, [])

  if (!dest) return <div className="p-8 text-sm text-gray-400">Loading...</div>
  return <Navigate to={dest} replace />
}

const container = document.getElementById("app")!
createRoot(container).render(
  <BrowserRouter>
    <Routes>
      <Route path="/" element={<Layout />}>
        <Route index element={<RootRedirect />} />
        <Route path="setup"            element={<SetupPage />} />
        <Route path="dashboard"        element={<UsagePage />} />
        <Route path="billing"          element={<BillingPage />} />
        <Route path="account"          element={<AccountPage />} />
        <Route path="trades"           element={<TradesPage />} />
      </Route>
    </Routes>
  </BrowserRouter>
)
