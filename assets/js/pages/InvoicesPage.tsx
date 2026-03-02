import React, { useEffect, useState } from "react"
import { api, Invoice } from "../api"
import StatusBadge from "../components/StatusBadge"

export default function InvoicesPage() {
  const [invoices, setInvoices] = useState<Invoice[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    api.invoices()
      .then(inv => { setInvoices(inv); setLoading(false) })
      .catch(() => setLoading(false))
  }, [])

  if (loading) return <div className="p-8 text-gray-500">Loading...</div>

  const fmt = (s: string | null) =>
    s ? new Date(s).toLocaleDateString("en-US", { year: "numeric", month: "short", day: "numeric" }) : "—"

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-semibold text-gray-900">Invoice History</h1>
      {(invoices ?? []).length === 0 ? (
        <div className="bg-white rounded-lg border border-gray-200 p-6 text-gray-500">No invoices yet.</div>
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
              {(invoices ?? []).map((inv, i) => (
                <tr key={inv.id} className={i % 2 === 0 ? "bg-white" : "bg-gray-50"}>
                  <td className="p-4 font-mono text-xs text-gray-600">{inv.stripe_invoice_id}</td>
                  <td className="p-4 text-right font-medium">
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
  )
}
