import React, { useEffect, useRef, useState } from "react"
import { Link } from "react-router-dom"
import { api, DailyCount, EndpointCount, MonthlySummary, Latency, AccountInfo } from "../api"
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, Legend, Cell
} from "recharts"

const COLORS = ["#3b82f6","#8b5cf6","#10b981","#f59e0b","#ef4444","#06b6d4","#84cc16","#f97316","#ec4899","#6366f1"]

type SandboxInputType = "ticker" | "search"

interface SandboxEndpoint {
  label: string
  path: string
  inputType?: SandboxInputType
}

interface SandboxResult {
  status: number
  duration_ms: number
  bodyText: string
}

const SANDBOX_ENDPOINTS: SandboxEndpoint[] = [
  { label: "Recent Congressional Trades", path: "/api/congress/recent" },
  { label: "Congressional Trade Summary", path: "/api/congress/summary" },
  { label: "Trades by Ticker",            path: "/api/congress/ticker/:ticker", inputType: "ticker" },
  { label: "Search Trades",              path: "/api/congress/search",          inputType: "search" },
]

function ApiSandbox({ onRefresh }: { onRefresh: () => void }) {
  const [endpointIdx, setEndpointIdx] = useState(0)
  const [ticker,      setTicker]      = useState("NVDA")
  const [query,       setQuery]       = useState("Pelosi")
  const [loading,     setLoading]     = useState(false)
  const [result,      setResult]      = useState<SandboxResult | null>(null)
  const [refreshing,  setRefreshing]  = useState(false)

  const endpoint = SANDBOX_ENDPOINTS[endpointIdx]

  const resolvedPath = (() => {
    if (endpoint.inputType === "ticker")
      return endpoint.path.replace(":ticker", ticker.toUpperCase().trim())
    if (endpoint.inputType === "search")
      return `${endpoint.path}?q=${encodeURIComponent(query)}`
    return endpoint.path
  })()

  const send = async () => {
    setLoading(true)
    setResult(null)
    const t0 = performance.now()
    try {
      const res = await fetch(resolvedPath, {
        headers: { "X-Api-Key": localStorage.getItem("uw_api_key") ?? "" }
      })
      const duration_ms = Math.round(performance.now() - t0)
      const raw = await res.text()
      let bodyText: string
      try {
        bodyText = JSON.stringify(JSON.parse(raw), null, 2)
      } catch {
        bodyText = raw
      }
      setResult({ status: res.status, duration_ms, bodyText })
      setRefreshing(true)
      setTimeout(() => { onRefresh(); setRefreshing(false) }, 2000)
    } finally {
      setLoading(false)
    }
  }

  const preview   = result ? result.bodyText.slice(0, 1800) : ""
  const truncated = result ? result.bodyText.length > 1800 : false

  return (
    <div className="bg-white rounded-lg border border-gray-200 p-6 flex flex-col gap-4">
      <div>
        <h3 className="font-semibold text-gray-900 text-sm">API Sandbox</h3>
        <p className="text-xs text-gray-500 mt-0.5">
          Fire a real request — watch it appear in your usage charts.
        </p>
      </div>

      <div className="flex gap-2 flex-wrap">
        <select
          value={endpointIdx}
          onChange={e => { setEndpointIdx(Number(e.target.value)); setResult(null) }}
          className="text-sm border border-gray-200 rounded px-2.5 py-1.5 bg-white text-gray-700
                     focus:outline-none focus:ring-2 focus:ring-blue-500 flex-1 min-w-0"
        >
          {SANDBOX_ENDPOINTS.map((ep, i) => (
            <option key={i} value={i}>{ep.label}</option>
          ))}
        </select>

        {endpoint.inputType === "ticker" && (
          <input
            value={ticker}
            onChange={e => setTicker(e.target.value)}
            placeholder="NVDA"
            maxLength={5}
            className="text-sm text-gray-900 bg-white border border-gray-200 rounded px-2.5 py-1.5 w-20
                       font-mono uppercase focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        )}
        {endpoint.inputType === "search" && (
          <input
            value={query}
            onChange={e => setQuery(e.target.value)}
            placeholder="Pelosi"
            maxLength={40}
            className="text-sm text-gray-900 bg-white border border-gray-200 rounded px-2.5 py-1.5 w-32
                       focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        )}

        <button
          onClick={send}
          disabled={
            loading ||
            (endpoint.inputType === "ticker" && !ticker.trim()) ||
            (endpoint.inputType === "search" && !query.trim())
          }
          className="text-sm px-4 py-1.5 bg-blue-600 text-white rounded font-medium
                     hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed shrink-0"
        >
          {loading ? "Sending…" : "Send →"}
        </button>
      </div>

      <div className="text-xs font-mono text-gray-400 -mt-1">
        GET {resolvedPath}
      </div>

      {result && (
        <div className="space-y-2">
          <div className="flex items-center gap-3 text-sm">
            <span className={`font-mono font-semibold ${result.status < 400 ? "text-emerald-600" : "text-red-600"}`}>
              {result.status}
            </span>
            <span className="text-gray-400">{result.duration_ms}ms</span>
            <span className="text-emerald-600 text-xs">
              {refreshing ? "Refreshing metrics…" : "✓ Request logged"}
            </span>
          </div>
          <pre className="bg-gray-50 border border-gray-200 rounded p-3 text-xs overflow-auto max-h-52 font-mono leading-relaxed text-gray-700">
            {preview}{truncated && "\n… (truncated)"}
          </pre>
        </div>
      )}
    </div>
  )
}

interface State {
  daily: DailyCount[]
  endpoints: EndpointCount[]
  summary: MonthlySummary | null
  latency: Latency | null
  account: AccountInfo | null
  loading: boolean
  error: string | null
}

export default function UsagePage() {
  const [state, setState] = useState<State>({
    daily: [], endpoints: [], summary: null, latency: null,
    account: null, loading: true, error: null
  })
  const [copied,  setCopied]  = useState(false)
  const [days,    setDays]    = useState<7 | 30 | 90>(30)
  const isInitialized = useRef(false)

  useEffect(() => {
    Promise.all([
      api.dailyCounts(30), api.byEndpoint(),
      api.monthlySummary(), api.latency(30), api.account()
    ])
      .then(([daily, endpoints, summary, latency, account]) => {
        setState({ daily, endpoints, summary, latency, account, loading: false, error: null })
        isInitialized.current = true
      })
      .catch(err => setState(s => ({ ...s, loading: false, error: (err as Error).message })))
  }, [])

  useEffect(() => {
    if (!isInitialized.current) return
    Promise.all([api.dailyCounts(days), api.latency(days)])
      .then(([daily, latency]) => setState(s => ({ ...s, daily, latency })))
  }, [days])

  const refresh = () => {
    Promise.all([api.dailyCounts(days), api.byEndpoint(), api.monthlySummary(), api.latency(days)])
      .then(([daily, endpoints, summary, latency]) =>
        setState(s => ({ ...s, daily, endpoints, summary, latency }))
      )
  }

  const copyKey = () => {
    if (!state.account) return
    navigator.clipboard.writeText(state.account.api_key).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    })
  }

  if (state.loading) return <div className="p-8 text-gray-500">Loading…</div>
  if (state.error)   return <div className="p-8 text-red-500">Error: {state.error}</div>

  const { summary, latency, account } = state

  const monthStart = new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    .toLocaleDateString("en-US", { month: "long", day: "numeric" })

  const dailyFormatted = state.daily.map(d => ({
    ...d,
    label: new Date(d.date).toLocaleDateString("en-US", { month: "short", day: "numeric" })
  }))

  const top9 = state.endpoints.slice(0, 9)
  const otherTotal = state.endpoints.slice(9).reduce((s, d) => s + d.total, 0)
  const endpointData = otherTotal > 0 ? [...top9, { endpoint: "other", total: otherTotal }] : top9

  return (
    <div className="space-y-8">
      <h1 className="text-2xl font-semibold text-gray-900">API Usage</h1>

      {/* API Access — key + sandbox */}
      <div>
        <h2 className="text-base font-semibold text-gray-900 mb-3">API Access</h2>
        <div className="grid grid-cols-2 gap-4 items-start">
          {account && (
            <div className="bg-white rounded-lg border border-gray-200 p-6 space-y-3">
              <div className="text-xs font-medium text-gray-500 uppercase tracking-wide">Your API Key</div>
              <div className="flex items-center gap-2">
                <code className="text-xs text-gray-900 bg-gray-50 border border-gray-200 rounded px-2 py-1.5 flex-1 font-mono truncate">
                  {account.api_key}
                </code>
                <button
                  onClick={copyKey}
                  className="text-xs text-gray-700 px-2.5 py-1.5 border border-gray-200 rounded hover:bg-gray-50 shrink-0"
                >
                  {copied ? "Copied!" : "Copy"}
                </button>
              </div>
              <p className="text-xs text-gray-400">
                Pass as <code className="font-mono">X-Api-Key</code> on every request.
              </p>
            </div>
          )}
          <ApiSandbox onRefresh={refresh} />
        </div>
      </div>

      {/* Monthly summary */}
      {summary && (
        <div className="bg-white rounded-lg border border-gray-200 p-6">
          {summary.plan_unlimited ? (
            <div className="flex items-center justify-between">
              <div>
                <span className="text-sm font-medium text-gray-700">
                  Since {monthStart} — {summary.plan_tier} plan
                </span>
                <div className="mt-0.5">
                  <span className="text-emerald-600 font-semibold text-sm">∞ Unlimited requests</span>
                </div>
              </div>
              <span className="text-2xl font-bold text-gray-900">
                {summary.count.toLocaleString()}
              </span>
            </div>
          ) : (
            <>
              <div className="flex items-center justify-between mb-2">
                <span className="text-sm font-medium text-gray-700">
                  Since {monthStart} — {summary.plan_tier} plan
                </span>
                <span className="text-sm text-gray-500">
                  {summary.count.toLocaleString()}
                  {summary.limit ? ` / ${summary.limit.toLocaleString()} requests` : " requests"}
                </span>
              </div>
              {summary.limit && (
                <div className="w-full bg-gray-100 rounded-full h-2">
                  <div
                    className={`h-2 rounded-full transition-all ${summary.near_limit ? "bg-amber-500" : "bg-blue-500"}`}
                    style={{ width: `${Math.min(summary.usage_pct ?? 0, 100)}%` }}
                  />
                </div>
              )}
              {summary.near_limit && (
                <div className="mt-3 flex items-center gap-2 text-sm text-amber-700 bg-amber-50 rounded p-3">
                  <span>You're at {summary.usage_pct}% of your monthly limit.</span>
                  <Link to="/billing" className="font-medium underline">Upgrade →</Link>
                </div>
              )}
            </>
          )}
        </div>
      )}

      {/* Latency cards — 2-col, metrics only */}
      <div className="grid grid-cols-2 gap-4">
        <div className="bg-white rounded-lg border border-gray-200 p-6 text-center">
          <div className="text-3xl font-bold text-gray-900">
            {latency ? `${Math.round(latency.p50)}ms` : "—"}
          </div>
          <div className="text-sm text-gray-500 mt-1">Median latency (P50)</div>
        </div>
        <div className="bg-white rounded-lg border border-gray-200 p-6 text-center">
          <div className="text-3xl font-bold text-gray-900">
            {latency ? `${Math.round(latency.p95)}ms` : "—"}
          </div>
          <div className="text-sm text-gray-500 mt-1">95th percentile (P95)</div>
        </div>
      </div>

      {/* Daily chart with time range selector */}
      <div className="bg-white rounded-lg border border-gray-200 p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-base font-semibold text-gray-900">
            Daily requests — last {days} days
          </h2>
          <div className="flex rounded border border-gray-200 overflow-hidden text-xs">
            {([7, 30, 90] as const).map(d => (
              <button
                key={d}
                onClick={() => setDays(d)}
                className={`px-3 py-1.5 ${
                  days === d
                    ? "bg-blue-600 text-white font-medium"
                    : "bg-white text-gray-500 hover:bg-gray-50"
                }`}
              >
                {d}d
              </button>
            ))}
          </div>
        </div>
        <ResponsiveContainer width="100%" height={240}>
          <BarChart data={dailyFormatted} margin={{ top: 0, right: 0, left: -10, bottom: 0 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
            <XAxis dataKey="label" tick={{ fontSize: 11, fill: "#9ca3af" }} tickLine={false} axisLine={false} interval="preserveStartEnd" />
            <YAxis tick={{ fontSize: 11, fill: "#9ca3af" }} tickLine={false} axisLine={false} />
            <Tooltip contentStyle={{ borderRadius: 8, border: "1px solid #e5e7eb", fontSize: 12, backgroundColor: "#fff", color: "#111827" }} />
            <Legend wrapperStyle={{ fontSize: 12, color: "#374151" }} />
            <Bar dataKey="total"  name="Requests" fill="#3b82f6" radius={[2, 2, 0, 0]} />
            <Bar dataKey="errors" name="Errors"   fill="#f87171" radius={[2, 2, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </div>

      {/* Top endpoints — horizontal bar chart */}
      <div className="bg-white rounded-lg border border-gray-200 p-6">
        <h2 className="text-base font-semibold text-gray-900 mb-4">Top endpoints this month</h2>
        <ResponsiveContainer width="100%" height={Math.max(160, endpointData.length * 44)}>
          <BarChart
            data={endpointData}
            layout="vertical"
            margin={{ top: 0, right: 16, left: 8, bottom: 0 }}
          >
            <CartesianGrid strokeDasharray="3 3" horizontal={false} stroke="#f0f0f0" />
            <XAxis
              type="number"
              tick={{ fontSize: 11, fill: "#9ca3af" }}
              tickLine={false}
              axisLine={false}
            />
            <YAxis
              type="category"
              dataKey="endpoint"
              width={220}
              tick={{ fontSize: 11, fill: "#374151" }}
              tickLine={false}
              axisLine={false}
            />
            <Tooltip
              contentStyle={{ borderRadius: 8, border: "1px solid #e5e7eb", fontSize: 12, backgroundColor: "#fff", color: "#111827" }}
              formatter={(v: number) => [v.toLocaleString(), "requests"]}
            />
            <Bar dataKey="total" radius={[0, 3, 3, 0]}>
              {endpointData.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  )
}
