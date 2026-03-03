import React, { useEffect, useState } from "react"
import { Link } from "react-router-dom"
import { api, DailyCount, EndpointCount, MonthlySummary, Latency, AccountInfo } from "../api"
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend,
         PieChart, Pie, Cell } from "recharts"

const COLORS = ["#3b82f6","#8b5cf6","#10b981","#f59e0b","#ef4444","#06b6d4","#84cc16","#f97316","#ec4899","#6366f1"]

interface State {
  daily: DailyCount[]; endpoints: EndpointCount[]
  summary: MonthlySummary | null; latency: Latency | null
  account: AccountInfo | null
  loading: boolean; error: string | null
}

export default function UsagePage() {
  const [state, setState] = useState<State>({
    daily: [], endpoints: [], summary: null, latency: null, account: null, loading: true, error: null
  })
  const [copied, setCopied] = useState(false)

  useEffect(() => {
    Promise.all([api.dailyCounts(30), api.byEndpoint(), api.monthlySummary(), api.latency(), api.account()])
      .then(([daily, endpoints, summary, latency, account]) =>
        setState({ daily, endpoints, summary, latency, account, loading: false, error: null }))
      .catch(err => setState(s => ({ ...s, loading: false, error: (err as Error).message })))
  }, [])

  const copyKey = () => {
    if (!state.account) return
    navigator.clipboard.writeText(state.account.api_key).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    })
  }

  if (state.loading) return <div className="p-8 text-gray-500">Loading...</div>
  if (state.error)   return <div className="p-8 text-red-500">Error: {state.error}</div>

  const { summary, latency, account } = state

  const dailyFormatted = (state.daily ?? []).map(d => ({
    ...d,
    label: new Date(d.date).toLocaleDateString("en-US", { month: "short", day: "numeric" })
  }))

  const top9 = (state.endpoints ?? []).slice(0, 9)
  const otherTotal = (state.endpoints ?? []).slice(9).reduce((s, d) => s + d.total, 0)
  const pieData = otherTotal > 0 ? [...top9, { endpoint: "other", total: otherTotal }] : top9

  return (
    <div className="space-y-8">
      <h1 className="text-2xl font-semibold text-gray-900">API Usage</h1>

      {summary && (
        <div className="bg-white rounded-lg border border-gray-200 p-6">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium text-gray-700">
              This month — {summary.plan_tier} plan
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
        </div>
      )}

      <div className="grid grid-cols-3 gap-4">
        {latency && (
          <>
            <div className="bg-white rounded-lg border border-gray-200 p-6 text-center">
              <div className="text-3xl font-bold text-gray-900">{latency.p50}ms</div>
              <div className="text-sm text-gray-500 mt-1">Median (P50)</div>
            </div>
            <div className="bg-white rounded-lg border border-gray-200 p-6 text-center">
              <div className="text-3xl font-bold text-gray-900">{latency.p95}ms</div>
              <div className="text-sm text-gray-500 mt-1">95th percentile (P95)</div>
            </div>
          </>
        )}
        {account && (
          <div className="bg-white rounded-lg border border-gray-200 p-6 flex flex-col justify-between">
            <div className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-2">API Key</div>
            <div className="flex items-center gap-2">
              <code className="text-xs text-gray-900 bg-gray-50 border border-gray-200 rounded px-2 py-1.5 flex-1 font-mono truncate">
                {account.api_key}
              </code>
              <button
                onClick={copyKey}
                className="text-xs text-gray-700 px-2.5 py-1.5 border border-gray-200 rounded hover:bg-gray-50 shrink-0">
                {copied ? "Copied!" : "Copy"}
              </button>
            </div>
            <p className="text-xs text-gray-400 mt-2">
              Pass as <code className="font-mono">X-Api-Key</code> header
            </p>
          </div>
        )}
      </div>

      <div className="bg-white rounded-lg border border-gray-200 p-6">
        <h2 className="text-base font-semibold text-gray-900 mb-4">Daily requests — last 30 days</h2>
        <ResponsiveContainer width="100%" height={240}>
          <BarChart data={dailyFormatted} margin={{ top: 0, right: 0, left: -10, bottom: 0 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
            <XAxis dataKey="label" tick={{ fontSize: 11, fill: "#9ca3af" }} tickLine={false} axisLine={false} interval="preserveStartEnd" />
            <YAxis tick={{ fontSize: 11, fill: "#9ca3af" }} tickLine={false} axisLine={false} />
            <Tooltip contentStyle={{ borderRadius: 8, border: "1px solid #e5e7eb", fontSize: 12, backgroundColor: "#fff", color: "#111827" }} />
            <Legend wrapperStyle={{ fontSize: 12, color: "#374151" }} />
            <Bar dataKey="total" name="Requests" fill="#3b82f6" radius={[2, 2, 0, 0]} />
            <Bar dataKey="errors" name="Errors" fill="#f87171" radius={[2, 2, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </div>

      <div className="bg-white rounded-lg border border-gray-200 p-6">
        <h2 className="text-base font-semibold text-gray-900 mb-4">Top endpoints this month</h2>
        <ResponsiveContainer width="100%" height={280}>
          <PieChart>
            <Pie data={pieData} dataKey="total" nameKey="endpoint" cx="50%" cy="50%" outerRadius={100}
              label={({ endpoint, percent }: { endpoint: string; percent: number }) =>
                `${endpoint} (${(percent * 100).toFixed(0)}%)`}
              labelLine={false}>
              {pieData.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
            </Pie>
            <Tooltip contentStyle={{ borderRadius: 8, border: "1px solid #e5e7eb", fontSize: 12, backgroundColor: "#fff", color: "#111827" }}
              formatter={(v: number) => [v.toLocaleString(), "requests"]} />
          </PieChart>
        </ResponsiveContainer>
      </div>
    </div>
  )
}
