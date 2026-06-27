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
  });

  try {
    await bootstrapConnection.query(
      `CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;`,
    );
    await bootstrapConnection.query(`USE \`${MYSQL_DATABASE}\`;`);

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
    `);
    await bootstrapConnection.query(`
      ALTER TABLE transaction_orders
      ADD COLUMN IF NOT EXISTS mcc VARCHAR(4) NOT NULL DEFAULT '0000' AFTER channel_name;
    `);

    await bootstrapConnection.query(`
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
    `);

    await bootstrapConnection.query(`
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
    `);

    await bootstrapConnection.query(`
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
