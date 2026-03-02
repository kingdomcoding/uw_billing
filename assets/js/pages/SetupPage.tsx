import React, { useEffect, useState } from "react"
import { useNavigate } from "react-router-dom"
import { api, StripeCredentials, StripeConfigStatus } from "../api"

interface FormState {
  secret_key: string
  webhook_secret: string
  price_id_pro: string
  price_id_premium: string
}

interface FieldErrors { [k: string]: string }

export default function SetupPage() {
  const navigate = useNavigate()
  const [status, setStatus]         = useState<StripeConfigStatus | null>(null)
  const [form, setForm]             = useState<FormState>({
    secret_key: "", webhook_secret: "", price_id_pro: "", price_id_premium: ""
  })
  const [errors, setErrors]         = useState<FieldErrors>({})
  const [submitting, setSubmitting] = useState(false)
  const [disabling, setDisabling]   = useState(false)
  const [globalError, setGlobalError] = useState<string | null>(null)
  const [demoCustomerId, setDemoCustomerId] = useState<string | null>(null)
  const [priceIdPro, setPriceIdPro] = useState<string | null>(null)

  const autoLogin = async () => {
    try {
      const { api_key } = await api.demoSession()
      localStorage.setItem("uw_api_key", api_key)
    } catch (_) {}
  }

  const load = () =>
    api.stripeConfig().then(s => {
      setStatus(s)
      if (s.custom_configured) {
        setForm(f => ({
          ...f,
          price_id_pro:     s.price_id_pro     ?? "",
          price_id_premium: s.price_id_premium ?? "",
        }))
      }
    }).catch(() => {})

  useEffect(() => { autoLogin(); load() }, [])

  const set = (field: keyof FormState) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setForm(f => ({ ...f, [field]: e.target.value }))

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setErrors({})
    setGlobalError(null)
    setSubmitting(true)
    try {
      const result = await api.verifyStripe(form as StripeCredentials)
      if ("configured" in result && result.configured) {
        await autoLogin()
        setDemoCustomerId(result.stripe_customer_id ?? null)
        setPriceIdPro(result.price_id_pro ?? null)
        await load()
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
      await load()
    } catch (err) {
      setGlobalError((err as Error).message ?? "Failed to revert credentials")
    } finally {
      setDisabling(false)
    }
  }

  const envConfigured    = status?.env_configured    === true
  const customConfigured = status?.custom_configured === true
  const skipAvailable    = envConfigured && !customConfigured
  const revertAvailable  = customConfigured && envConfigured

  return (
    <div className="space-y-8 max-w-2xl">
      <div>
        <h1 className="text-2xl font-semibold text-gray-900">Stripe Setup</h1>
        <p className="text-sm text-gray-500 mt-1">
          Enter your own Stripe test credentials to drive the billing features in this demo.
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
              type="button"
              onClick={handleDisable}
              disabled={disabling}
              className="text-xs text-gray-500 hover:text-red-600 whitespace-nowrap disabled:opacity-50">
              {disabling ? "Reverting..." : "Revert to app defaults"}
            </button>
          )}
        </div>
      )}

      {!customConfigured && envConfigured && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 flex items-start justify-between gap-4">
          <p className="text-sm text-blue-800">
            The app is running with default Stripe credentials (set by the app owner).
            Enter your own below to use your Stripe account instead.
          </p>
          <button
            type="button"
            onClick={() => navigate("/dashboard")}
            className="text-sm font-medium text-blue-700 hover:text-blue-900 whitespace-nowrap">
            Skip — use defaults
          </button>
        </div>
      )}

      <div className="bg-gray-50 border border-gray-200 rounded-lg p-5 text-sm text-gray-800 space-y-3">
        <div className="font-semibold text-gray-700">What you need from Stripe</div>
        <ol className="list-decimal list-inside space-y-2">
          <li>
            <strong>Log in to Stripe in test mode.</strong>{" "}
            <a href="https://dashboard.stripe.com" target="_blank" rel="noreferrer"
              className="underline text-blue-600">dashboard.stripe.com</a> → toggle Test mode on.
          </li>
          <li>
            <strong>Get your Secret Key.</strong>{" "}
            Developers → API keys → copy the <code className="bg-gray-200 px-1 rounded">sk_test_...</code> key.
          </li>
          <li>
            <strong>Create two products with monthly prices.</strong>{" "}
            Products → + Add product:
            <ul className="list-disc list-inside ml-4 mt-1 space-y-1">
              <li><strong>Pro</strong> — $49.00 / month (recurring). Copy the Price ID.</li>
              <li><strong>Premium</strong> — $99.00 / month (recurring). Copy the Price ID.</li>
            </ul>
          </li>
          <li>
            <strong>Start the Stripe CLI webhook forwarder</strong>{" "}
            (keep it running while you test):
            <pre className="bg-gray-200 rounded p-2 mt-1 text-xs font-mono">
              stripe listen --forward-to localhost:4000/webhooks/stripe
            </pre>
            Copy the <code className="bg-gray-200 px-1 rounded">whsec_...</code> secret shown in the terminal.
            <span className="block text-xs text-gray-500 mt-1">
              This secret changes every time you run stripe listen. Re-enter it here if you restart the CLI.
            </span>
          </li>
          <li>
            <strong>Enter all four values below</strong> and click Verify & Save.
            The app calls Stripe to validate each credential before accepting them.
          </li>
          <li>
            <strong>After saving, trigger a test event</strong> to confirm the webhook pipeline:
            <pre className="bg-gray-200 rounded p-2 mt-1 text-xs font-mono">
              stripe trigger customer.subscription.created
            </pre>
          </li>
        </ol>
      </div>

      <form onSubmit={handleSubmit} className="bg-white rounded-lg border border-gray-200 p-6 space-y-5">
        {globalError && (
          <div className="bg-red-50 border border-red-200 rounded p-3 text-sm text-red-700">
            {globalError}
          </div>
        )}

        {([
          { field: "secret_key",       label: "Secret Key",             placeholder: "sk_test_...", type: "password" },
          { field: "webhook_secret",   label: "Webhook Signing Secret", placeholder: "whsec_...",  type: "password" },
          { field: "price_id_pro",     label: "Pro Plan Price ID",      placeholder: "price_...",  type: "text"     },
          { field: "price_id_premium", label: "Premium Plan Price ID",  placeholder: "price_...",  type: "text"     },
        ] as const).map(({ field, label, placeholder, type }) => (
          <div key={field}>
            <label className="block text-sm font-medium text-gray-700 mb-1">{label}</label>
            {customConfigured && (field === "secret_key" || field === "webhook_secret") && (
              <p className="text-xs text-gray-400 mb-1">
                Currently set (masked). Leave blank to keep existing, or enter a new value to replace.
              </p>
            )}
            <input
              type={type}
              value={form[field]}
              onChange={set(field)}
              placeholder={placeholder}
              className={`w-full text-sm text-gray-900 border rounded px-3 py-2 font-mono ${
                errors[field] ? "border-red-400 bg-red-50" : "border-gray-200 bg-white"
              }`}
            />
            {errors[field] && (
              <p className="text-xs text-red-600 mt-1">{errors[field]}</p>
            )}
          </div>
        ))}

        <div className="flex items-center gap-3 pt-2">
          <button
            type="submit"
            disabled={submitting}
            className="px-4 py-2 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 disabled:opacity-50">
            {submitting ? "Verifying with Stripe..." : "Verify & Save"}
          </button>
          {skipAvailable && (
            <button type="button" onClick={() => navigate("/dashboard")}
              className="text-sm text-gray-500 hover:text-gray-700">
              Skip — use app defaults
            </button>
          )}
        </div>
      </form>

      {demoCustomerId && (
        <SubscribePanel onDone={() => navigate("/billing")} />
      )}

      <p className="text-xs text-gray-500">
        In a real deployment these credentials would be environment variables managed as secrets.
        This page exists solely for demo convenience — it lets reviewers use their own Stripe
        test account without modifying server configuration.
      </p>
    </div>
  )
}

function SubscribePanel({ onDone }: { onDone: () => void }) {
  const [state, setState] = useState<"idle" | "loading" | "done" | "error">("idle")
  const [error, setError] = useState<string | null>(null)

  const subscribe = async () => {
    setState("loading")
    try {
      await api.demoSubscribe()
      setState("done")
    } catch (e) {
      setError((e as Error).message)
      setState("error")
    }
  }

  return (
    <div className="bg-green-50 border border-green-300 rounded-lg p-5 space-y-3">
      <p className="text-sm font-semibold text-green-800">Credentials saved!</p>
      <p className="text-sm text-green-700">
        Click below to create a test Pro subscription and fire the webhook pipeline end-to-end.
        Make sure <code className="bg-green-100 px-1 rounded">stripe listen</code> is running first.
      </p>
      {state === "error" && (
        <p className="text-sm text-red-600">{error}</p>
      )}
      {state === "done" ? (
        <div className="space-y-2">
          <p className="text-sm text-green-800 font-medium">Subscription created — webhook is processing.</p>
          <button onClick={onDone}
            className="px-4 py-2 text-sm bg-green-700 text-white rounded hover:bg-green-800">
            Go to Billing →
          </button>
        </div>
      ) : (
        <div className="flex gap-3">
          <button
            disabled={state === "loading"}
            onClick={subscribe}
            className="px-4 py-2 text-sm bg-green-700 text-white rounded hover:bg-green-800 disabled:opacity-50">
            {state === "loading" ? "Creating subscription…" : "Create test subscription"}
          </button>
          <button onClick={onDone}
            className="px-4 py-2 text-sm border border-gray-300 rounded hover:bg-gray-50 text-gray-600">
            Skip → Go to Billing
          </button>
        </div>
      )}
    </div>
  )
}
