import React, { useEffect, useState } from "react"
import { api, CongressTrade, CongressSummary } from "../api"
import StatusBadge from "../components/StatusBadge"

export default function TradesPage() {
  const [trades, setTrades] = useState<CongressTrade[]>([])
  const [summary, setSummary] = useState<CongressSummary[]>([])
  const [filterTicker, setFilterTicker] = useState("")
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    Promise.all([api.recentTrades(50), api.tradeSummary()])
      .then(([t, s]) => { setTrades(t); setSummary(s); setLoading(false) })
      .catch(() => setLoading(false))
  }, [])

  const searchTicker = () => {
    if (!filterTicker.trim()) return
    setLoading(true)
    api.tradesByTicker(filterTicker.trim())
      .then(t => { setTrades(t); setLoading(false) })
      .catch(() => setLoading(false))
  }

  const fmt = (s: string | null) =>
    s ? new Date(s).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" }) : "—"

  if (loading) return <div className="p-8 text-gray-500">Loading...</div>

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold text-gray-900">Congressional Trades</h1>
        <div className="flex gap-2">
          <input
            type="text"
            value={filterTicker}
            onChange={e => setFilterTicker(e.target.value.toUpperCase())}
            onKeyDown={e => e.key === "Enter" && searchTicker()}
            placeholder="Filter by ticker…"
            className="text-sm text-gray-900 bg-white border border-gray-200 rounded px-3 py-1.5 w-40 font-mono uppercase"
          />
          <button onClick={searchTicker}
            className="text-sm px-3 py-1.5 bg-blue-600 text-white rounded hover:bg-blue-700">
            Search
          </button>
        </div>
      </div>

      {(summary ?? []).length > 0 && (
        <div className="bg-white rounded-lg border border-gray-200 p-4">
          <h2 className="text-sm font-medium text-gray-700 mb-3">Active tickers (last 50 filings)</h2>
          <div className="flex flex-wrap gap-2">
            {(summary ?? []).slice(0, 20).map(s => (
              <button key={s.ticker}
                onClick={() => {
                  setFilterTicker(s.ticker)
                  api.tradesByTicker(s.ticker).then(t => setTrades(t ?? []))
                }}
                className="flex items-center gap-1.5 px-2 py-1 bg-gray-50 border border-gray-200 rounded text-xs hover:bg-blue-50 hover:border-blue-300">
                <span className="font-mono font-semibold text-gray-900">{s.ticker}</span>
                <span className="text-gray-500">{s.trades}</span>
              </button>
            ))}
          </div>
        </div>
      )}

      <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="text-left p-4 text-gray-500 font-medium">Trader</th>
              <th className="text-left p-4 text-gray-500 font-medium">Ticker</th>
              <th className="text-center p-4 text-gray-500 font-medium">Type</th>
              <th className="text-left p-4 text-gray-500 font-medium">Amount</th>
              <th className="text-right p-4 text-gray-500 font-medium">Traded</th>
              <th className="text-right p-4 text-gray-500 font-medium">Filed</th>
            </tr>
          </thead>
          <tbody>
            {(trades ?? []).map((t, i) => (
              <tr key={t.id} className={i % 2 === 0 ? "bg-white" : "bg-gray-50"}>
                <td className="p-4 text-gray-700">{t.trader_name}</td>
                <td className="p-4 font-mono font-semibold text-blue-600">{t.ticker}</td>
                <td className="p-4 text-center"><StatusBadge status={t.transaction_type} /></td>
                <td className="p-4 text-gray-500 text-xs">{t.amount_range ?? "—"}</td>
                <td className="p-4 text-right text-gray-500">{fmt(t.traded_at)}</td>
                <td className="p-4 text-right text-gray-500">{fmt(t.filed_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {(trades ?? []).length === 0 && (
          <div className="p-8 text-center text-gray-400 text-sm">No trades found.</div>
        )}
      </div>

      <p className="text-xs text-gray-500">
        Data sourced via the Unusual Whales API (or EDGAR EFTS as fallback).
        Polled every 6 hours via Oban cron. STOCK Act requires disclosure within 45 days of trade.
      </p>
    </div>
  )
}
