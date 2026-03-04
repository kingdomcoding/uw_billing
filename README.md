# uw_billing

Hi Dario — this is my take on what a billing and API metering system would look like
built on UW's stack: Ash, Oban, ClickHouse, Stripe, and React. It's meant to be
production-patterned, not a toy — every architectural choice here has a concrete reason
behind it that I'm happy to dig into.

The premise: UW's API is a monetized product. That means subscriptions, rate limiting,
metered usage tracking, and congressional trade data as a first-class domain. This
implements all three modules in one Phoenix app.

---

## What this implements

**Module 1 — Stripe billing engine**

Full subscription lifecycle via AshStateMachine:

```
free → trialing → active ⇄ past_due → canceled
                  active → paused → active
```

Idempotent Oban webhook processing. Upgrade/downgrade with scheduled plan change at
period end. Daily sync + dunning reaper via AshOban triggers. Invoice history via
Stripe invoice events.

The state machine isn't just aesthetics — `Billing.cancel_subscription(sub)` on an
already-canceled subscription returns `{:error, %Ash.Error.Invalid{}}` from the
framework, not from a guard I might forget to write.

**Module 2 — API usage tracking**

In-process `BufferServer` (GenServer) flushes batches to ClickHouse every 1 second
or every 500 rows, whichever comes first. `ApiUsageLogger` plug captures every
request with zero blocking — it uses `register_before_send` so the push fires after
the response is formed but before bytes hit the socket.

`SummingMergeTree` + Materialized View pre-aggregates the daily rollup so quota
checks query hundreds of rows, not billions. The rate-limit plug does one ClickHouse
read per metered request — correctness over cache approximation for the demo.

**Module 3 — Congressional Trade Watcher**

Oban-scheduled worker polling STOCK Act disclosures via the UW API, with EDGAR EFTS
as an always-available fallback. Upserts to Postgres with a field-enrichment strategy:
UW records overwrite EDGAR names (UW returns clean formatted names; EDGAR returns
whatever `display_names` contains). A Postgres trigger prevents NULL regression when
an EDGAR upsert would overwrite fields that UW previously enriched.

This one is deliberate domain signaling. Congressional trading transparency is UW's
identity — including it as a first-class domain shows I understand what UW actually is.

---

## The SPA — four pages

| URL | What it shows |
|-----|---------------|
| `/settings` | Stripe credential setup (secret key, publishable key, price IDs) and UW API key configuration. Live verification against both APIs. Green/amber dot in the nav reflects Stripe config state. |
| `/usage` | Daily request chart, endpoint breakdown, quota ring, P50/P95 latency — all from ClickHouse. |
| `/billing` | Subscription status, billing period, plan grid (Free / Pro / Premium), invoice history, and pause/resume/cancel actions. |
| `/trades` | Congressional stock disclosures table + ticker heatmap. House/Senate chamber badges. Issuer labels for spouse/joint trades. |

The Trades and Usage pages work immediately with seeded data — no Stripe account needed
to see them.

---

## Running it

### Docker — local demo or production

Fill in `.env` (copy from `.env.example`) with your Stripe credentials, then:

```bash
# Local demo
docker compose up

# Production (also needs SECRET_KEY_BASE, POSTGRES_PASSWORD, PHX_HOST in .env)
docker compose -f docker-compose.prod.yml up
```

On first start, the app container runs database creation, migrations, and seeding
before the HTTP server comes up. Subsequent starts skip setup that's already done
(seeds are idempotent).

Open [http://localhost:4200](http://localhost:4200). You land on `/trades`.

### Local mix — active development

For hot-reload and faster iteration:

```bash
docker compose up -d    # postgres + clickhouse only
source .env
bin/reset               # full wipe + re-seed (destructive)
mix phx.server
```

Use `bin/setup` instead of `bin/reset` when you want to run migrations and seeds
without dropping the database first.

### Testing Stripe billing end-to-end

1. Start the webhook forwarder: `stripe listen --forward-to localhost:4200/webhooks/stripe`
2. Enter credentials on `/settings` and click **Verify & Save**.
3. Trigger a test event:

```bash
stripe trigger customer.subscription.created
```

The webhook hits `/webhooks/stripe`, gets enqueued by Oban, processed by
`StripeWebhookWorker`, and the subscription appears in Postgres. Check `/billing` to
see the status update.

---

## Architecture: the key decisions

**Ash domains as the stable public API.** The standard Elixir stack has four layers per domain: schemas, changesets, contexts, queries. Ash collapses them into one resource file, with the domain block as the public API. `define :cancel_subscription, action: :cancel` generates both `f/n` and `f!/n` variants. Callers use `Billing.cancel_subscription(sub)`, never `Ash.update`. Validation is enforced at the action boundary via `accept [...]`, not a `cast/3` a developer might forget.

**AshOban colocates background jobs with resources.** The dunning and sync triggers live in the `Subscription` resource block — `where expr(status == :past_due and past_due_since <= ago(7, :day))`. AshOban generates the scheduler and worker modules at compile time. The invariants for when a subscription gets reaped live next to the state machine that governs transitions, not in a separate workers directory.

**Stripe webhook idempotency at three layers.** The controller returns 200 immediately and enqueues an Oban job — Stripe stops retrying. Oban's `unique: [keys: [:stripe_event_id], period: :infinity]` discards duplicate deliveries before they run. `StripeEvent` has a DB-level unique identity on `stripe_event_id` as a final backstop. Event ordering issues (e.g. `invoice.finalized` arriving before `subscription.created` is processed) are handled with `{:snooze, 30}` rather than hard errors.

**BufferServer + supervision tree ordering for zero-loss shutdown.** `BufferServer.push/1` is a `GenServer.cast` — fire-and-forget, never blocks the caller. On SIGTERM the supervision tree shuts down in reverse start order: Endpoint stops first, then Oban drains, then `BufferServer.terminate/2` flushes remaining events. The ClickHouse pool starts at position 3 and shuts down later, so it's still alive when the flush runs. No DETS, no external queue.

**Congress trade enrichment is protected at the DB level.** The upsert identity is semantic — `(trader_name, ticker, traded_at, transaction_type)` — because UW and EDGAR don't share a record ID. A Postgres `BEFORE UPDATE` trigger prevents EDGAR upserts from NULLing out fields that UW previously populated (`amount_range`, `politician_id`, `issuer`, `member_type`). Once set from UW, they're never regressed.

**The rate-limit plug makes an explicit tradeoff.** `EnforceRateLimit` does a synchronous ClickHouse query per metered request for non-premium users — exact counts, no stale cache. A production implementation would cache the monthly count in ETS with a TTL. `ApiUsageLogger` uses `register_before_send` so the duration includes the full request lifecycle but the ClickHouse push never delays the response. Internal paths are excluded so quota management never counts against your own quota.

---

## Production concerns already addressed

- **Webhook deduplication** — three layers as described above
- **Zero-downtime credential rotation** — Stripe and UW API keys resolve from the DB at call time, not cached at startup; updating via Settings takes effect immediately
- **Graceful shutdown** — 30-second BufferServer shutdown timeout; supervision tree ordering guarantees the ClickHouse pool outlives the flusher
- **Enrichment protection** — Postgres trigger prevents NULL regression on Congress trade fields; fires on every UPDATE, including migrations
- **Release-ready container** — multi-stage Alpine build; ~60MB runtime image; `config/runtime.exs` reads env vars at boot, not compile time
- **Metered path exclusions** — `/api/billing`, `/api/usage`, `/webhooks` are excluded from rate limiting; users can always reach account management at zero quota
- **Type-safe frontend contract** — `strict: true` TypeScript with union types for all enums; compiler catches backend contract changes before runtime

---

## What I'd build next

1. **Ash authorization policies** — `Ash.Policy.Authorizer` on `Subscription`, `Invoice`, and `StripeEvent`; `relates_to_actor_via(:user)` enforces row-level tenancy at the framework level with no migration
2. **Metered billing** — `:usage_metered` Plan tier; nightly `SyncUsageRecordsWorker` queries ClickHouse `daily_counts` and calls `Stripe.UsageRecord.create/3`; idempotent via `"#{user_id}-#{date}"` key
3. **Smart dunning** — `DunningPolicy` singleton resource with configurable `retry_days`; reaper calls `Stripe.Invoice.pay/2` on retry days and `cancel_subscription` at the terminal threshold
4. **Proration preview** — `GET /api/billing/plans/:id/preview` calls `Stripe.Invoice.upcoming/1` before the user commits to a plan change
5. **Webhook event replay** — admin endpoint listing `stripe_events` where `processed_at IS NULL`; replay via `Oban.insert!` with the original args
6. **Live trade push** — PubSub broadcast from `CongressTradePoller` on each batch; Phoenix Channel or SSE replaces the 30-second frontend poll
7. **ClickHouse trade archive** — mirror `congress_trades` to a `MergeTree` table for historical scale; replace in-memory `recent_summary/0` grouping with a `CongressClickHouse` query module

---

## Tests

```bash
mix test
```

**24 cases total:**
- 16 subscription state machine transition cases — covers every valid and invalid transition
  including `canceled` as a terminal state
- 8 `StripeWebhookWorker` cases — idempotency, snooze behavior, full subscription lifecycle
  (`created → updated → deleted`), payment failure and recovery

ClickHouse interactions and `CongressTradePoller` (network dependency) are not covered by
the test suite — those would require a test ClickHouse instance and VCR-style HTTP
fixtures, which felt out of scope for a demo.

---

Happy to walk through any part of this live. The whole backend is under 3k lines —
small enough to cover end-to-end in one session.
