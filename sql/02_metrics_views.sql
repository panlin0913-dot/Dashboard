USE demo_payments;

DROP VIEW IF EXISTS vw_platform_daily_metrics;
CREATE VIEW vw_platform_daily_metrics AS
WITH tx AS (
  SELECT
    DATE(txn_time) AS stat_date,
    COUNT(*) AS tx_total_count,
    SUM(CASE WHEN payment_status = 'SUCCESS' THEN 1 ELSE 0 END) AS tx_success_count,
    SUM(CASE WHEN payment_status = 'SUCCESS' THEN amount ELSE 0 END) AS tx_success_amount
  FROM transactions
  GROUP BY DATE(txn_time)
),
rf AS (
  SELECT
    DATE(t.txn_time) AS stat_date,
    COUNT(DISTINCT r.original_order_id) AS refund_count,
    SUM(r.refund_amount) AS refund_amount
  FROM refunds r
  JOIN transactions t ON t.order_id = r.original_order_id
  WHERE r.refund_status = 'SUCCESS'
    AND t.payment_status = 'SUCCESS'
  GROUP BY DATE(t.txn_time)
),
cb AS (
  SELECT
    DATE(t.txn_time) AS stat_date,
    COUNT(DISTINCT c.original_order_id) AS chargeback_count,
    SUM(c.chargeback_amount) AS chargeback_amount
  FROM chargebacks c
  JOIN transactions t ON t.order_id = c.original_order_id
  WHERE t.payment_status = 'SUCCESS'
  GROUP BY DATE(t.txn_time)
),
fd AS (
  SELECT
    DATE(t.txn_time) AS stat_date,
    COUNT(DISTINCT f.original_order_id) AS fraud_count,
    SUM(f.amount) AS fraud_amount
  FROM fraud_events f
  JOIN transactions t ON t.order_id = f.original_order_id
  WHERE t.payment_status = 'SUCCESS'
  GROUP BY DATE(t.txn_time)
)
SELECT
  tx.stat_date,
  tx.tx_total_count,
  tx.tx_success_count,
  tx.tx_success_amount,
  COALESCE(rf.refund_count, 0) AS refund_count,
  COALESCE(rf.refund_amount, 0) AS refund_amount,
  COALESCE(cb.chargeback_count, 0) AS chargeback_count,
  COALESCE(cb.chargeback_amount, 0) AS chargeback_amount,
  COALESCE(fd.fraud_count, 0) AS fraud_count,
  COALESCE(fd.fraud_amount, 0) AS fraud_amount,
  ROUND(COALESCE(rf.refund_count, 0) / NULLIF(tx.tx_success_count, 0), 6) AS refund_rate,
  ROUND(COALESCE(cb.chargeback_count, 0) / NULLIF(tx.tx_success_count, 0), 6) AS chargeback_rate,
  ROUND(COALESCE(fd.fraud_count, 0) / NULLIF(tx.tx_success_count, 0), 6) AS fraud_rate
FROM tx
LEFT JOIN rf ON rf.stat_date = tx.stat_date
LEFT JOIN cb ON cb.stat_date = tx.stat_date
LEFT JOIN fd ON fd.stat_date = tx.stat_date;

DROP VIEW IF EXISTS vw_platform_monthly_metrics;
CREATE VIEW vw_platform_monthly_metrics AS
SELECT
  DATE_FORMAT(stat_date, '%Y-%m-01') AS stat_month,
  SUM(tx_total_count) AS tx_total_count,
  SUM(tx_success_count) AS tx_success_count,
  SUM(tx_success_amount) AS tx_success_amount,
  SUM(refund_count) AS refund_count,
  SUM(refund_amount) AS refund_amount,
  SUM(chargeback_count) AS chargeback_count,
  SUM(chargeback_amount) AS chargeback_amount,
  SUM(fraud_count) AS fraud_count,
  SUM(fraud_amount) AS fraud_amount,
  ROUND(SUM(refund_count) / NULLIF(SUM(tx_success_count), 0), 6) AS refund_rate,
  ROUND(SUM(chargeback_count) / NULLIF(SUM(tx_success_count), 0), 6) AS chargeback_rate,
  ROUND(SUM(fraud_count) / NULLIF(SUM(tx_success_count), 0), 6) AS fraud_rate
FROM vw_platform_daily_metrics
GROUP BY DATE_FORMAT(stat_date, '%Y-%m-01');

DROP VIEW IF EXISTS vw_merchant_daily_metrics;
CREATE VIEW vw_merchant_daily_metrics AS
WITH tx AS (
  SELECT
    merchant_id,
    DATE(txn_time) AS stat_date,
    COUNT(*) AS tx_total_count,
    SUM(CASE WHEN payment_status = 'SUCCESS' THEN 1 ELSE 0 END) AS tx_success_count,
    SUM(CASE WHEN payment_status = 'SUCCESS' THEN amount ELSE 0 END) AS tx_success_amount
  FROM transactions
  GROUP BY merchant_id, DATE(txn_time)
),
rf AS (
  SELECT
    t.merchant_id,
    DATE(t.txn_time) AS stat_date,
    COUNT(DISTINCT r.original_order_id) AS refund_count,
    SUM(r.refund_amount) AS refund_amount
  FROM refunds r
  JOIN transactions t ON t.order_id = r.original_order_id
  WHERE r.refund_status = 'SUCCESS'
    AND t.payment_status = 'SUCCESS'
  GROUP BY t.merchant_id, DATE(t.txn_time)
),
cb AS (
  SELECT
    t.merchant_id,
    DATE(t.txn_time) AS stat_date,
    COUNT(DISTINCT c.original_order_id) AS chargeback_count,
    SUM(c.chargeback_amount) AS chargeback_amount
  FROM chargebacks c
  JOIN transactions t ON t.order_id = c.original_order_id
  WHERE t.payment_status = 'SUCCESS'
  GROUP BY t.merchant_id, DATE(t.txn_time)
),
fd AS (
  SELECT
    t.merchant_id,
    DATE(t.txn_time) AS stat_date,
    COUNT(DISTINCT f.original_order_id) AS fraud_count,
    SUM(f.amount) AS fraud_amount
  FROM fraud_events f
  JOIN transactions t ON t.order_id = f.original_order_id
  WHERE t.payment_status = 'SUCCESS'
  GROUP BY t.merchant_id, DATE(t.txn_time)
)
SELECT
  tx.merchant_id,
  tx.stat_date,
  tx.tx_total_count,
  tx.tx_success_count,
  tx.tx_success_amount,
  COALESCE(rf.refund_count, 0) AS refund_count,
  COALESCE(rf.refund_amount, 0) AS refund_amount,
  COALESCE(cb.chargeback_count, 0) AS chargeback_count,
  COALESCE(cb.chargeback_amount, 0) AS chargeback_amount,
  COALESCE(fd.fraud_count, 0) AS fraud_count,
  COALESCE(fd.fraud_amount, 0) AS fraud_amount,
  ROUND(COALESCE(rf.refund_count, 0) / NULLIF(tx.tx_success_count, 0), 6) AS refund_rate,
  ROUND(COALESCE(cb.chargeback_count, 0) / NULLIF(tx.tx_success_count, 0), 6) AS chargeback_rate,
  ROUND(COALESCE(fd.fraud_count, 0) / NULLIF(tx.tx_success_count, 0), 6) AS fraud_rate
FROM tx
LEFT JOIN rf ON rf.merchant_id = tx.merchant_id AND rf.stat_date = tx.stat_date
LEFT JOIN cb ON cb.merchant_id = tx.merchant_id AND cb.stat_date = tx.stat_date
LEFT JOIN fd ON fd.merchant_id = tx.merchant_id AND fd.stat_date = tx.stat_date;

DROP VIEW IF EXISTS vw_merchant_monthly_metrics;
CREATE VIEW vw_merchant_monthly_metrics AS
SELECT
  merchant_id,
  DATE_FORMAT(stat_date, '%Y-%m-01') AS stat_month,
  SUM(tx_total_count) AS tx_total_count,
  SUM(tx_success_count) AS tx_success_count,
  SUM(tx_success_amount) AS tx_success_amount,
  SUM(refund_count) AS refund_count,
  SUM(refund_amount) AS refund_amount,
  SUM(chargeback_count) AS chargeback_count,
  SUM(chargeback_amount) AS chargeback_amount,
  SUM(fraud_count) AS fraud_count,
  SUM(fraud_amount) AS fraud_amount,
  ROUND(SUM(refund_count) / NULLIF(SUM(tx_success_count), 0), 6) AS refund_rate,
  ROUND(SUM(chargeback_count) / NULLIF(SUM(tx_success_count), 0), 6) AS chargeback_rate,
  ROUND(SUM(fraud_count) / NULLIF(SUM(tx_success_count), 0), 6) AS fraud_rate
FROM vw_merchant_daily_metrics
GROUP BY merchant_id, DATE_FORMAT(stat_date, '%Y-%m-01');
