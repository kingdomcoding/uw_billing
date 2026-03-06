import React, { useEffect, useState } from "react"
import { Link } from "react-router-dom"
import { api, ApiError, CongressTrade, CongressSummary, MonthlySummary } from "../api"
import StatusBadge from "../components/StatusBadge"
import ErrorBanner from "../components/ErrorBanner"

type TxFilter = "all" | "purchase" | "sale" | "exchange"

const PAGE_SIZE = 50

function formatRelative(d: Date): string {
  const secs = Math.floor((Date.now() - d.getTime()) / 1000)
  if (secs < 10)   return "just now"
  if (secs < 60)   return `${secs}s ago`
  if (secs < 3600) return `${Math.floor(secs / 60)}m ago`
  return `${Math.floor(secs / 3600)}h ago`
}

export default function TradesPage() {
  const [trades, setTrades]             = useState<CongressTrade[]>([])
  const [summary, setSummary]           = useState<CongressSummary[]>([])
  const [filterTicker, setFilterTicker] = useState("")
  const [isFiltered, setIsFiltered]     = useState(false)
  const [loading, setLoading]           = useState(true)
  const [error, setError]               = useState<ApiError | Error | null>(null)
  const [polling, setPolling]           = useState(false)
  const [page, setPage]                 = useState(1)
  const [txFilter, setTxFilter]         = useState<TxFilter>("all")
  const [usageSummary, setUsageSummary] = useState<MonthlySummary | null>(null)
  const [lastUpdated, setLastUpdated]   = useState<Date | null>(null)

  const refreshUsage = () =>
    api.monthlySummary().then(setUsageSummary).catch(() => {})

  const loadAll = (p = 1) => {
    setIsFiltered(false)
    setTxFilter("all")
    setLoading(true)
    setError(null)
    Promise.all([api.recentTrades(p * PAGE_SIZE), api.tradeSummary()])
      .then(([t, s]) => {
        setTrades(t)
        setSummary(s)
        setPage(p)
        setLastUpdated(new Date())
        setLoading(false)
        refreshUsage()
      })
      .catch((err: unknown) => { setLoading(false); setError(err instanceof Error ? err : new Error(String(err))) })
  }

  useEffect(() => { loadAll() }, [])

  useEffect(() => {
    if (!lastUpdated) return
    const interval = setInterval(() => {
      setLastUpdated(d => d ? new Date(d.getTime()) : d)
    }, 30_000)
    return () => clearInterval(interval)
  }, [lastUpdated])

  const searchTicker = () => {
    const q = filterTicker.trim()
    if (!q) { loadAll(); return }
    setLoading(true)
    setError(null)
    setIsFiltered(true)
    api.searchTrades(q)
      .then(t => {
        setTrades(t)
        setLastUpdated(new Date())
        setLoading(false)
        refreshUsage()
      })
      .catch((err: unknown) => { setLoading(false); setError(err instanceof Error ? err : new Error(String(err))) })
  }

  const triggerPoll = () => {
    setPolling(true)
    api.refreshTrades()
      .then(() => {
        setTimeout(() => {
          loadAll()
          setPolling(false)
        }, 3_000)
      })
      .catch((err: unknown) => { setPolling(false); setError(err instanceof Error ? err : new Error("Refresh failed")) })
  }

  const fmt = (s: string | null) =>
    s ? new Date(s).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" }) : "—"

  const visibleTrades = txFilter === "all"
    ? trades
    : trades.filter(t => t.transaction_type === txFilter)

  if (loading) return <div className="p-8 text-gray-500">Loading...</div>

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold text-gray-900">Congressional Trades</h1>
          <p className="mt-1 text-xs text-gray-500">
            STOCK Act disclosures from the Unusual Whales API (SEC EDGAR fallback) · polled every 6h via Oban · Ash resources backed by Postgres
          </p>
        </div>
        <div className="flex items-center gap-2 flex-wrap justify-end">
          <input
            type="text"
            value={filterTicker}
            onChange={e => setFilterTicker(e.target.value)}
            onKeyDown={e => e.key === "Enter" && searchTicker()}
            placeholder="Search ticker or name…"
            className="text-sm text-gray-900 bg-white border border-gray-200 rounded px-3 py-1.5 w-44"
          />
          <button onClick={searchTicker}
            className="text-sm px-3 py-1.5 bg-blue-600 text-white rounded hover:bg-blue-700">
            Search
          </button>
          {isFiltered && (
            <button
              onClick={() => { setFilterTicker(""); loadAll() }}
              className="text-sm px-3 py-1.5 border border-gray-200 text-gray-600 rounded hover:bg-gray-50">
              Clear
            </button>
          )}
          {lastUpdated && (
            <span className="text-xs text-gray-400 tabular-nums">
              {formatRelative(lastUpdated)}
            </span>
          )}
          {usageSummary && !usageSummary.plan_unlimited && (
            <span className="text-xs text-gray-400 tabular-nums">
              {usageSummary.count.toLocaleString()} / {usageSummary.limit?.toLocaleString()} req
            </span>
          )}
          <button
            onClick={triggerPoll}
            disabled={polling}
            title={polling ? "Fetching…" : "Fetch live data"}
            className="text-sm px-3 py-1.5 border border-gray-200 text-gray-600 rounded hover:bg-gray-50 disabled:opacity-50">
            {polling ? "Fetching…" : "↻"}
          </button>
        </div>
      </div>

      {error && <ErrorBanner error={error} onRetry={() => { setError(null); loadAll(page) }} />}

      {usageSummary?.near_limit && !usageSummary.plan_unlimited && (usageSummary.usage_pct ?? 0) < 100 && (
        <div className="bg-amber-50 border border-amber-200 rounded-lg px-4 py-3 flex items-center justify-between text-sm">
          <span className="text-amber-800">
            You're at {usageSummary.usage_pct}% of your monthly request limit.
          </span>
          <Link to="/billing" className="text-amber-900 font-medium underline ml-4 shrink-0">
            Upgrade →
          </Link>
        </div>
      )}

      <div className="flex items-center gap-1">
        {(["all", "purchase", "sale", "exchange"] as const).map(f => (
          <button
            key={f}
            onClick={() => setTxFilter(f)}
            className={`text-xs px-3 py-1 rounded border transition-colors ${
              txFilter === f
                ? "bg-gray-900 text-white border-gray-900"
                : "bg-white text-gray-500 border-gray-200 hover:border-gray-400"
            }`}
          >
            {f === "all" ? "All" : f.charAt(0).toUpperCase() + f.slice(1) + "s"}
          </button>
        ))}
      </div>

      {(summary ?? []).length > 0 && (
        <div className="bg-white rounded-lg border border-gray-200 p-4">
          <h2 className="text-sm font-medium text-gray-700 mb-3">Active tickers (last 200 filings)</h2>
          <div className="flex flex-wrap gap-2">
            {(summary ?? []).slice(0, 20).map(s => (
              <button key={s.ticker}
                onClick={() => {
                  setFilterTicker(s.ticker)
                  setIsFiltered(true)
                  setLoading(true)
                  setError(null)
                  api.tradesByTicker(s.ticker)
                    .then(t => {
                      setTrades(t ?? [])
                      setLastUpdated(new Date())
                      setLoading(false)
                      refreshUsage()
                    })
                    .catch((err: unknown) => { setLoading(false); setError(err instanceof Error ? err : new Error(String(err))) })
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
            {visibleTrades.map((t, i) => (
              <tr key={t.id} className={i % 2 === 0 ? "bg-white" : "bg-gray-50"}>
                <td className="p-4 text-gray-700">
                  <span>{t.trader_name}</span>
                  {t.issuer && t.issuer !== "self" && (
                    <span className="ml-1.5 text-xs text-gray-400">({t.issuer})</span>
                  )}
                </td>
                <td className="p-4 font-mono font-semibold text-blue-600">
                  {t.ticker}
                  {t.member_type && (
                    <span className={`ml-1.5 text-xs font-sans font-normal px-1 rounded ${
                      t.member_type === "house"
                        ? "bg-blue-50 text-blue-500"
                        : "bg-purple-50 text-purple-500"
                    }`}>
                      {t.member_type === "house" ? "H" : "S"}
                    </span>
                  )}
                </td>
                <td className="p-4 text-center"><StatusBadge status={t.transaction_type} /></td>
                <td className="p-4 text-gray-500 text-xs">{t.amount_range ?? "—"}</td>
                <td className="p-4 text-right text-gray-500">{fmt(t.traded_at)}</td>
                <td className="p-4 text-right text-gray-500">{fmt(t.filed_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {visibleTrades.length === 0 && (
          <div className="p-8 text-center text-gray-400 text-sm">No trades found.</div>
        )}
      </div>

      <div className="flex items-center justify-between">
        {!isFiltered && trades.length === page * PAGE_SIZE && (
          <button
            onClick={() => loadAll(page + 1)}
            className="text-sm px-4 py-2 border border-gray-200 text-gray-600 rounded hover:bg-gray-50">
            Load more
          </button>
        )}
        <p className="text-xs text-gray-400 ml-auto">
          {isFiltered
            ? `${visibleTrades.length} result${visibleTrades.length !== 1 ? "s" : ""}`
            : `Showing ${trades.length} most recent trades`}
        </p>
      </div>

    </div>
  )
}
