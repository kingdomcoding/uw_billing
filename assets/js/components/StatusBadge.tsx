import React from "react"

const COLORS: Record<string, string> = {
  active:        "bg-green-100 text-green-800",
  trialing:      "bg-blue-100 text-blue-800",
  past_due:      "bg-amber-100 text-amber-800",
  paused:        "bg-gray-100 text-gray-600",
  canceled:      "bg-red-100 text-red-700",
  free:          "bg-gray-100 text-gray-600",
  paid:          "bg-green-100 text-green-800",
  open:          "bg-amber-100 text-amber-800",
  void:          "bg-gray-100 text-gray-500",
  uncollectible: "bg-red-100 text-red-700",
  purchase:      "bg-green-100 text-green-800",
  sale:          "bg-red-100 text-red-700",
  exchange:      "bg-gray-100 text-gray-600",
}

export default function StatusBadge({ status }: { status: string }) {
  const cls = COLORS[status] ?? "bg-gray-100 text-gray-600"
  return (
    <span className={`inline-block px-2 py-0.5 rounded text-xs font-medium ${cls}`}>
      {status.replace(/_/g, " ")}
    </span>
  )
}
