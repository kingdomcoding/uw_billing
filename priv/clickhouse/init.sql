CREATE DATABASE IF NOT EXISTS uw_billing;

CREATE TABLE IF NOT EXISTS uw_billing.api_requests
(
    user_id      UInt64,
    plan_tier    LowCardinality(String),
    method       LowCardinality(String),
    path         LowCardinality(String),
    status_code  UInt16,
    duration_ms  Float32,
    error        UInt8 DEFAULT 0,
    timestamp    DateTime
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (user_id, timestamp)
TTL timestamp + INTERVAL 2 YEAR
SETTINGS index_granularity = 8192;

CREATE TABLE IF NOT EXISTS uw_billing.api_requests_daily
(
    user_id       UInt64,
    plan_tier     LowCardinality(String),
    path          LowCardinality(String),
    date          Date,
    request_count UInt64,
    error_count   UInt64,
    p50_ms        Float32,
    p95_ms        Float32
)
ENGINE = SummingMergeTree((request_count, error_count))
PARTITION BY toYYYYMM(date)
ORDER BY (user_id, date, path);

CREATE MATERIALIZED VIEW IF NOT EXISTS uw_billing.api_requests_daily_mv
TO uw_billing.api_requests_daily
AS
SELECT
    user_id,
    plan_tier,
    path,
    toDate(timestamp)           AS date,
    count()                     AS request_count,
    countIf(error = 1)          AS error_count,
    quantile(0.50)(duration_ms) AS p50_ms,
    quantile(0.95)(duration_ms) AS p95_ms
FROM uw_billing.api_requests
GROUP BY user_id, plan_tier, path, date;
