CREATE DATABASE IF NOT EXISTS `payment_dashboard_db`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'app_user'@'%' IDENTIFIED BY 'app_password';
GRANT ALL PRIVILEGES ON `payment_dashboard_db`.* TO 'app_user'@'%';
FLUSH PRIVILEGES;

USE `payment_dashboard_db`;

CREATE TABLE IF NOT EXISTS merchants (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  merchant_code VARCHAR(64) NOT NULL UNIQUE,
  name VARCHAR(128) NOT NULL,
  status ENUM('onboarding', 'active', 'suspended') NOT NULL DEFAULT 'active',
  risk_level ENUM('low', 'medium', 'high') NOT NULL DEFAULT 'medium',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS orders (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  merchant_id BIGINT UNSIGNED NOT NULL,
  order_no VARCHAR(64) NOT NULL,
  amount DECIMAL(18, 2) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'CNY',
  order_status ENUM('created', 'paid', 'failed', 'refunded', 'chargeback') NOT NULL DEFAULT 'created',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uk_merchant_order_no (merchant_id, order_no),
  KEY idx_orders_merchant_created_at (merchant_id, created_at),
  CONSTRAINT fk_orders_merchant_id
    FOREIGN KEY (merchant_id) REFERENCES merchants (id)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS transactions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  merchant_id BIGINT UNSIGNED NOT NULL,
  order_id BIGINT UNSIGNED NOT NULL,
  transaction_no VARCHAR(64) NOT NULL UNIQUE,
  amount DECIMAL(18, 2) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'CNY',
  channel VARCHAR(32) NOT NULL,
  status ENUM('success', 'failed', 'pending') NOT NULL DEFAULT 'pending',
  decline_reason VARCHAR(255) DEFAULT NULL,
  processed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_transactions_merchant_processed_at (merchant_id, processed_at),
  KEY idx_transactions_order_id (order_id),
  CONSTRAINT fk_transactions_merchant_id
    FOREIGN KEY (merchant_id) REFERENCES merchants (id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_transactions_order_id
    FOREIGN KEY (order_id) REFERENCES orders (id)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS refunds (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  merchant_id BIGINT UNSIGNED NOT NULL,
  transaction_id BIGINT UNSIGNED NOT NULL,
  refund_no VARCHAR(64) NOT NULL UNIQUE,
  amount DECIMAL(18, 2) NOT NULL,
  status ENUM('submitted', 'approved', 'rejected', 'completed') NOT NULL DEFAULT 'submitted',
  reason VARCHAR(255) DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMP NULL DEFAULT NULL,
  KEY idx_refunds_merchant_created_at (merchant_id, created_at),
  KEY idx_refunds_transaction_id (transaction_id),
  CONSTRAINT fk_refunds_merchant_id
    FOREIGN KEY (merchant_id) REFERENCES merchants (id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_refunds_transaction_id
    FOREIGN KEY (transaction_id) REFERENCES transactions (id)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS chargebacks (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  merchant_id BIGINT UNSIGNED NOT NULL,
  transaction_id BIGINT UNSIGNED NOT NULL,
  chargeback_no VARCHAR(64) NOT NULL UNIQUE,
  amount DECIMAL(18, 2) NOT NULL,
  stage ENUM('pre_arbitration', 'arbitration', 'won', 'lost') NOT NULL DEFAULT 'pre_arbitration',
  reason VARCHAR(255) DEFAULT NULL,
  opened_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  closed_at TIMESTAMP NULL DEFAULT NULL,
  KEY idx_chargebacks_merchant_opened_at (merchant_id, opened_at),
  KEY idx_chargebacks_transaction_id (transaction_id),
  CONSTRAINT fk_chargebacks_merchant_id
    FOREIGN KEY (merchant_id) REFERENCES merchants (id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_chargebacks_transaction_id
    FOREIGN KEY (transaction_id) REFERENCES transactions (id)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS fraud_cases (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  merchant_id BIGINT UNSIGNED NOT NULL,
  transaction_id BIGINT UNSIGNED DEFAULT NULL,
  case_no VARCHAR(64) NOT NULL UNIQUE,
  risk_score DECIMAL(5, 2) NOT NULL,
  decision ENUM('review', 'blocked', 'approved') NOT NULL DEFAULT 'review',
  status ENUM('open', 'confirmed_fraud', 'false_positive', 'closed') NOT NULL DEFAULT 'open',
  detected_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  closed_at TIMESTAMP NULL DEFAULT NULL,
  KEY idx_fraud_cases_merchant_detected_at (merchant_id, detected_at),
  KEY idx_fraud_cases_transaction_id (transaction_id),
  CONSTRAINT fk_fraud_cases_merchant_id
    FOREIGN KEY (merchant_id) REFERENCES merchants (id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_fraud_cases_transaction_id
    FOREIGN KEY (transaction_id) REFERENCES transactions (id)
    ON UPDATE CASCADE ON DELETE SET NULL
);

INSERT INTO merchants (merchant_code, name, status, risk_level)
VALUES
  ('M1001', 'Nebula Shop', 'active', 'medium'),
  ('M1002', 'Atlas Travel', 'active', 'low'),
  ('M1003', 'Zenith Digital', 'active', 'high')
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  status = VALUES(status),
  risk_level = VALUES(risk_level);

INSERT INTO orders (merchant_id, order_no, amount, currency, order_status)
SELECT m.id, 'ORD-M1001-0001', 1280.00, 'CNY', 'paid'
FROM merchants m
WHERE m.merchant_code = 'M1001'
ON DUPLICATE KEY UPDATE amount = VALUES(amount), order_status = VALUES(order_status);

INSERT INTO orders (merchant_id, order_no, amount, currency, order_status)
SELECT m.id, 'ORD-M1001-0002', 880.00, 'CNY', 'paid'
FROM merchants m
WHERE m.merchant_code = 'M1001'
ON DUPLICATE KEY UPDATE amount = VALUES(amount), order_status = VALUES(order_status);

INSERT INTO orders (merchant_id, order_no, amount, currency, order_status)
SELECT m.id, 'ORD-M1002-0001', 2999.00, 'CNY', 'paid'
FROM merchants m
WHERE m.merchant_code = 'M1002'
ON DUPLICATE KEY UPDATE amount = VALUES(amount), order_status = VALUES(order_status);

INSERT INTO transactions (merchant_id, order_id, transaction_no, amount, currency, channel, status)
SELECT m.id, o.id, 'TXN-M1001-0001', 1280.00, 'CNY', 'wechat', 'success'
FROM merchants m
JOIN orders o ON o.merchant_id = m.id AND o.order_no = 'ORD-M1001-0001'
WHERE m.merchant_code = 'M1001'
ON DUPLICATE KEY UPDATE amount = VALUES(amount), status = VALUES(status);

INSERT INTO transactions (merchant_id, order_id, transaction_no, amount, currency, channel, status)
SELECT m.id, o.id, 'TXN-M1001-0002', 880.00, 'CNY', 'alipay', 'success'
FROM merchants m
JOIN orders o ON o.merchant_id = m.id AND o.order_no = 'ORD-M1001-0002'
WHERE m.merchant_code = 'M1001'
ON DUPLICATE KEY UPDATE amount = VALUES(amount), status = VALUES(status);

INSERT INTO transactions (merchant_id, order_id, transaction_no, amount, currency, channel, status, decline_reason)
SELECT m.id, o.id, 'TXN-M1002-0001', 2999.00, 'CNY', 'card', 'failed', 'insufficient_funds'
FROM merchants m
JOIN orders o ON o.merchant_id = m.id AND o.order_no = 'ORD-M1002-0001'
WHERE m.merchant_code = 'M1002'
ON DUPLICATE KEY UPDATE status = VALUES(status), decline_reason = VALUES(decline_reason);

INSERT INTO refunds (merchant_id, transaction_id, refund_no, amount, status, reason, completed_at)
SELECT t.merchant_id, t.id, 'RFD-M1001-0001', 200.00, 'completed', 'partial_refund', CURRENT_TIMESTAMP
FROM transactions t
WHERE t.transaction_no = 'TXN-M1001-0001'
ON DUPLICATE KEY UPDATE amount = VALUES(amount), status = VALUES(status);

INSERT INTO chargebacks (merchant_id, transaction_id, chargeback_no, amount, stage, reason)
SELECT t.merchant_id, t.id, 'CBK-M1001-0001', 100.00, 'pre_arbitration', 'customer_dispute'
FROM transactions t
WHERE t.transaction_no = 'TXN-M1001-0002'
ON DUPLICATE KEY UPDATE amount = VALUES(amount), stage = VALUES(stage);

INSERT INTO fraud_cases (merchant_id, transaction_id, case_no, risk_score, decision, status)
SELECT t.merchant_id, t.id, 'FRAUD-M1002-0001', 91.50, 'blocked', 'confirmed_fraud'
FROM transactions t
WHERE t.transaction_no = 'TXN-M1002-0001'
ON DUPLICATE KEY UPDATE
  risk_score = VALUES(risk_score),
  decision = VALUES(decision),
  status = VALUES(status);
