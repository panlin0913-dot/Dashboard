# Payment Monitoring Demo (MySQL)

This demo uses virtual data for:

- Transactions
- Refunds
- Chargebacks
- Fraud events

It supports both:

- Platform-wide daily/monthly monitoring
- Per-merchant daily/monthly monitoring

## 1) Create schema

```bash
mysql -u root -p < sql/01_schema.sql
```

## 2) Create metrics views

```bash
mysql -u root -p < sql/02_metrics_views.sql
```

## 3) Generate demo seed SQL

```bash
python scripts/generate_demo_data.py --merchants 80 --days 120 --tx-per-day 1500
```

By default, this generates `sql/03_seed_demo.sql`.

If your machine has no Python, use MySQL-only generator:

```bash
mysql -u root -p < sql/03_seed_demo_mysql_only.sql
```

Then run (Excel-required 6 months):

```sql
CALL demo_payments.sp_generate_demo_data('202512', '202605');
```

## 4) Load demo seed data

```bash
mysql -u root -p < sql/03_seed_demo.sql
```

## 5) Query metrics

Platform daily:

```sql
SELECT * FROM demo_payments.vw_platform_daily_metrics ORDER BY stat_date DESC LIMIT 30;
```

Platform monthly:

```sql
SELECT * FROM demo_payments.vw_platform_monthly_metrics ORDER BY stat_month DESC;
```

Merchant daily (example merchant):

```sql
SELECT *
FROM demo_payments.vw_merchant_daily_metrics
WHERE merchant_id = 'M00001'
ORDER BY stat_date DESC
LIMIT 30;
```

Merchant monthly:

```sql
SELECT *
FROM demo_payments.vw_merchant_monthly_metrics
WHERE merchant_id = 'M00001'
ORDER BY stat_month DESC;
```

## Metric definitions

- `refund_rate` = successful refunded order count / successful transaction count
- `chargeback_rate` = chargeback order count / successful transaction count
- `fraud_rate` = fraud order count / successful transaction count

Rates are calculated from original transaction cohorts (`txn_time` date), so platform and merchant rates remain consistent.

## Amount realism model

The seed generator applies merchant-level profiles and mixed perturbation for amounts:

- Merchant profile controls volume and risk weight differences
- Transaction amounts use varied micro-noise and monthly constrained reconciliation
- Refund/chargeback/fraud amounts are generated independently (not cloned from one fixed ticket)
- Monthly platform totals remain aligned with Excel targets after reconciliation
- Per merchant, transaction amounts are integer values in `[29, 200]`
- Per merchant, each month uses 10-15 distinct transaction amount levels
- Refund/chargeback/fraud streams avoid 3 consecutive identical amounts per merchant

## Distribution check SQL

Use these checks after seed generation:

```sql
-- 1) Platform month totals must match target months (2025-12 to 2026-05)
SELECT DATE_FORMAT(stat_month, '%Y%m') AS ym,
       tx_success_amount, refund_amount, chargeback_amount, fraud_amount
FROM demo_payments.vw_platform_monthly_metrics
WHERE DATE_FORMAT(stat_month, '%Y%m') BETWEEN '202512' AND '202605'
ORDER BY ym;
```

```sql
-- 2) Amount diversity by merchant/month
SELECT merchant_id,
       DATE_FORMAT(txn_time, '%Y-%m') AS ym,
       COUNT(DISTINCT amount) AS unique_amounts,
       MIN(amount) AS min_amt,
       MAX(amount) AS max_amt
FROM demo_payments.transactions
GROUP BY merchant_id, DATE_FORMAT(txn_time, '%Y-%m')
ORDER BY merchant_id, ym;
```

```sql
-- 3) P50 / P90 / P99 check for long-tail shape
WITH ranked AS (
  SELECT merchant_id,
         DATE_FORMAT(txn_time, '%Y-%m') AS ym,
         amount,
         CUME_DIST() OVER (
           PARTITION BY merchant_id, DATE_FORMAT(txn_time, '%Y-%m')
           ORDER BY amount
         ) AS cd
  FROM demo_payments.transactions
)
SELECT merchant_id, ym,
       MIN(CASE WHEN cd >= 0.50 THEN amount END) AS p50,
       MIN(CASE WHEN cd >= 0.90 THEN amount END) AS p90,
       MIN(CASE WHEN cd >= 0.99 THEN amount END) AS p99
FROM ranked
GROUP BY merchant_id, ym
ORDER BY merchant_id, ym;
```

```sql
-- 4) No 3 consecutive equal amounts for refund/chargeback/fraud per merchant-month
WITH rf AS (
  SELECT t.merchant_id AS mid,
         DATE_FORMAT(r.refund_time, '%Y-%m') AS ym,
         r.refund_amount AS amt,
         LAG(r.refund_amount, 1) OVER (
           PARTITION BY t.merchant_id, DATE_FORMAT(r.refund_time, '%Y-%m')
           ORDER BY r.refund_time
         ) AS l1,
         LAG(r.refund_amount, 2) OVER (
           PARTITION BY t.merchant_id, DATE_FORMAT(r.refund_time, '%Y-%m')
           ORDER BY r.refund_time
         ) AS l2
  FROM demo_payments.refunds r
  JOIN demo_payments.transactions t ON t.order_id = r.original_order_id
),
cb AS (
  SELECT c.merchant_id AS mid,
         DATE_FORMAT(c.chargeback_time, '%Y-%m') AS ym,
         c.chargeback_amount AS amt,
         LAG(c.chargeback_amount, 1) OVER (
           PARTITION BY c.merchant_id, DATE_FORMAT(c.chargeback_time, '%Y-%m')
           ORDER BY c.chargeback_time
         ) AS l1,
         LAG(c.chargeback_amount, 2) OVER (
           PARTITION BY c.merchant_id, DATE_FORMAT(c.chargeback_time, '%Y-%m')
           ORDER BY c.chargeback_time
         ) AS l2
  FROM demo_payments.chargebacks c
),
fd AS (
  SELECT f.merchant_id AS mid,
         DATE_FORMAT(f.fraud_time, '%Y-%m') AS ym,
         f.amount AS amt,
         LAG(f.amount, 1) OVER (
           PARTITION BY f.merchant_id, DATE_FORMAT(f.fraud_time, '%Y-%m')
           ORDER BY f.fraud_time
         ) AS l1,
         LAG(f.amount, 2) OVER (
           PARTITION BY f.merchant_id, DATE_FORMAT(f.fraud_time, '%Y-%m')
           ORDER BY f.fraud_time
         ) AS l2
  FROM demo_payments.fraud_events f
)
SELECT 'refund' AS type, SUM(CASE WHEN amt = l1 AND amt = l2 THEN 1 ELSE 0 END) AS triple_same FROM rf
UNION ALL
SELECT 'chargeback', SUM(CASE WHEN amt = l1 AND amt = l2 THEN 1 ELSE 0 END) FROM cb
UNION ALL
SELECT 'fraud', SUM(CASE WHEN amt = l1 AND amt = l2 THEN 1 ELSE 0 END) FROM fd;
```

## 6) Run UI with real MySQL data (no Node/Python required)

Start local API + static UI server:

```powershell
powershell -ExecutionPolicy Bypass -File .\server\serve.ps1
```

Open browser:

- `http://localhost:8790`（登录页）
- `http://localhost:8790/dashboard`（看板页，需先登录）

Demo login account:

- Username: `admin`
- Password: `PayDemo@2026`

Optional custom DB connection:

```powershell
powershell -ExecutionPolicy Bypass -File .\server\serve.ps1 `
  -MySqlHost 127.0.0.1 `
  -MySqlPort 3306 `
  -MySqlUser root `
  -MySqlPassword Rm200509 `
  -Database demo_payments
```
