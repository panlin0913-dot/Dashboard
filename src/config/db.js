const mysql = require("mysql2/promise");

const {
  MYSQL_HOST = "127.0.0.1",
  MYSQL_PORT = "3306",
  MYSQL_USER = "app_user",
  MYSQL_PASSWORD = "app_password",
  MYSQL_DATABASE = "payment_dashboard_db",
} = process.env;

let pool;

function getPool() {
  if (!pool) {
    pool = mysql.createPool({
      host: MYSQL_HOST,
      port: Number(MYSQL_PORT),
      user: MYSQL_USER,
      password: MYSQL_PASSWORD,
      database: MYSQL_DATABASE,
      waitForConnections: true,
      connectionLimit: 10,
      queueLimit: 0,
    });
  }

  return pool;
}

async function initializeDatabase() {
  const bootstrapConnection = await mysql.createConnection({
    host: MYSQL_HOST,
    port: Number(MYSQL_PORT),
    user: MYSQL_USER,
    password: MYSQL_PASSWORD,
    database: MYSQL_DATABASE,
  });

  try {
    await bootstrapConnection.query(`
      CREATE TABLE IF NOT EXISTS merchants (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        merchant_code VARCHAR(64) NOT NULL UNIQUE,
        name VARCHAR(128) NOT NULL,
        status ENUM('onboarding', 'active', 'suspended') NOT NULL DEFAULT 'active',
        risk_level ENUM('low', 'medium', 'high') NOT NULL DEFAULT 'medium',
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    `);
    await bootstrapConnection.query(`
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
    `);
    await bootstrapConnection.query(`
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
    `);
    await bootstrapConnection.query(`
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
    `);
    await bootstrapConnection.query(`
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
    `);
    await bootstrapConnection.query(`
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
    `);
  } finally {
    await bootstrapConnection.end();
  }
}

async function query(sql, params = []) {
  const [rows] = await getPool().execute(sql, params);
  return rows;
}

module.exports = {
  initializeDatabase,
  query,
};
