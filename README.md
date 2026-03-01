# uw_billing

A production-patterned Elixir/Phoenix billing + API usage tracking system,
built to demonstrate the architecture I'd bring to the Unusual Whales backend role.

## What this implements

**Module 1 — Stripe billing engine**
Full subscription lifecycle (`free → trialing → active → past_due → paused → canceled`)
via AshStateMachine. Idempotent Oban webhook processing. Upgrade/downgrade with
scheduled plan change at period end. Daily sync + dunning reaper via AshOban triggers.
Invoice history via Stripe invoice events.

**Module 2 — API usage tracking**
In-process BufferServer flushes batches to ClickHouse. ApiUsageLogger Plug captures
every request with zero blocking. Materialized View pre-aggregates daily rollup.

**Module 3 — Congressional Trade Watcher**
Oban-scheduled worker polling STOCK Act disclosures via the UW API (or EDGAR EFTS
as a fallback). Upserts to Postgres via the Congress domain. ~80 lines total.
Shows genuine domain awareness: UW's core identity is congressional trading transparency.

## React SPA — seven pages

| URL | What you see |
|-----|--------------|
| `/setup` | **First-time entry point.** Step-by-step Stripe setup guide + live credential verification. Green/amber dot in the nav shows configuration status. |
| `/dashboard` | Daily request chart, endpoint breakdown, quota progress, P50/P95 latency |
| `/billing` | Subscription status badge, period dates, pause/resume/cancel actions |
| `/billing/plans` | Three-column plan grid (Free / Pro / Premium) with instant plan switching |
| `/billing/invoices` | Full invoice history with amount, status, and payment date |
| `/account` | Email and copyable API key |
| `/trades` | Congressional stock disclosures table + active ticker heatmap |

Set your API key once in the nav bar input — it persists via `localStorage` for the session.

## Architecture decisions

### Why Ash Framework

Ash provides a unified layer for resources (schema + validation), domains (public API),
actions (CRUD + custom), AshStateMachine (declarative transitions), AshOban (per-record
cron triggers), and AshJsonApi (JSON:API endpoint generation). The result: no separate
Ecto schemas, changeset modules, or context functions. The domain is the public API;
resources are implementation details. AshStateMachine raises `Ash.Error.Invalid` on
invalid transitions rather than relying on every caller to check a guard function.

### Why Oban for webhook processing, not inline

Stripe retries on non-2xx responses. Without durable idempotent processing, an upgrade
event delivered twice would double-charge or corrupt subscription state. The controller
returns 200 immediately. Oban's `unique` constraint (keyed on Stripe event ID,
`period: :infinity`) ensures exactly-once execution. A secondary `stripe_events`
uniqueness check catches the edge case where a worker crashes post-processing.

### Why Ash domains as the public API, not resource modules

Callers should not know which resource a function delegates to. `Billing.cancel_subscription(sub)`
is stable across refactors; `Subscription.cancel!(sub)` leaks the resource name.
`define` in the domain block auto-generates both `f/n` and `f!/n` variants — no boilerplate.

### Why ClickHouse for usage data

At UW's scale, `api_requests` accumulates billions of rows. Columnar MergeTree with
monthly partitioning and a Materialized View rollup makes per-user analytical queries
run in milliseconds. PostgreSQL at the same scale requires sequential scans or
oversized indexes that degrade with time.

### Why BufferServer flushes directly on shutdown (not DETS)

DETS is node-local — it does not survive a container replacement or rollout. Instead,
the supervision tree is arranged so the ClickHouse pool (child #2) outlives the
BufferServer (child #5) on shutdown. `Process.flag(:trap_exit, true)` ensures
`terminate/2` is called on SIGTERM, and a 30-second `child_spec` shutdown timeout
gives the flush enough time to complete.

## Running locally

```bash
docker compose up -d
mix deps.get
mix ash.setup          # creates DB, runs Ash migrations, seeds plans + demo user
cd assets && npm install
mix phx.server         # http://localhost:4000
```

`mix ash.setup` prints the seeded demo user's API key. Copy it.

Open [http://localhost:4000](http://localhost:4000) — you'll land on `/setup`.

1. Paste the API key into the nav bar input.
2. Follow the on-page instructions to create a Stripe test account and get your credentials.
3. Start the webhook forwarder: `stripe listen --forward-to localhost:4000/webhooks/stripe`
4. Enter all four credentials in the form and click **Verify & Save**.
5. On success you're redirected to `/dashboard` — all billing features are now live.

**Test a billing event end-to-end:**
```bash
stripe trigger customer.subscription.created
```

The webhook arrives at `/webhooks/stripe`, is enqueued by Oban, processed by
`StripeWebhookWorker`, and the subscription row appears in Postgres. Check `/billing`
in the SPA to see the subscription status update.

## Running tests

```bash
mix test
```

Covers: subscription state machine transitions (16 cases), StripeWebhookWorker
idempotency and full lifecycle (8 cases).

## What I'd build next

1. **Metered billing** — Stripe Usage Records for API-tier plans billed per request.
2. **Smart dunning** — configurable retry cadence (day 1, 3, 7, 14) before cancel.
3. **Usage-based upgrade prompts** — AshOban trigger querying ClickHouse for users
   approaching their monthly limit, firing an Ash notification action.
4. **Webhook event replay** — LiveView admin page listing failed `stripe_events`
   with an `Oban.insert!` replay button for incident recovery.
5. **Ash authorization policies** — `Ash.Policy.Authorizer` ensuring users can
   only read their own subscriptions and usage data, enforced at the resource level.
