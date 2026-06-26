const mysql = require("mysql2/promise");

const {
  MYSQL_HOST = "127.0.0.1",
  MYSQL_PORT = "3306",
  MYSQL_USER = "app_user",
  MYSQL_PASSWORD = "app_password",
  MYSQL_DATABASE = "web_app_db",
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
      CREATE TABLE IF NOT EXISTS users (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(80) NOT NULL,
        email VARCHAR(120) NOT NULL UNIQUE,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
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
