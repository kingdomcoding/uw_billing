import React, { useEffect, useState } from "react"
import { api, AccountInfo } from "../api"

export default function AccountPage() {
  const [account, setAccount] = useState<AccountInfo | null>(null)
  const [loading, setLoading] = useState(true)
  const [copied, setCopied] = useState(false)

  useEffect(() => {
    api.account()
      .then(a => { setAccount(a); setLoading(false) })
      .catch(() => setLoading(false))
  }, [])

  const copyKey = () => {
    if (!account) return
    navigator.clipboard.writeText(account.api_key).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    })
  }

  if (loading) return <div className="p-8 text-gray-500">Loading...</div>

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-semibold text-gray-900">Account</h1>
      <div className="bg-white rounded-lg border border-gray-200 p-6 space-y-4">
        <div>
          <div className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">Email</div>
          <div className="text-sm text-gray-900">{account?.email}</div>
        </div>
        <div>
          <div className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">API Key</div>
          <div className="flex items-center gap-2">
            <code className="text-xs text-gray-900 bg-gray-50 border border-gray-200 rounded px-3 py-2 flex-1 font-mono truncate">
              {account?.api_key}
            </code>
            <button
              onClick={copyKey}
              className="text-xs text-gray-700 px-3 py-2 border border-gray-200 rounded hover:bg-gray-50 shrink-0">
              {copied ? "Copied!" : "Copy"}
            </button>
          </div>
          <p className="text-xs text-gray-500 mt-1">
            Pass this as the <code className="font-mono">X-Api-Key</code> header on all API requests.
          </p>
        </div>
      </div>
    </div>
  )
}
