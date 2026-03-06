import React, { useEffect, useState } from "react"
import { Link } from "react-router-dom"
import { api } from "../api"

interface OverviewStatus {
  configured: boolean
  has_subscription: boolean
}

const FEATURES = [
  {
    to: "/trades",
    title: "Congressional Trades",
    desc: "Real-time STOCK Act disclosure tracker. Pulls from the Unusual Whales API with SEC EDGAR fallback. Supports search, ticker filtering, and background polling via Oban.",
    tech: ["Req HTTP client", "Oban background jobs", "Ash resources", "Postgres"],
    color: "blue",
  },
  {
    to: "/usage",
    title: "API Usage Metering",
    desc: "Per-request usage tracking with daily breakdowns, endpoint heatmaps, and P50/P95 latency. Includes a live API sandbox \u2014 fire a request and watch it appear in the charts.",
    tech: ["ClickHouse analytics", "Plug pipeline", "Recharts", "BufferServer GenServer"],
    color: "violet",
  },
  {
    to: "/billing",
    title: "Stripe Billing",
    desc: "Full subscription lifecycle: subscribe, upgrade (immediate proration), downgrade (end-of-period), pause, resume, cancel. Webhook-driven state machine keeps local state in sync.",
    tech: ["Stripe API", "Ash state machine", "Webhook signature verification", "Oban workers"],
    color: "emerald",
  },
  {
    to: "/settings",
    title: "Configuration",
    desc: "Credential management for Stripe and Unusual Whales API keys. Validates against live APIs before saving. Supports both env vars and DB-stored overrides.",
    tech: ["Runtime config", "Stripe Balance.retrieve verification"],
    color: "amber",
  },
] as const

type FeatureColor = typeof FEATURES[number]["color"]

const BORDER_COLORS: Record<FeatureColor, string> = {
  blue: "hover:border-blue-400",
  violet: "hover:border-violet-400",
  emerald: "hover:border-emerald-400",
  amber: "hover:border-amber-400",
}

const TAG_COLORS: Record<FeatureColor, string> = {
  blue: "bg-blue-50 text-blue-700",
  violet: "bg-violet-50 text-violet-700",
  emerald: "bg-emerald-50 text-emerald-700",
  amber: "bg-amber-50 text-amber-700",
}

interface PipelineStep {
  label: string
  sub: string
}

function PipelineRow({ label, steps }: { label: string; steps: PipelineStep[] }) {
  return (
    <div className="space-y-1.5">
      <div className="text-xs font-medium text-gray-400 uppercase tracking-wide">{label}</div>
      <div className="flex items-center gap-1.5">
        {steps.map((step, i) => (
          <React.Fragment key={step.label}>
            {i > 0 && <span className="text-gray-300 text-sm shrink-0">&rarr;</span>}
            <div className="bg-gray-50 border border-gray-200 rounded px-3 py-1.5 text-center flex-1 min-w-0">
              <div className="text-xs font-semibold text-gray-800 truncate">{step.label}</div>
              <div className="text-xs text-gray-400 truncate">{step.sub}</div>
            </div>
          </React.Fragment>
        ))}
      </div>
    </div>
  )
}

export default function OverviewPage() {
  const [status, setStatus] = useState<OverviewStatus | null>(null)

  useEffect(() => {
    api.setupStatus().then(setStatus).catch(() => {})
  }, [])

  return (
    <div className="space-y-10">

      <div className="space-y-3">
        <h1 className="text-3xl font-bold text-gray-900 tracking-tight">
          SaaS Billing &amp; Usage Platform
        </h1>
        <p className="text-base text-gray-600 leading-relaxed max-w-2xl">
          A full-stack Elixir demo &mdash; a SaaS API product that sells congressional
          stock trade data, meters every request through ClickHouse, and manages
          the entire subscription lifecycle through Stripe.
        </p>
        <div className="flex flex-wrap gap-2 pt-1">
          {["Phoenix 1.8", "Ash Framework", "Stripe", "ClickHouse", "Oban", "React", "TypeScript"].map(t => (
            <span key={t} className="px-2 py-0.5 bg-gray-100 text-gray-600 rounded text-xs font-medium">
              {t}
            </span>
          ))}
        </div>
      </div>

      {status && (
        <div className="flex items-center gap-4 text-sm">
          <span className="flex items-center gap-1.5">
            <span className={`w-2 h-2 rounded-full ${status.configured ? "bg-green-500" : "bg-amber-400"}`} />
            Stripe: {status.configured ? "configured" : "using defaults"}
          </span>
          <span className="flex items-center gap-1.5">
            <span className={`w-2 h-2 rounded-full ${status.has_subscription ? "bg-green-500" : "bg-gray-300"}`} />
            Subscription: {status.has_subscription ? "active" : "none"}
          </span>
          <span className="text-gray-400">&middot;</span>
          <span className="text-gray-500">
            You're signed in as a demo user &mdash; all Stripe charges use test mode.
          </span>
        </div>
      )}

      <div className="bg-blue-50 border border-blue-200 rounded-lg px-5 py-4">
        <p className="text-sm text-blue-900">
          <span className="font-semibold">Suggested walkthrough:</span>{" "}
          <Link to="/trades" className="underline">Trades</Link> (the product) &rarr;{" "}
          <Link to="/usage" className="underline">API Usage</Link> (fire requests in the sandbox, watch charts update) &rarr;{" "}
          <Link to="/billing" className="underline">Billing</Link> (subscribe, upgrade, pause &mdash; full lifecycle) &rarr;{" "}
          <Link to="/settings" className="underline">Settings</Link> (plug in your own Stripe test keys)
        </p>
      </div>

      <div className="grid grid-cols-2 gap-4">
        {FEATURES.map(f => (
          <Link
            key={f.to}
            to={f.to}
            className={`bg-white rounded-lg border border-gray-200 p-5 space-y-3 transition-colors ${BORDER_COLORS[f.color]}`}
          >
            <div className="text-base font-semibold text-gray-900">{f.title}</div>
            <p className="text-sm text-gray-600 leading-relaxed">{f.desc}</p>
            <div className="flex flex-wrap gap-1.5">
              {f.tech.map(t => (
                <span key={t} className={`px-1.5 py-0.5 rounded text-xs font-medium ${TAG_COLORS[f.color]}`}>
                  {t}
                </span>
              ))}
            </div>
          </Link>
        ))}
      </div>

      <div className="bg-white rounded-lg border border-gray-200 p-6 space-y-5">
        <h2 className="text-base font-semibold text-gray-900">Architecture</h2>
        <div className="space-y-4">
          <PipelineRow
            label="Data Pipeline"
            steps={[
              { label: "UW API / EDGAR", sub: "data source" },
              { label: "Oban Worker", sub: "6h poll" },
              { label: "Postgres", sub: "Ash resources" },
              { label: "JSON API", sub: "Phoenix" },
              { label: "React SPA", sub: "TypeScript" },
            ]}
          />
          <PipelineRow
            label="Usage Metering"
            steps={[
              { label: "API Request", sub: "any client" },
              { label: "Plug Pipeline", sub: "auth + rate limit" },
              { label: "BufferServer", sub: "GenServer" },
              { label: "ClickHouse", sub: "analytics" },
              { label: "Usage Charts", sub: "Recharts" },
            ]}
          />
          <PipelineRow
            label="Billing Lifecycle"
            steps={[
              { label: "Stripe Event", sub: "webhook" },
              { label: "Sig Verify", sub: "Plug" },
              { label: "Oban Worker", sub: "async processing" },
              { label: "State Machine", sub: "Ash states" },
              { label: "Billing UI", sub: "React" },
            ]}
          />
        </div>
      </div>

      <div className="bg-gray-50 rounded-lg border border-gray-200 p-6 space-y-3">
        <h2 className="text-base font-semibold text-gray-900">Key Code Locations</h2>
        <div className="grid grid-cols-2 gap-x-8 gap-y-1.5 text-sm font-mono text-gray-600">
          <div><span className="text-gray-400">Subscription state machine</span></div>
          <div>lib/uw_billing/billing/subscription.ex</div>
          <div><span className="text-gray-400">Stripe webhook worker</span></div>
          <div>lib/uw_billing/workers/stripe_webhook_worker.ex</div>
          <div><span className="text-gray-400">Usage buffer (GenServer)</span></div>
          <div>lib/uw_billing/usage/buffer_server.ex</div>
          <div><span className="text-gray-400">ClickHouse queries</span></div>
          <div>lib/uw_billing/usage/click_house.ex</div>
          <div><span className="text-gray-400">Rate limiter plug</span></div>
          <div>lib/uw_billing_web/plugs/enforce_rate_limit.ex</div>
          <div><span className="text-gray-400">Congress trade poller</span></div>
          <div>lib/uw_billing/congress.ex</div>
          <div><span className="text-gray-400">React SPA entry</span></div>
          <div>assets/js/app.tsx</div>
        </div>
      </div>

    </div>
  )
}
