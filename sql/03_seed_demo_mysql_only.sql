USE demo_payments;

DROP PROCEDURE IF EXISTS sp_generate_demo_data;

DELIMITER $$
CREATE PROCEDURE sp_generate_demo_data(
  IN p_start_month CHAR(6),
  IN p_end_month CHAR(6)
)
BEGIN
  DECLARE v_ym CHAR(6);
  DECLARE v_done INT DEFAULT 0;
  DECLARE v_tx_count INT;
  DECLARE v_refund_count INT;
  DECLARE v_chargeback_count INT;
  DECLARE v_fraud_count INT;

  DECLARE v_tx_amount DECIMAL(20,6);
  DECLARE v_refund_amount DECIMAL(20,6);
  DECLARE v_chargeback_amount DECIMAL(20,6);
  DECLARE v_fraud_amount DECIMAL(20,6);

  DECLARE v_month_start DATE;
  DECLARE v_days_in_month INT;

  DECLARE v_tx_total_cents BIGINT;
  DECLARE v_refund_total_cents BIGINT;
  DECLARE v_chargeback_total_cents BIGINT;
  DECLARE v_fraud_total_cents BIGINT;

  DECLARE v_tx_base_cents BIGINT;
  DECLARE v_refund_base_cents BIGINT;
  DECLARE v_chargeback_base_cents BIGINT;
  DECLARE v_fraud_base_cents BIGINT;

  DECLARE v_tx_remainder BIGINT;
  DECLARE v_refund_remainder BIGINT;
  DECLARE v_chargeback_remainder BIGINT;
  DECLARE v_fraud_remainder BIGINT;

  DECLARE v_sum_tx_count BIGINT;
  DECLARE v_sum_refund_count BIGINT;
  DECLARE v_sum_chargeback_count BIGINT;
  DECLARE v_sum_fraud_count BIGINT;

  DECLARE v_sum_tx_cents BIGINT;
  DECLARE v_sum_refund_cents BIGINT;
  DECLARE v_sum_chargeback_cents BIGINT;
  DECLARE v_sum_fraud_cents BIGINT;

  DECLARE v_sum_volume_weight DECIMAL(20,6);
  DECLARE v_sum_refund_weight DECIMAL(20,6);
  DECLARE v_sum_chargeback_weight DECIMAL(20,6);
  DECLARE v_sum_fraud_weight DECIMAL(20,6);

  DECLARE cur_targets CURSOR FOR
    SELECT ym, tx_count, refund_count, chargeback_count, fraud_count, tx_amount, refund_amount, chargeback_amount, fraud_amount
    FROM tmp_month_targets
    WHERE ym BETWEEN p_start_month AND p_end_month
    ORDER BY ym;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

  SET FOREIGN_KEY_CHECKS = 0;
  TRUNCATE TABLE fraud_events;
  TRUNCATE TABLE chargebacks;
  TRUNCATE TABLE refunds;
  TRUNCATE TABLE transactions;
  TRUNCATE TABLE merchants;
  SET FOREIGN_KEY_CHECKS = 1;

  INSERT INTO merchants (merchant_id, merchant_name, mcc, created_at) VALUES
    ('M00001', 'Victoria Harbour Dining Group Limited', '5816', NOW()),
    ('M00002', 'Kowloon Lantern Hospitality Limited', '5817', NOW()),
    ('M00003', 'Pearl East Lifestyle Trading HK Limited', '5399', NOW()),
    ('M00004', 'Central Bay Bistro Holdings Limited', '5816', NOW()),
    ('M00005', 'Harbour Crown Dining Concepts Limited', '5817', NOW()),
    ('M00006', 'Golden Bauhinia Retail Network Limited', '5399', NOW()),
    ('M00007', 'Causeway Prime Food Services Limited', '5816', NOW()),
    ('M00008', 'Tsim Sha Tsui Culinary Group Limited', '5817', NOW()),
    ('M00009', 'Prosper Link Merchants Hong Kong Limited', '5399', NOW()),
    ('M00010', 'Island Coast Dining Collection Limited', '5816', NOW()),
    ('M00011', 'New Territories Flavour House Limited', '5817', NOW()),
    ('M00012', 'Harbour City Lifestyle Brands Limited', '5399', NOW()),
    ('M00013', 'Pacific Rim Dining HK Limited', '5816', NOW()),
    ('M00014', 'Jade Bridge Restaurant Partners Limited', '5817', NOW()),
    ('M00015', 'Star Ferry Retail Alliance Limited', '5399', NOW()),
    ('M00016', 'Blue Peak Dining Group Hong Kong Limited', '5816', NOW()),
    ('M00017', 'Metro Gourmet Operations Limited', '5817', NOW()),
    ('M00018', 'Fortune Gate General Merchandise Limited', '5399', NOW()),
    ('M00019', 'Amber Harbour Dining Company Limited', '5816', NOW()),
    ('M00020', 'Orient Plaza Kitchen Management Limited', '5817', NOW()),
    ('M00021', 'Skyline Supply Chain HK Limited', '5399', NOW()),
    ('M00022', 'Sea View Dining Ventures Limited', '5816', NOW()),
    ('M00023', 'Lotus Court Food and Beverage Limited', '5817', NOW()),
    ('M00024', 'Regent Street Retail Hub HK Limited', '5399', NOW()),
    ('M00025', 'Harbourfront Dining Syndicate Limited', '5816', NOW()),
    ('M00026', 'Dragon Gate Bistro Group Limited', '5817', NOW()),
    ('M00027', 'Bright Union Lifestyle Commerce Limited', '5399', NOW()),
    ('M00028', 'Peninsula Dining Services Limited', '5816', NOW()),
    ('M00029', 'South Bay Culinary Company Limited', '5817', NOW()),
    ('M00030', 'Ever Prosper Merchants HK Limited', '5399', NOW());

  DROP TEMPORARY TABLE IF EXISTS tmp_digits;
  DROP TEMPORARY TABLE IF EXISTS tmp_digits0;
  DROP TEMPORARY TABLE IF EXISTS tmp_digits1;
  DROP TEMPORARY TABLE IF EXISTS tmp_digits2;
  DROP TEMPORARY TABLE IF EXISTS tmp_digits3;
  DROP TEMPORARY TABLE IF EXISTS tmp_digits4;
  DROP TEMPORARY TABLE IF EXISTS tmp_digits5;
  DROP TEMPORARY TABLE IF EXISTS tmp_seq;
  DROP TEMPORARY TABLE IF EXISTS tmp_month_targets;
  DROP TEMPORARY TABLE IF EXISTS tmp_profiles;
  DROP TEMPORARY TABLE IF EXISTS tmp_mm;
  DROP TEMPORARY TABLE IF EXISTS tmp_amt_catalog;

  CREATE TEMPORARY TABLE tmp_digits (
    n INT PRIMARY KEY
  );

  INSERT INTO tmp_digits (n) VALUES
    (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);

  CREATE TEMPORARY TABLE tmp_digits0 AS SELECT n FROM tmp_digits;
  CREATE TEMPORARY TABLE tmp_digits1 AS SELECT n FROM tmp_digits;
  CREATE TEMPORARY TABLE tmp_digits2 AS SELECT n FROM tmp_digits;
  CREATE TEMPORARY TABLE tmp_digits3 AS SELECT n FROM tmp_digits;
  CREATE TEMPORARY TABLE tmp_digits4 AS SELECT n FROM tmp_digits;
  CREATE TEMPORARY TABLE tmp_digits5 AS SELECT n FROM tmp_digits;

  CREATE TEMPORARY TABLE tmp_seq (
    n INT PRIMARY KEY
  );

  INSERT INTO tmp_seq (n)
  SELECT
    d0.n + d1.n * 10 + d2.n * 100 + d3.n * 1000 + d4.n * 10000 + d5.n * 100000
  FROM tmp_digits0 d0
  CROSS JOIN tmp_digits1 d1
  CROSS JOIN tmp_digits2 d2
  CROSS JOIN tmp_digits3 d3
  CROSS JOIN tmp_digits4 d4
  CROSS JOIN tmp_digits5 d5;

  CREATE TEMPORARY TABLE tmp_month_targets (
    ym CHAR(6) PRIMARY KEY,
    tx_amount DECIMAL(20,6) NOT NULL,
    refund_amount DECIMAL(20,6) NOT NULL,
    chargeback_amount DECIMAL(20,6) NOT NULL,
    fraud_amount DECIMAL(20,6) NOT NULL,
    tx_count INT NOT NULL,
    refund_count INT NOT NULL,
    chargeback_count INT NOT NULL,
    fraud_count INT NOT NULL
  );

  INSERT INTO tmp_month_targets (
    ym, tx_amount, refund_amount, chargeback_amount, fraud_amount, tx_count, refund_count, chargeback_count, fraud_count
  ) VALUES
    ('202512', 14076090.601247, 776424.804070, 116900.835387, 287866.295162, 216344, 12291, 1808, 5255),
    ('202601', 12255326.302251, 653968.384438,  93960.899835, 278495.570822, 169996,  9493, 1332, 3983),
    ('202602', 10918704.780154, 559718.132141,  74507.862786, 209307.694816, 112860,  6045,  773, 2115),
    ('202603', 10063123.556978, 471838.526947,  70450.245076, 202876.120126, 121484,  6385,  734, 2691),
    ('202604', 10038654.951138, 460688.018948,  68793.822364, 192877.584066, 128779,  6413,  942, 2596),
    ('202605',  9956104.818805, 476031.227483,  66389.982348, 187315.590197, 101467,  5682,  900, 2020);

  CREATE TEMPORARY TABLE tmp_profiles (
    merchant_id VARCHAR(32) PRIMARY KEY,
    volume_weight DECIMAL(12,6) NOT NULL,
    refund_weight DECIMAL(12,6) NOT NULL,
    chargeback_weight DECIMAL(12,6) NOT NULL,
    fraud_weight DECIMAL(12,6) NOT NULL
  );

  INSERT INTO tmp_profiles (merchant_id, volume_weight, refund_weight, chargeback_weight, fraud_weight) VALUES
    -- Top-quality merchants: larger volume, very low risk
    ('M00001', 1.80, 0.35, 0.32, 0.30),
    ('M00002', 1.72, 0.38, 0.35, 0.34),
    ('M00003', 1.64, 0.40, 0.38, 0.36),
    ('M00004', 1.58, 0.45, 0.42, 0.40),
    ('M00005', 1.52, 0.48, 0.45, 0.43),
    ('M00006', 1.46, 0.52, 0.48, 0.46),
    ('M00007', 1.40, 0.56, 0.52, 0.50),
    ('M00008', 1.34, 0.60, 0.56, 0.55),
    ('M00009', 1.28, 0.64, 0.60, 0.58),
    ('M00010', 1.22, 0.68, 0.64, 0.62),
    -- Mid-tier merchants
    ('M00011', 1.10, 0.90, 0.88, 0.86),
    ('M00012', 1.08, 0.94, 0.92, 0.90),
    ('M00013', 1.06, 0.98, 0.96, 0.94),
    ('M00014', 1.04, 1.02, 1.00, 0.98),
    ('M00015', 1.02, 1.06, 1.04, 1.02),
    ('M00016', 1.00, 1.10, 1.08, 1.06),
    ('M00017', 0.98, 1.14, 1.12, 1.10),
    ('M00018', 0.96, 1.18, 1.16, 1.14),
    ('M00019', 0.94, 1.22, 1.20, 1.18),
    ('M00020', 0.92, 1.26, 1.24, 1.22),
    -- High-risk merchants: lower/mid volume, much higher risk
    ('M00021', 0.90, 1.55, 1.70, 1.85),
    ('M00022', 0.88, 1.65, 1.85, 2.00),
    ('M00023', 0.86, 1.75, 2.00, 2.20),
    ('M00024', 0.84, 1.85, 2.15, 2.35),
    ('M00025', 0.82, 1.95, 2.30, 2.55),
    ('M00026', 0.80, 2.10, 2.50, 2.80),
    ('M00027', 0.78, 2.25, 2.70, 3.05),
    ('M00028', 0.76, 2.40, 2.90, 3.30),
    ('M00029', 0.74, 2.55, 3.10, 3.55),
    ('M00030', 0.72, 2.70, 3.30, 3.80);

  SELECT
    SUM(volume_weight),
    SUM(refund_weight),
    SUM(chargeback_weight),
    SUM(fraud_weight)
  INTO
    v_sum_volume_weight,
    v_sum_refund_weight,
    v_sum_chargeback_weight,
    v_sum_fraud_weight
  FROM tmp_profiles;

  OPEN cur_targets;
  read_loop: LOOP
    FETCH cur_targets INTO
      v_ym, v_tx_count, v_refund_count, v_chargeback_count, v_fraud_count,
      v_tx_amount, v_refund_amount, v_chargeback_amount, v_fraud_amount;
    IF v_done = 1 THEN
      LEAVE read_loop;
    END IF;

    SET v_month_start = STR_TO_DATE(CONCAT(v_ym, '01'), '%Y%m%d');
    SET v_days_in_month = DAY(LAST_DAY(v_month_start));

    SET v_tx_total_cents = ROUND(v_tx_amount * 100, 0);
    SET v_refund_total_cents = ROUND(v_refund_amount * 100, 0);
    SET v_chargeback_total_cents = ROUND(v_chargeback_amount * 100, 0);
    SET v_fraud_total_cents = ROUND(v_fraud_amount * 100, 0);

    SET v_tx_base_cents = FLOOR(v_tx_total_cents / v_tx_count);
    SET v_refund_base_cents = FLOOR(v_refund_total_cents / GREATEST(v_refund_count, 1));
    SET v_chargeback_base_cents = FLOOR(v_chargeback_total_cents / GREATEST(v_chargeback_count, 1));
    SET v_fraud_base_cents = FLOOR(v_fraud_total_cents / GREATEST(v_fraud_count, 1));

    DROP TEMPORARY TABLE IF EXISTS tmp_mm;
    CREATE TEMPORARY TABLE tmp_mm (
      merchant_id VARCHAR(32) PRIMARY KEY,
      mcc VARCHAR(4) NOT NULL,
      volume_weight DECIMAL(12,6) NOT NULL,
      refund_weight DECIMAL(12,6) NOT NULL,
      chargeback_weight DECIMAL(12,6) NOT NULL,
      fraud_weight DECIMAL(12,6) NOT NULL,
      tx_count INT NOT NULL DEFAULT 0,
      refund_count INT NOT NULL DEFAULT 0,
      chargeback_count INT NOT NULL DEFAULT 0,
      fraud_count INT NOT NULL DEFAULT 0,
      tx_cents BIGINT NOT NULL DEFAULT 0,
      refund_cents BIGINT NOT NULL DEFAULT 0,
      chargeback_cents BIGINT NOT NULL DEFAULT 0,
      fraud_cents BIGINT NOT NULL DEFAULT 0,
      tx_base BIGINT NOT NULL DEFAULT 0,
      tx_rem BIGINT NOT NULL DEFAULT 0,
      refund_base BIGINT NOT NULL DEFAULT 0,
      refund_rem BIGINT NOT NULL DEFAULT 0,
      chargeback_base BIGINT NOT NULL DEFAULT 0,
      chargeback_rem BIGINT NOT NULL DEFAULT 0,
      fraud_base BIGINT NOT NULL DEFAULT 0,
      fraud_rem BIGINT NOT NULL DEFAULT 0,
      cat_size INT NOT NULL DEFAULT 10,
      cat_step INT NOT NULL DEFAULT 3
    );

    INSERT INTO tmp_mm (
      merchant_id, mcc, volume_weight, refund_weight, chargeback_weight, fraud_weight,
      tx_count, refund_count, chargeback_count, fraud_count,
      tx_cents, refund_cents, chargeback_cents, fraud_cents
    )
    SELECT
      p.merchant_id,
      m.mcc,
      p.volume_weight,
      p.refund_weight,
      p.chargeback_weight,
      p.fraud_weight,
      FLOOR(v_tx_count * p.volume_weight / v_sum_volume_weight),
      FLOOR(v_refund_count * p.refund_weight / v_sum_refund_weight),
      FLOOR(v_chargeback_count * p.chargeback_weight / v_sum_chargeback_weight),
      FLOOR(v_fraud_count * p.fraud_weight / v_sum_fraud_weight),
      FLOOR(v_tx_total_cents * p.volume_weight / v_sum_volume_weight),
      FLOOR(v_refund_total_cents * p.refund_weight / v_sum_refund_weight),
      FLOOR(v_chargeback_total_cents * p.chargeback_weight / v_sum_chargeback_weight),
      FLOOR(v_fraud_total_cents * p.fraud_weight / v_sum_fraud_weight)
    FROM tmp_profiles p
    JOIN merchants m ON m.merchant_id = p.merchant_id;

    SELECT
      SUM(tx_count),
      SUM(refund_count),
      SUM(chargeback_count),
      SUM(fraud_count),
      SUM(tx_cents),
      SUM(refund_cents),
      SUM(chargeback_cents),
      SUM(fraud_cents)
    INTO
      v_sum_tx_count, v_sum_refund_count, v_sum_chargeback_count, v_sum_fraud_count,
      v_sum_tx_cents, v_sum_refund_cents, v_sum_chargeback_cents, v_sum_fraud_cents
    FROM tmp_mm;

    SET v_tx_remainder = v_tx_count - v_sum_tx_count;
    SET v_refund_remainder = v_refund_count - v_sum_refund_count;
    SET v_chargeback_remainder = v_chargeback_count - v_sum_chargeback_count;
    SET v_fraud_remainder = v_fraud_count - v_sum_fraud_count;

    IF v_tx_remainder > 0 THEN
      UPDATE tmp_mm
      SET tx_count = tx_count + 1
      ORDER BY volume_weight DESC, merchant_id
      LIMIT v_tx_remainder;
    END IF;
    IF v_refund_remainder > 0 THEN
      UPDATE tmp_mm
      SET refund_count = refund_count + 1
      ORDER BY refund_weight DESC, merchant_id
      LIMIT v_refund_remainder;
    END IF;
    IF v_chargeback_remainder > 0 THEN
      UPDATE tmp_mm
      SET chargeback_count = chargeback_count + 1
      ORDER BY chargeback_weight DESC, merchant_id
      LIMIT v_chargeback_remainder;
    END IF;
    IF v_fraud_remainder > 0 THEN
      UPDATE tmp_mm
      SET fraud_count = fraud_count + 1
      ORDER BY fraud_weight DESC, merchant_id
      LIMIT v_fraud_remainder;
    END IF;

    SET v_tx_remainder = v_tx_total_cents - v_sum_tx_cents;
    SET v_refund_remainder = v_refund_total_cents - v_sum_refund_cents;
    SET v_chargeback_remainder = v_chargeback_total_cents - v_sum_chargeback_cents;
    SET v_fraud_remainder = v_fraud_total_cents - v_sum_fraud_cents;

    IF v_tx_remainder > 0 THEN
      UPDATE tmp_mm
      SET tx_cents = tx_cents + 1
      ORDER BY volume_weight DESC, merchant_id
      LIMIT v_tx_remainder;
    END IF;
    IF v_refund_remainder > 0 THEN
      UPDATE tmp_mm
      SET refund_cents = refund_cents + 1
      ORDER BY refund_weight DESC, merchant_id
      LIMIT v_refund_remainder;
    END IF;
    IF v_chargeback_remainder > 0 THEN
      UPDATE tmp_mm
      SET chargeback_cents = chargeback_cents + 1
      ORDER BY chargeback_weight DESC, merchant_id
      LIMIT v_chargeback_remainder;
    END IF;
    IF v_fraud_remainder > 0 THEN
      UPDATE tmp_mm
      SET fraud_cents = fraud_cents + 1
      ORDER BY fraud_weight DESC, merchant_id
      LIMIT v_fraud_remainder;
    END IF;

    UPDATE tmp_mm
    SET
      tx_base = FLOOR(tx_cents / tx_count),
      tx_rem = tx_cents - FLOOR(tx_cents / tx_count) * tx_count,
      refund_base = CASE WHEN refund_count > 0 THEN FLOOR(refund_cents / refund_count) ELSE 0 END,
      refund_rem = CASE WHEN refund_count > 0 THEN refund_cents - FLOOR(refund_cents / refund_count) * refund_count ELSE 0 END,
      chargeback_base = CASE WHEN chargeback_count > 0 THEN FLOOR(chargeback_cents / chargeback_count) ELSE 0 END,
      chargeback_rem = CASE WHEN chargeback_count > 0 THEN chargeback_cents - FLOOR(chargeback_cents / chargeback_count) * chargeback_count ELSE 0 END,
      fraud_base = CASE WHEN fraud_count > 0 THEN FLOOR(fraud_cents / fraud_count) ELSE 0 END,
      fraud_rem = CASE WHEN fraud_count > 0 THEN fraud_cents - FLOOR(fraud_cents / fraud_count) * fraud_count ELSE 0 END,
      cat_size = 10 + MOD(CAST(SUBSTRING(merchant_id, 2) AS UNSIGNED), 6),
      cat_step = 3 + MOD(CAST(SUBSTRING(merchant_id, 2) AS UNSIGNED), 5);

    DROP TEMPORARY TABLE IF EXISTS tmp_amt_catalog;
    CREATE TEMPORARY TABLE tmp_amt_catalog (
      merchant_id VARCHAR(32) NOT NULL,
      seq_idx INT NOT NULL,
      amt INT NOT NULL,
      PRIMARY KEY (merchant_id, seq_idx)
    );

    INSERT INTO tmp_amt_catalog (merchant_id, seq_idx, amt)
    SELECT
      mm.merchant_id,
      (s.n + 1) AS seq_idx,
      (
        GREATEST(
          29,
          LEAST(
            200 - (mm.cat_size - 1) * mm.cat_step,
            ROUND(mm.tx_cents / GREATEST(mm.tx_count, 1) / 100) - FLOOR(((mm.cat_size - 1) * mm.cat_step) / 2)
          )
        ) + s.n * mm.cat_step
      ) AS amt
    FROM tmp_mm mm
    JOIN tmp_seq s ON s.n < mm.cat_size;

    DROP TEMPORARY TABLE IF EXISTS tmp_tx_raw;
    DROP TEMPORARY TABLE IF EXISTS tmp_tx_agg;

    CREATE TEMPORARY TABLE tmp_tx_raw AS
    SELECT
      mm.merchant_id,
      mm.mcc,
      mm.tx_cents,
      (s.n + 1) AS seq_no,
      ac.amt AS raw_amt
    FROM tmp_mm mm
    JOIN tmp_seq s ON s.n < mm.tx_count
    JOIN tmp_amt_catalog ac
      ON ac.merchant_id = mm.merchant_id
      AND ac.seq_idx = MOD(s.n, mm.cat_size) + 1;

    CREATE TEMPORARY TABLE tmp_tx_agg AS
    SELECT
      merchant_id,
      COUNT(*) AS cnt_rows,
      ROUND(MAX(tx_cents) / 100, 0) AS target_units,
      SUM(raw_amt) AS sum_raw_units,
      (ROUND(MAX(tx_cents) / 100, 0) - SUM(raw_amt)) AS delta_units,
      CASE
        WHEN (ROUND(MAX(tx_cents) / 100, 0) - SUM(raw_amt)) >= 0 THEN FLOOR((ROUND(MAX(tx_cents) / 100, 0) - SUM(raw_amt)) / COUNT(*))
        ELSE -FLOOR(ABS(ROUND(MAX(tx_cents) / 100, 0) - SUM(raw_amt)) / COUNT(*))
      END AS adj_base,
      ABS(ROUND(MAX(tx_cents) / 100, 0) - SUM(raw_amt)) - (
        ABS(
          CASE
            WHEN (ROUND(MAX(tx_cents) / 100, 0) - SUM(raw_amt)) >= 0 THEN FLOOR((ROUND(MAX(tx_cents) / 100, 0) - SUM(raw_amt)) / COUNT(*))
            ELSE -FLOOR(ABS(ROUND(MAX(tx_cents) / 100, 0) - SUM(raw_amt)) / COUNT(*))
          END
        ) * COUNT(*)
      ) AS adj_rem,
      CASE WHEN (ROUND(MAX(tx_cents) / 100, 0) - SUM(raw_amt)) >= 0 THEN 1 ELSE -1 END AS adj_sign
    FROM tmp_tx_raw
    GROUP BY merchant_id;

    INSERT INTO transactions (
      merchant_id, order_id, currency, amount, mcc, payment_status, txn_time
    )
    SELECT
      r.merchant_id,
      CONCAT('ORD', v_ym, SUBSTRING(r.merchant_id, 2), LPAD(r.seq_no, 8, '0')) AS order_id,
      'USD' AS currency,
      r.raw_amt AS amount,
      r.mcc AS mcc,
      'SUCCESS' AS payment_status,
      DATE_ADD(
        v_month_start,
        INTERVAL (
          MOD(r.seq_no, v_days_in_month) * 86400 +
          MOD((r.seq_no + CAST(SUBSTRING(r.merchant_id, 2) AS UNSIGNED)) * 37, 86400)
        ) SECOND
      ) AS txn_time
    FROM tmp_tx_raw r
    JOIN tmp_tx_agg a ON a.merchant_id = r.merchant_id
    ORDER BY r.merchant_id, r.seq_no;

    DROP TEMPORARY TABLE IF EXISTS tmp_refund_raw;
    DROP TEMPORARY TABLE IF EXISTS tmp_refund_agg;

    CREATE TEMPORARY TABLE tmp_refund_raw AS
    SELECT
      mm.merchant_id,
      mm.refund_cents,
      (s.n + 1) AS seq_no,
      ac.amt AS raw_amt
    FROM tmp_mm mm
    JOIN tmp_seq s ON s.n < mm.refund_count
    JOIN tmp_amt_catalog ac
      ON ac.merchant_id = mm.merchant_id
      AND ac.seq_idx = MOD((s.n * 3 + 1), mm.cat_size) + 1;

    CREATE TEMPORARY TABLE tmp_refund_agg AS
    SELECT
      merchant_id,
      COUNT(*) AS cnt_rows,
      ROUND(MAX(refund_cents) / 100, 0) AS target_units,
      SUM(raw_amt) AS sum_raw_units,
      (ROUND(MAX(refund_cents) / 100, 0) - SUM(raw_amt)) AS delta_units,
      CASE
        WHEN (ROUND(MAX(refund_cents) / 100, 0) - SUM(raw_amt)) >= 0 THEN FLOOR((ROUND(MAX(refund_cents) / 100, 0) - SUM(raw_amt)) / COUNT(*))
        ELSE -FLOOR(ABS(ROUND(MAX(refund_cents) / 100, 0) - SUM(raw_amt)) / COUNT(*))
      END AS adj_base,
      ABS(ROUND(MAX(refund_cents) / 100, 0) - SUM(raw_amt)) - (
        ABS(
          CASE
            WHEN (ROUND(MAX(refund_cents) / 100, 0) - SUM(raw_amt)) >= 0 THEN FLOOR((ROUND(MAX(refund_cents) / 100, 0) - SUM(raw_amt)) / COUNT(*))
            ELSE -FLOOR(ABS(ROUND(MAX(refund_cents) / 100, 0) - SUM(raw_amt)) / COUNT(*))
          END
        ) * COUNT(*)
      ) AS adj_rem,
      CASE WHEN (ROUND(MAX(refund_cents) / 100, 0) - SUM(raw_amt)) >= 0 THEN 1 ELSE -1 END AS adj_sign
    FROM tmp_refund_raw
    GROUP BY merchant_id;

    INSERT INTO refunds (
      original_order_id, refund_currency, refund_amount, refund_status, refund_time
    )
    SELECT
      CONCAT('ORD', v_ym, SUBSTRING(r.merchant_id, 2), LPAD(r.seq_no, 8, '0')) AS original_order_id,
      'USD' AS refund_currency,
      GREATEST(29, LEAST(200, r.raw_amt + a.adj_base + IF(r.seq_no <= a.adj_rem, a.adj_sign, 0))) AS refund_amount,
      'SUCCESS' AS refund_status,
      DATE_ADD(
        v_month_start,
        INTERVAL (r.seq_no + CAST(SUBSTRING(r.merchant_id, 2) AS UNSIGNED) * 3) MINUTE
      ) AS refund_time
    FROM tmp_refund_raw r
    JOIN tmp_refund_agg a ON a.merchant_id = r.merchant_id
    ORDER BY r.merchant_id, r.seq_no;

    DROP TEMPORARY TABLE IF EXISTS tmp_cb_raw;
    DROP TEMPORARY TABLE IF EXISTS tmp_cb_agg;

    CREATE TEMPORARY TABLE tmp_cb_raw AS
    SELECT
      mm.merchant_id,
      mm.mcc,
      mm.tx_count,
      mm.chargeback_cents,
      (s.n + 1) AS seq_no,
      ac.amt AS raw_amt
    FROM tmp_mm mm
    JOIN tmp_seq s ON s.n < mm.chargeback_count
    JOIN tmp_amt_catalog ac
      ON ac.merchant_id = mm.merchant_id
      AND ac.seq_idx = MOD((s.n * 4 + 2), mm.cat_size) + 1;

    CREATE TEMPORARY TABLE tmp_cb_agg AS
    SELECT
      merchant_id,
      COUNT(*) AS cnt_rows,
      ROUND(MAX(chargeback_cents) / 100, 0) AS target_units,
      SUM(raw_amt) AS sum_raw_units,
      (ROUND(MAX(chargeback_cents) / 100, 0) - SUM(raw_amt)) AS delta_units,
      CASE
        WHEN (ROUND(MAX(chargeback_cents) / 100, 0) - SUM(raw_amt)) >= 0 THEN FLOOR((ROUND(MAX(chargeback_cents) / 100, 0) - SUM(raw_amt)) / COUNT(*))
        ELSE -FLOOR(ABS(ROUND(MAX(chargeback_cents) / 100, 0) - SUM(raw_amt)) / COUNT(*))
      END AS adj_base,
      ABS(ROUND(MAX(chargeback_cents) / 100, 0) - SUM(raw_amt)) - (
        ABS(
          CASE
            WHEN (ROUND(MAX(chargeback_cents) / 100, 0) - SUM(raw_amt)) >= 0 THEN FLOOR((ROUND(MAX(chargeback_cents) / 100, 0) - SUM(raw_amt)) / COUNT(*))
            ELSE -FLOOR(ABS(ROUND(MAX(chargeback_cents) / 100, 0) - SUM(raw_amt)) / COUNT(*))
          END
        ) * COUNT(*)
      ) AS adj_rem,
      CASE WHEN (ROUND(MAX(chargeback_cents) / 100, 0) - SUM(raw_amt)) >= 0 THEN 1 ELSE -1 END AS adj_sign
    FROM tmp_cb_raw
    GROUP BY merchant_id;

    INSERT INTO chargebacks (
      original_order_id, merchant_id, mcc, chargeback_currency, chargeback_amount, chargeback_reason, chargeback_time
    )
    SELECT
      CONCAT('ORD', v_ym, SUBSTRING(r.merchant_id, 2), LPAD((r.tx_count - r.seq_no + 1), 8, '0')) AS original_order_id,
      r.merchant_id AS merchant_id,
      r.mcc AS mcc,
      'USD' AS chargeback_currency,
      GREATEST(29, LEAST(200, r.raw_amt + a.adj_base + IF(r.seq_no <= a.adj_rem, a.adj_sign, 0))) AS chargeback_amount,
      ELT(
        MOD(r.seq_no - 1, 5) + 1,
        'FRAUD_CARD_NOT_PRESENT',
        'PRODUCT_NOT_RECEIVED',
        'CREDIT_NOT_PROCESSED',
        'DUPLICATE_PROCESSING',
        'SUBSCRIPTION_CANCELLED'
      ) AS chargeback_reason,
      DATE_ADD(
        DATE_ADD(v_month_start, INTERVAL (v_days_in_month - 1) DAY),
        INTERVAL MOD((r.seq_no + CAST(SUBSTRING(r.merchant_id, 2) AS UNSIGNED)) * 71, 86400) SECOND
      ) AS chargeback_time
    FROM tmp_cb_raw r
    JOIN tmp_cb_agg a ON a.merchant_id = r.merchant_id
    ORDER BY r.merchant_id, r.seq_no;

    DROP TEMPORARY TABLE IF EXISTS tmp_fraud_raw;
    DROP TEMPORARY TABLE IF EXISTS tmp_fraud_agg;

    CREATE TEMPORARY TABLE tmp_fraud_raw AS
    SELECT
      mm.merchant_id,
      mm.mcc,
      mm.tx_count,
      mm.fraud_cents,
      (s.n + 1) AS seq_no,
      ac.amt AS raw_amt
    FROM tmp_mm mm
    JOIN tmp_seq s ON s.n < mm.fraud_count
    JOIN tmp_amt_catalog ac
      ON ac.merchant_id = mm.merchant_id
      AND ac.seq_idx = MOD((s.n * 5 + 3), mm.cat_size) + 1;

    CREATE TEMPORARY TABLE tmp_fraud_agg AS
    SELECT
      merchant_id,
      COUNT(*) AS cnt_rows,
      ROUND(MAX(fraud_cents) / 100, 0) AS target_units,
      SUM(raw_amt) AS sum_raw_units,
      (ROUND(MAX(fraud_cents) / 100, 0) - SUM(raw_amt)) AS delta_units,
      CASE
        WHEN (ROUND(MAX(fraud_cents) / 100, 0) - SUM(raw_amt)) >= 0 THEN FLOOR((ROUND(MAX(fraud_cents) / 100, 0) - SUM(raw_amt)) / COUNT(*))
        ELSE -FLOOR(ABS(ROUND(MAX(fraud_cents) / 100, 0) - SUM(raw_amt)) / COUNT(*))
      END AS adj_base,
      ABS(ROUND(MAX(fraud_cents) / 100, 0) - SUM(raw_amt)) - (
        ABS(
          CASE
            WHEN (ROUND(MAX(fraud_cents) / 100, 0) - SUM(raw_amt)) >= 0 THEN FLOOR((ROUND(MAX(fraud_cents) / 100, 0) - SUM(raw_amt)) / COUNT(*))
            ELSE -FLOOR(ABS(ROUND(MAX(fraud_cents) / 100, 0) - SUM(raw_amt)) / COUNT(*))
          END
        ) * COUNT(*)
      ) AS adj_rem,
      CASE WHEN (ROUND(MAX(fraud_cents) / 100, 0) - SUM(raw_amt)) >= 0 THEN 1 ELSE -1 END AS adj_sign
    FROM tmp_fraud_raw
    GROUP BY merchant_id;

    INSERT INTO fraud_events (
      original_order_id, merchant_id, mcc, currency, amount, fraud_time
    )
    SELECT
      CONCAT('ORD', v_ym, SUBSTRING(r.merchant_id, 2), LPAD((MOD((r.seq_no - 1) * 7, r.tx_count) + 1), 8, '0')) AS original_order_id,
      r.merchant_id AS merchant_id,
      r.mcc AS mcc,
      'USD' AS currency,
      GREATEST(29, LEAST(200, r.raw_amt + a.adj_base + IF(r.seq_no <= a.adj_rem, a.adj_sign, 0))) AS amount,
      DATE_ADD(
        v_month_start,
        INTERVAL (r.seq_no + CAST(SUBSTRING(r.merchant_id, 2) AS UNSIGNED) * 5) MINUTE
      ) AS fraud_time
    FROM tmp_fraud_raw r
    JOIN tmp_fraud_agg a ON a.merchant_id = r.merchant_id
    ORDER BY r.merchant_id, r.seq_no;
  END LOOP;
  CLOSE cur_targets;
END$$
DELIMITER ;

-- Example run:
-- CALL sp_generate_demo_data('202512', '202605');
