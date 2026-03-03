import React from "react"
import { Link } from "react-router-dom"
import { ApiError } from "../api"

interface Props {
  error: ApiError | Error | string
  onRetry?: () => void
}

export default function ErrorBanner({ error, onRetry }: Props) {
  const isRateLimit = error instanceof ApiError && error.status === 429
  const limit = isRateLimit ? (error.body?.limit as number | undefined) : undefined

  if (isRateLimit) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-lg px-4 py-4 flex items-start justify-between gap-4">
        <div>
          <p className="text-sm font-semibold text-red-800">Monthly request limit reached</p>
          <p className="text-sm text-red-700 mt-0.5">
            {limit
              ? `You've used all ${limit.toLocaleString()} requests included in your plan this month.`
              : "You've reached your monthly request limit."}
            {" "}Upgrade to Premium for unlimited access.
          </p>
        </div>
        <Link
          to="/billing"
          className="shrink-0 px-3 py-1.5 bg-red-700 text-white rounded text-sm font-medium hover:bg-red-800"
        >
          Upgrade →
        </Link>
      </div>
    )
  }

  const message = typeof error === "string" ? error : error.message

  return (
    <div className="bg-red-50 border border-red-200 rounded-lg p-4 flex items-center justify-between gap-4 text-sm">
      <span className="text-red-700">{message}</span>
      {onRetry && (
        <button
          onClick={onRetry}
          className="shrink-0 text-red-700 underline hover:text-red-900"
        >
          Retry
        </button>
      )}
    </div>
  )
}
