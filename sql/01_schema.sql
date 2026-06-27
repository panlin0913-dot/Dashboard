CREATE DATABASE IF NOT EXISTS demo_payments
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;

USE demo_payments;

CREATE TABLE IF NOT EXISTS merchants (
  merchant_id VARCHAR(32) PRIMARY KEY,
  merchant_name VARCHAR(128) NOT NULL,
  mcc VARCHAR(4) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS transactions (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  merchant_id VARCHAR(32) NOT NULL,
  order_id VARCHAR(64) NOT NULL,
  currency CHAR(3) NOT NULL,
  amount DECIMAL(18,2) NOT NULL,
  mcc VARCHAR(4) NOT NULL,
  payment_status ENUM('SUCCESS', 'FAILED', 'PENDING') NOT NULL,
  txn_time DATETIME NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_transactions_order_id (order_id),
  KEY idx_transactions_merchant_time (merchant_id, txn_time),
  KEY idx_transactions_status_time (payment_status, txn_time),
  CONSTRAINT fk_transactions_merchant
    FOREIGN KEY (merchant_id) REFERENCES merchants (merchant_id)
);

CREATE TABLE IF NOT EXISTS refunds (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  original_order_id VARCHAR(64) NOT NULL,
  refund_currency CHAR(3) NOT NULL,
  refund_amount DECIMAL(18,2) NOT NULL,
  refund_status ENUM('SUCCESS', 'FAILED', 'PENDING') NOT NULL,
  refund_time DATETIME NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_refunds_order_id (original_order_id),
  KEY idx_refunds_time (refund_time),
  CONSTRAINT fk_refunds_original_order
    FOREIGN KEY (original_order_id) REFERENCES transactions (order_id)
);

CREATE TABLE IF NOT EXISTS chargebacks (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  original_order_id VARCHAR(64) NOT NULL,
  merchant_id VARCHAR(32) NOT NULL,
  mcc VARCHAR(4) NOT NULL,
  chargeback_currency CHAR(3) NOT NULL,
  chargeback_amount DECIMAL(18,2) NOT NULL,
  chargeback_reason VARCHAR(255) NOT NULL,
  chargeback_time DATETIME NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_chargebacks_order_id (original_order_id),
  KEY idx_chargebacks_merchant_time (merchant_id, chargeback_time),
  CONSTRAINT fk_chargebacks_original_order
    FOREIGN KEY (original_order_id) REFERENCES transactions (order_id),
  CONSTRAINT fk_chargebacks_merchant
    FOREIGN KEY (merchant_id) REFERENCES merchants (merchant_id)
);

CREATE TABLE IF NOT EXISTS fraud_events (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  original_order_id VARCHAR(64) NOT NULL,
  merchant_id VARCHAR(32) NOT NULL,
  mcc VARCHAR(4) NOT NULL,
  currency CHAR(3) NOT NULL,
  amount DECIMAL(18,2) NOT NULL,
  fraud_time DATETIME NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_fraud_order_id (original_order_id),
  KEY idx_fraud_merchant_time (merchant_id, fraud_time),
  CONSTRAINT fk_fraud_original_order
    FOREIGN KEY (original_order_id) REFERENCES transactions (order_id),
  CONSTRAINT fk_fraud_merchant
    FOREIGN KEY (merchant_id) REFERENCES merchants (merchant_id)
);
