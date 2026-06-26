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

CREATE TABLE IF NOT EXISTS transaction_orders (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  merchant_id BIGINT UNSIGNED NOT NULL,
  order_no VARCHAR(64) NOT NULL UNIQUE,
  merchant_name VARCHAR(128) NOT NULL,
  card_number_first6_last4 VARCHAR(16) NOT NULL,
  channel_name VARCHAR(64) NOT NULL,
  mcc VARCHAR(4) NOT NULL,
  order_amount DECIMAL(18, 2) NOT NULL,
  order_currency CHAR(3) NOT NULL DEFAULT 'CNY',
  payer_email VARCHAR(120) NOT NULL,
  payer_name VARCHAR(80) NOT NULL,
  payment_status ENUM('pending', 'paid', 'failed', 'refunded', 'chargeback') NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  paid_at TIMESTAMP NULL DEFAULT NULL,
  KEY idx_transaction_orders_merchant_created_at (merchant_id, created_at),
  KEY idx_transaction_orders_payment_status (payment_status),
  CONSTRAINT fk_transaction_orders_merchant_id
    FOREIGN KEY (merchant_id) REFERENCES merchants (id)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

ALTER TABLE transaction_orders
  ADD COLUMN IF NOT EXISTS mcc VARCHAR(4) NOT NULL DEFAULT '0000' AFTER channel_name;

CREATE TABLE IF NOT EXISTS order_refunds (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  merchant_id BIGINT UNSIGNED NOT NULL,
  refund_no VARCHAR(64) NOT NULL UNIQUE,
  original_order_no VARCHAR(64) NOT NULL,
  refund_currency CHAR(3) NOT NULL DEFAULT 'CNY',
  refund_amount DECIMAL(18, 2) NOT NULL,
  refund_status ENUM('submitted', 'processing', 'completed', 'failed') NOT NULL DEFAULT 'submitted',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_order_refunds_merchant_created_at (merchant_id, created_at),
  KEY idx_order_refunds_original_order_no (original_order_no),
  CONSTRAINT fk_order_refunds_merchant_id
    FOREIGN KEY (merchant_id) REFERENCES merchants (id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_order_refunds_original_order_no
    FOREIGN KEY (original_order_no) REFERENCES transaction_orders (order_no)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS order_chargebacks (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  merchant_id BIGINT UNSIGNED NOT NULL,
  chargeback_no VARCHAR(64) NOT NULL UNIQUE,
  original_order_no VARCHAR(64) NOT NULL,
  chargeback_amount DECIMAL(18, 2) NOT NULL,
  chargeback_status ENUM('open', 'investigating', 'won', 'lost', 'closed') NOT NULL DEFAULT 'open',
  chargeback_reason VARCHAR(255) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_order_chargebacks_merchant_created_at (merchant_id, created_at),
  KEY idx_order_chargebacks_original_order_no (original_order_no),
  CONSTRAINT fk_order_chargebacks_merchant_id
    FOREIGN KEY (merchant_id) REFERENCES merchants (id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_order_chargebacks_original_order_no
    FOREIGN KEY (original_order_no) REFERENCES transaction_orders (order_no)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS order_fraud_cases (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  merchant_id BIGINT UNSIGNED NOT NULL,
  case_no VARCHAR(64) NOT NULL UNIQUE,
  original_order_no VARCHAR(64) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'CNY',
  amount DECIMAL(18, 2) NOT NULL,
  fraud_reason VARCHAR(255) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_order_fraud_cases_merchant_created_at (merchant_id, created_at),
  KEY idx_order_fraud_cases_original_order_no (original_order_no),
  CONSTRAINT fk_order_fraud_cases_merchant_id
    FOREIGN KEY (merchant_id) REFERENCES merchants (id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_order_fraud_cases_original_order_no
    FOREIGN KEY (original_order_no) REFERENCES transaction_orders (order_no)
    ON UPDATE CASCADE ON DELETE RESTRICT
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

INSERT INTO transaction_orders
  (merchant_id, order_no, merchant_name, card_number_first6_last4, channel_name, mcc, order_amount, order_currency, payer_email, payer_name, payment_status, paid_at)
SELECT m.id, 'ORD-M1001-0001', m.name, '6222021234', 'alipay', '5411', 1280.00, 'CNY', 'alice@nebula.com', 'Alice', 'paid', CURRENT_TIMESTAMP
FROM merchants m
WHERE m.merchant_code = 'M1001'
ON DUPLICATE KEY UPDATE
  payment_status = VALUES(payment_status),
  order_amount = VALUES(order_amount);

INSERT INTO transaction_orders
  (merchant_id, order_no, merchant_name, card_number_first6_last4, channel_name, mcc, order_amount, order_currency, payer_email, payer_name, payment_status, paid_at)
SELECT m.id, 'ORD-M1001-0002', m.name, '6228485678', 'wechat', '5732', 880.00, 'CNY', 'bob@nebula.com', 'Bob', 'paid', CURRENT_TIMESTAMP
FROM merchants m
WHERE m.merchant_code = 'M1001'
ON DUPLICATE KEY UPDATE
  payment_status = VALUES(payment_status),
  order_amount = VALUES(order_amount);

INSERT INTO transaction_orders
  (merchant_id, order_no, merchant_name, card_number_first6_last4, channel_name, mcc, order_amount, order_currency, payer_email, payer_name, payment_status)
SELECT m.id, 'ORD-M1002-0001', m.name, '4111111234', 'card', '4722', 2999.00, 'CNY', 'carol@atlas.com', 'Carol', 'failed'
FROM merchants m
WHERE m.merchant_code = 'M1002'
ON DUPLICATE KEY UPDATE
  payment_status = VALUES(payment_status),
  order_amount = VALUES(order_amount);

INSERT INTO order_refunds
  (merchant_id, refund_no, original_order_no, refund_currency, refund_amount, refund_status)
SELECT m.id, 'RFD-M1001-0001', 'ORD-M1001-0001', 'CNY', 200.00, 'completed'
FROM merchants m
WHERE m.merchant_code = 'M1001'
ON DUPLICATE KEY UPDATE
  refund_amount = VALUES(refund_amount),
  refund_status = VALUES(refund_status);

INSERT INTO order_chargebacks
  (merchant_id, chargeback_no, original_order_no, chargeback_amount, chargeback_status, chargeback_reason)
SELECT m.id, 'CBK-M1001-0001', 'ORD-M1001-0002', 100.00, 'investigating', 'cardholder_dispute'
FROM merchants m
WHERE m.merchant_code = 'M1001'
ON DUPLICATE KEY UPDATE
  chargeback_amount = VALUES(chargeback_amount),
  chargeback_status = VALUES(chargeback_status),
  chargeback_reason = VALUES(chargeback_reason);

INSERT INTO order_fraud_cases
  (merchant_id, case_no, original_order_no, currency, amount, fraud_reason)
SELECT m.id, 'FRAUD-M1002-0001', 'ORD-M1002-0001', 'CNY', 2999.00, 'stolen_card_pattern'
FROM merchants m
WHERE m.merchant_code = 'M1002'
ON DUPLICATE KEY UPDATE
  amount = VALUES(amount),
  fraud_reason = VALUES(fraud_reason);
