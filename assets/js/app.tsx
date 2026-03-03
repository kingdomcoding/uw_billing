import React from "react"
import { createRoot } from "react-dom/client"
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom"
import Layout from "./components/Layout"
import SetupPage from "./pages/SetupPage"
import UsagePage from "./pages/UsagePage"
import BillingPage from "./pages/BillingPage"
import TradesPage from "./pages/TradesPage"

const container = document.getElementById("app")!
createRoot(container).render(
  <BrowserRouter>
    <Routes>
      <Route path="/" element={<Layout />}>
        <Route index element={<Navigate to="/trades" replace />} />
        <Route path="settings" element={<SetupPage />} />
        <Route path="usage"   element={<UsagePage />} />
        <Route path="billing" element={<BillingPage />} />
        <Route path="trades"  element={<TradesPage />} />
      </Route>
    </Routes>
  </BrowserRouter>
)
