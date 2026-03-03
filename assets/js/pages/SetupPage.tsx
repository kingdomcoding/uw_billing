import React, { useEffect, useState, useRef } from "react"
import { useNavigate, useOutletContext } from "react-router-dom"
import { api, StripeCredentials, StripeConfigStatus } from "../api"

type OutletCtx = { refreshStripe: () => void; refreshSub: () => void }
type FormState = { secret_key: string; webhook_secret: string }
type ProvState = "idle" | "provisioning" | "done" | "timeout"

export default function SetupPage() {
  const navigate = useNavigate()
  const { refreshStripe, refreshSub } = useOutletContext<OutletCtx>()

  const [status, setStatus]           = useState<StripeConfigStatus | null>(null)
  const [form, setForm]               = useState<FormState>({ secret_key: "", webhook_secret: "" })
  const [errors, setErrors]           = useState<Record<string, string>>({})
  const [submitting, setSubmitting]   = useState(false)
  const [disabling, setDisabling]     = useState(false)
  const [globalError, setGlobalError] = useState<string | null>(null)
  const [prov, setProv]               = useState<ProvState>("idle")
  const [elapsed, setElapsed]         = useState(0)
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const load = () => api.stripeConfig().then(setStatus).catch(() => {})
  useEffect(() => { load() }, [])

  const set = (field: keyof FormState) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setForm(f => ({ ...f, [field]: e.target.value }))

  const runProvision = async () => {
    const existing = await api.subscription().catch(() => null)
    if (existing) { refreshSub(); navigate("/billing"); return }

    setProv("provisioning")
    setElapsed(0)
    timerRef.current = setInterval(() => setElapsed(n => n + 1), 1000)
    try {
      await api.demoSubscribe()
      for (let i = 0; i < 15; i++) {
        await new Promise(r => setTimeout(r, 2000))
        const sub = await api.subscription()
        if (sub) {
          await api.seedDemoInvoices().catch(() => null)
          setProv("done")
          clearInterval(timerRef.current!)
          refreshSub()
          setTimeout(() => navigate("/billing"), 1200)
          return
        }
      }
      setProv("timeout")
    } catch {
      setProv("timeout")
    } finally {
      if (timerRef.current) clearInterval(timerRef.current)
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setErrors({})
    setGlobalError(null)
    setSubmitting(true)
    try {
      const result = await api.verifyStripe(form as StripeCredentials)
      if ("configured" in result && result.configured) {
        refreshStripe()
        await load()
        await runProvision()
      } else if ("errors" in result) {
        setErrors(result.errors)
      }
    } catch (err) {
      setGlobalError((err as Error).message ?? "Verification failed")
    } finally {
      setSubmitting(false)
    }
  }

  const handleDisable = async () => {
    setDisabling(true)
    try {
      await api.disableStripe()
      refreshStripe()
      await load()
    } catch (err) {
      setGlobalError((err as Error).message ?? "Failed to revert credentials")
    } finally {
      setDisabling(false)
    }
  }

  if (prov === "provisioning" || prov === "done") {
    return (
      <div className="max-w-2xl">
        <div className="bg-white rounded-lg border border-gray-200 p-10 text-center space-y-4">
          {prov === "done" ? (
            <>
              <div className="text-4xl text-green-500">✓</div>
              <p className="text-base font-semibold text-gray-900">Subscription ready!</p>
              <p className="text-sm text-gray-500">Taking you to Billing…</p>
            </>
          ) : (
            <>
              <div className="w-6 h-6 border-2 border-blue-500 border-t-transparent rounded-full animate-spin mx-auto" />
              <p className="text-sm font-medium text-gray-900">Setting up your demo subscription…</p>
              <p className="text-xs text-gray-400">{elapsed}s</p>
              {elapsed >= 10 && (
                <p className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded px-3 py-2">
                  Waiting for Stripe webhook —{" "}
                  make sure <code className="font-mono">stripe listen --forward-to {window.location.origin}/webhooks/stripe</code>{" "}
                  is running.
                </p>
              )}
            </>
          )}
        </div>
      </div>
    )
  }

  if (prov === "timeout") {
    return (
      <div className="max-w-2xl">
        <div className="bg-amber-50 rounded-lg border border-amber-200 p-6 space-y-3">
          <p className="text-sm font-semibold text-amber-800">Subscription setup timed out</p>
          <p className="text-sm text-amber-700">
            Credentials were saved but the webhook didn't confirm within 30s.
            Make sure <code className="font-mono bg-amber-100 px-1 rounded">stripe listen</code> is
            running, then navigate to Billing — it will pick up the subscription automatically.
          </p>
          <button
            onClick={() => navigate("/billing")}
            className="px-4 py-2 text-sm bg-amber-700 text-white rounded hover:bg-amber-800">
            Go to Billing →
          </button>
        </div>
      </div>
    )
  }

  const envConfigured    = status?.env_configured    === true
  const customConfigured = status?.custom_configured === true
  const revertAvailable  = customConfigured && envConfigured
  const webhookUrl       = `${window.location.origin}/webhooks/stripe`

  return (
    <div className="space-y-8 max-w-2xl">
      <div>
        <h1 className="text-2xl font-semibold text-gray-900">Stripe Setup</h1>
        <p className="text-sm text-gray-500 mt-1">
          Enter your Stripe test credentials. Pro and Premium products will be created
          in your account automatically.
        </p>
      </div>

      {customConfigured && (
        <div className="bg-green-50 border border-green-300 rounded-lg p-4 flex items-start justify-between gap-4">
          <div>
            <p className="text-sm font-medium text-green-800">
              ✓ Using your Stripe credentials (verified {status?.verified_at?.slice(0, 10)})
            </p>
            <p className="text-xs text-green-700 mt-0.5">
              Re-enter credentials below to update them.
            </p>
          </div>
          {revertAvailable && (
            <button
              type="button" onClick={handleDisable} disabled={disabling}
              className="text-xs px-2.5 py-1 border border-gray-300 rounded bg-white text-gray-600 hover:border-red-400 hover:text-red-600 whitespace-nowrap disabled:opacity-50">
              {disabling ? "Reverting…" : "Revert to app defaults"}
            </button>
          )}
        </div>
      )}

      {!customConfigured && envConfigured && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 flex items-start justify-between gap-4">
          <p className="text-sm text-blue-800">
            The app is running with my default Stripe credentials.
            Enter your own below to use your Stripe account instead.
          </p>
          <button
            type="button" onClick={runProvision}
            className="text-sm px-3 py-1.5 bg-blue-600 text-white rounded hover:bg-blue-700 whitespace-nowrap shrink-0">
            Skip — use defaults
          </button>
        </div>
      )}

      <div className="bg-gray-50 border border-gray-200 rounded-lg p-5 text-sm text-gray-800 space-y-4">
        <div className="font-semibold text-gray-700">What you need from Stripe</div>

        <div className="space-y-1">
          <div className="font-medium text-gray-700">Step 1 — Get your Secret Key</div>
          <p className="text-gray-600">
            Log in to{" "}
            <a href="https://dashboard.stripe.com" target="_blank" rel="noreferrer"
              className="underline text-blue-600">dashboard.stripe.com</a>{" "}
            in test mode → Developers → API keys → copy the{" "}
            <code className="bg-gray-200 px-1 rounded">sk_test_...</code> key.
          </p>
        </div>

        <div className="space-y-2">
          <div className="font-medium text-gray-700">Step 2 — Register the webhook endpoint</div>
          <p className="text-xs text-gray-500 mb-1">
            Your webhook URL:{" "}
            <code className="bg-gray-200 px-1 rounded font-mono">{webhookUrl}</code>
          </p>
          <div className="grid grid-cols-2 gap-3">
            <div className="bg-white border border-gray-200 rounded p-3 space-y-1">
              <div className="text-xs font-semibold text-gray-700">Option A — Stripe Dashboard</div>
              <ol className="text-xs text-gray-600 space-y-1 list-decimal list-inside">
                <li>Developers → Webhooks → Add endpoint</li>
                <li>URL: <code className="bg-gray-100 px-0.5 rounded break-all">{webhookUrl}</code></li>
                <li>Subscribe to <code className="bg-gray-100 px-0.5 rounded">customer.subscription.*</code> and <code className="bg-gray-100 px-0.5 rounded">invoice.*</code></li>
                <li>Copy the Signing secret (<code className="bg-gray-100 px-0.5 rounded">whsec_...</code>)</li>
              </ol>
            </div>
            <div className="bg-white border border-gray-200 rounded p-3 space-y-1">
              <div className="text-xs font-semibold text-gray-700">Option B — CLI forwarder (local)</div>
              <p className="text-xs text-gray-600">Keep this running while you test:</p>
              <pre className="bg-gray-100 rounded p-2 text-xs font-mono break-all whitespace-pre-wrap">{`stripe listen --forward-to ${webhookUrl}`}</pre>
              <p className="text-xs text-gray-500">
                Copy the <code className="bg-gray-100 px-0.5 rounded">whsec_...</code> secret printed in the terminal.
              </p>
            </div>
          </div>
        </div>

        <div className="space-y-1">
          <div className="font-medium text-gray-700">Step 3 — Enter both values below and click Verify &amp; Save</div>
          <p className="text-gray-600">
            The app will validate your key and automatically create Pro ($49/mo) and Premium
            ($99/mo) products in your Stripe account, then provision a demo subscription.
          </p>
        </div>
      </div>

      <form onSubmit={handleSubmit} className="bg-white rounded-lg border border-gray-200 p-6 space-y-5">
        {globalError && (
          <div className="bg-red-50 border border-red-200 rounded p-3 text-sm text-red-700">
            {globalError}
          </div>
        )}

        {([
          { field: "secret_key",     label: "Secret Key",             placeholder: "sk_test_...", type: "password" },
          { field: "webhook_secret", label: "Webhook Signing Secret", placeholder: "whsec_...",  type: "password" },
        ] as const).map(({ field, label, placeholder, type }) => (
          <div key={field}>
            <label className="block text-sm font-medium text-gray-700 mb-1">{label}</label>
            {customConfigured && (
              <p className="text-xs text-gray-400 mb-1">
                Currently set (masked). Leave blank to keep existing, or enter a new value to replace.
              </p>
            )}
            <input
              type={type} value={form[field]} onChange={set(field)} placeholder={placeholder}
              className={`w-full text-sm text-gray-900 border rounded px-3 py-2 font-mono ${
                errors[field] ? "border-red-400 bg-red-50" : "border-gray-200 bg-white"
              }`}
            />
            {errors[field] && <p className="text-xs text-red-600 mt-1">{errors[field]}</p>}
          </div>
        ))}

        <div className="flex items-center gap-3 pt-2">
          <button
            type="submit" disabled={submitting}
            className="px-4 py-2 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 disabled:opacity-50">
            {submitting ? "Verifying with Stripe…" : "Verify & Save"}
          </button>
        </div>
      </form>

      <p className="text-xs text-gray-500">
        In a real deployment these credentials would be environment variables managed as secrets.
        This page exists solely for demo convenience.
      </p>
    </div>
  )
}
