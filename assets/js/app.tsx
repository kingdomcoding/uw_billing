import React from "react"
import { createRoot } from "react-dom/client"
import { BrowserRouter, Routes, Route } from "react-router-dom"
import Layout from "./components/Layout"
import OverviewPage from "./pages/OverviewPage"
import SetupPage from "./pages/SetupPage"
import UsagePage from "./pages/UsagePage"
import BillingPage from "./pages/BillingPage"
import TradesPage from "./pages/TradesPage"

const container = document.getElementById("app")!
createRoot(container).render(
  <BrowserRouter>
    <Routes>
      <Route path="/" element={<Layout />}>
        <Route index element={<OverviewPage />} />
        <Route path="settings" element={<SetupPage />} />
        <Route path="usage"   element={<UsagePage />} />
        <Route path="billing" element={<BillingPage />} />
        <Route path="trades"  element={<TradesPage />} />
      </Route>
    </Routes>
  </BrowserRouter>
)
