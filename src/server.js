require("dotenv").config();

const express = require("express");
const { initializeDatabase, query } = require("./config/db");

const app = express();
const port = Number(process.env.PORT || 3000);

app.use(express.json());

app.get("/", (_req, res) => {
  res.json({
    message: "Payment merchant dashboard service is running.",
  });
});

app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
  });
});

function toSqlDate(input) {
  if (!input) {
    return null;
  }
  if (Number.isNaN(Date.parse(input))) {
    return null;
  }
  return new Date(input).toISOString().slice(0, 19).replace("T", " ");
}

function buildDateFilter(column, startDate, endDate, params) {
  let sql = "";
  if (startDate) {
    sql += ` AND ${column} >= ?`;
    params.push(startDate);
  }
  if (endDate) {
    sql += ` AND ${column} <= ?`;
    params.push(endDate);
  }
  return sql;
}

function toNumber(value) {
  if (value === null || value === undefined) {
    return 0;
  }
  return Number(value);
}

function toPercentage(numerator, denominator) {
  if (!denominator) {
    return 0;
  }
  return Number(((numerator / denominator) * 100).toFixed(2));
}

function classifyHealth(score) {
  if (score >= 85) {
    return "healthy";
  }
  if (score >= 70) {
    return "watch";
  }
  return "critical";
}

function calculateHealthScore({
  successRate,
  refundRate,
  chargebackRate,
  confirmedFraudRate,
}) {
  const penalty =
    (100 - successRate) * 0.35 +
    refundRate * 0.2 +
    chargebackRate * 1.5 +
    confirmedFraudRate * 1.8;
  const score = Math.max(0, Math.min(100, 100 - penalty));
  return Number(score.toFixed(2));
}

function parseDateRange(req, res) {
  const startDate = toSqlDate(req.query.startDate);
  const endDate = toSqlDate(req.query.endDate);

  if (req.query.startDate && !startDate) {
    res.status(400).json({ error: "Invalid startDate format." });
    return null;
  }
  if (req.query.endDate && !endDate) {
    res.status(400).json({ error: "Invalid endDate format." });
    return null;
  }
  if (startDate && endDate && startDate > endDate) {
    res.status(400).json({ error: "startDate must be earlier than endDate." });
    return null;
  }

  return { startDate, endDate };
}

async function getMerchantById(merchantId) {
  const rows = await query(
    "SELECT id, merchant_code, name, status, risk_level, created_at FROM merchants WHERE id = ?",
    [merchantId],
  );
  return rows[0] || null;
}

async function getMerchantKpi({ merchantId = null, startDate = null, endDate = null }) {
  const txParams = [];
  let txWhere = " WHERE 1=1";
  if (merchantId) {
    txWhere += " AND merchant_id = ?";
    txParams.push(merchantId);
  }
  txWhere += buildDateFilter("processed_at", startDate, endDate, txParams);
  const txRows = await query(
    `
      SELECT
        COUNT(*) AS total_transactions,
        SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS success_transactions,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_transactions,
        COALESCE(SUM(CASE WHEN status = 'success' THEN amount ELSE 0 END), 0) AS gmv
      FROM transactions
      ${txWhere}
    `,
    txParams,
  );
  const tx = txRows[0];

  const orderParams = [];
  let orderWhere = " WHERE 1=1";
  if (merchantId) {
    orderWhere += " AND merchant_id = ?";
    orderParams.push(merchantId);
  }
  orderWhere += buildDateFilter("created_at", startDate, endDate, orderParams);
  const orderRows = await query(
    `
      SELECT COUNT(*) AS total_orders
      FROM orders
      ${orderWhere}
    `,
    orderParams,
  );

  const refundParams = [];
  let refundWhere = " WHERE status IN ('approved', 'completed')";
  if (merchantId) {
    refundWhere += " AND merchant_id = ?";
    refundParams.push(merchantId);
  }
  refundWhere += buildDateFilter("created_at", startDate, endDate, refundParams);
  const refundRows = await query(
    `
      SELECT
        COUNT(*) AS total_refunds,
        COALESCE(SUM(amount), 0) AS refund_amount
      FROM refunds
      ${refundWhere}
    `,
    refundParams,
  );

  const chargebackParams = [];
  let chargebackWhere = " WHERE 1=1";
  if (merchantId) {
    chargebackWhere += " AND merchant_id = ?";
    chargebackParams.push(merchantId);
  }
  chargebackWhere += buildDateFilter("opened_at", startDate, endDate, chargebackParams);
  const chargebackRows = await query(
    `
      SELECT
        COUNT(*) AS total_chargebacks,
        COALESCE(SUM(amount), 0) AS chargeback_amount
      FROM chargebacks
      ${chargebackWhere}
    `,
    chargebackParams,
  );

  const fraudParams = [];
  let fraudWhere = " WHERE status = 'confirmed_fraud'";
  if (merchantId) {
    fraudWhere += " AND merchant_id = ?";
    fraudParams.push(merchantId);
  }
  fraudWhere += buildDateFilter("detected_at", startDate, endDate, fraudParams);
  const fraudRows = await query(
    `
      SELECT COUNT(*) AS confirmed_fraud_cases
      FROM fraud_cases
      ${fraudWhere}
    `,
    fraudParams,
  );

  return {
    totalOrders: toNumber(orderRows[0].total_orders),
    totalTransactions: toNumber(tx.total_transactions),
    successTransactions: toNumber(tx.success_transactions),
    failedTransactions: toNumber(tx.failed_transactions),
    gmv: toNumber(tx.gmv),
    totalRefunds: toNumber(refundRows[0].total_refunds),
    refundAmount: toNumber(refundRows[0].refund_amount),
    totalChargebacks: toNumber(chargebackRows[0].total_chargebacks),
    chargebackAmount: toNumber(chargebackRows[0].chargeback_amount),
    confirmedFraudCases: toNumber(fraudRows[0].confirmed_fraud_cases),
  };
}

function buildDashboardSummary(kpi) {
  const successRate = toPercentage(kpi.successTransactions, kpi.totalTransactions);
  const refundRate = toPercentage(kpi.totalRefunds, kpi.successTransactions);
  const chargebackRate = toPercentage(kpi.totalChargebacks, kpi.successTransactions);
  const confirmedFraudRate = toPercentage(
    kpi.confirmedFraudCases,
    kpi.totalTransactions,
  );
  const healthScore = calculateHealthScore({
    successRate,
    refundRate,
    chargebackRate,
    confirmedFraudRate,
  });

  return {
    ...kpi,
    successRate,
    refundRate,
    chargebackRate,
    confirmedFraudRate,
    healthScore,
    healthLevel: classifyHealth(healthScore),
  };
}

async function ensureTransactionBelongsToMerchant(merchantId, transactionId) {
  const rows = await query(
    "SELECT id FROM transactions WHERE id = ? AND merchant_id = ?",
    [transactionId, merchantId],
  );
  return rows.length > 0;
}

async function ensureOrderBelongsToMerchant(merchantId, orderId) {
  const rows = await query("SELECT id FROM orders WHERE id = ? AND merchant_id = ?", [
    orderId,
    merchantId,
  ]);
  return rows.length > 0;
}

app.post("/api/merchants", async (req, res) => {
  const { merchantCode, name, status = "active", riskLevel = "medium" } = req.body;

  if (!merchantCode || !name) {
    return res.status(400).json({ error: "merchantCode and name are required." });
  }

  try {
    const result = await query(
      `
        INSERT INTO merchants (merchant_code, name, status, risk_level)
        VALUES (?, ?, ?, ?)
      `,
      [merchantCode, name, status, riskLevel],
    );
    return res.status(201).json({
      id: result.insertId,
      merchantCode,
      name,
      status,
      riskLevel,
    });
  } catch (error) {
    if (error && error.code === "ER_DUP_ENTRY") {
      return res.status(409).json({ error: "merchantCode already exists." });
    }
    if (error && error.code === "ER_TRUNCATED_WRONG_VALUE_FOR_FIELD") {
      return res.status(400).json({ error: "Invalid status or riskLevel." });
    }
    return res.status(500).json({ error: "Failed to create merchant." });
  }
});

app.get("/api/merchants", async (_req, res) => {
  try {
    const merchants = await query(
      `
        SELECT id, merchant_code, name, status, risk_level, created_at
        FROM merchants
        ORDER BY id DESC
      `,
    );
    return res.json(merchants);
  } catch (error) {
    return res.status(500).json({ error: "Failed to fetch merchants." });
  }
});

app.post("/api/orders", async (req, res) => {
  const {
    merchantId,
    orderNo,
    amount,
    currency = "CNY",
    orderStatus = "created",
  } = req.body;

  if (!merchantId || !orderNo || amount === undefined) {
    return res
      .status(400)
      .json({ error: "merchantId, orderNo, amount are required." });
  }

  try {
    const result = await query(
      `
        INSERT INTO orders (merchant_id, order_no, amount, currency, order_status)
        VALUES (?, ?, ?, ?, ?)
      `,
      [merchantId, orderNo, amount, currency, orderStatus],
    );
    return res.status(201).json({
      id: result.insertId,
      merchantId,
      orderNo,
    });
  } catch (error) {
    if (error && error.code === "ER_NO_REFERENCED_ROW_2") {
      return res.status(400).json({ error: "merchantId does not exist." });
    }
    if (error && error.code === "ER_DUP_ENTRY") {
      return res.status(409).json({ error: "orderNo already exists for merchant." });
    }
    if (error && error.code === "ER_TRUNCATED_WRONG_VALUE_FOR_FIELD") {
      return res.status(400).json({ error: "Invalid orderStatus." });
    }
    return res.status(500).json({ error: "Failed to create order." });
  }
});

app.post("/api/transactions", async (req, res) => {
  const {
    merchantId,
    orderId,
    transactionNo,
    amount,
    currency = "CNY",
    channel,
    status = "pending",
    declineReason = null,
    processedAt = null,
  } = req.body;

  if (!merchantId || !orderId || !transactionNo || amount === undefined || !channel) {
    return res.status(400).json({
      error:
        "merchantId, orderId, transactionNo, amount, channel are required.",
    });
  }

  try {
    const matched = await ensureOrderBelongsToMerchant(merchantId, orderId);
    if (!matched) {
      return res
        .status(400)
        .json({ error: "orderId does not belong to merchantId." });
    }

    const result = await query(
      `
        INSERT INTO transactions
        (merchant_id, order_id, transaction_no, amount, currency, channel, status, decline_reason, processed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP))
      `,
      [
        merchantId,
        orderId,
        transactionNo,
        amount,
        currency,
        channel,
        status,
        declineReason,
        toSqlDate(processedAt),
      ],
    );
    return res.status(201).json({
      id: result.insertId,
      transactionNo,
    });
  } catch (error) {
    if (error && error.code === "ER_DUP_ENTRY") {
      return res.status(409).json({ error: "transactionNo already exists." });
    }
    if (error && error.code === "ER_NO_REFERENCED_ROW_2") {
      return res.status(400).json({ error: "merchantId or orderId does not exist." });
    }
    if (error && error.code === "ER_TRUNCATED_WRONG_VALUE_FOR_FIELD") {
      return res.status(400).json({ error: "Invalid transaction status." });
    }
    return res.status(500).json({ error: "Failed to create transaction." });
  }
});

app.post("/api/refunds", async (req, res) => {
  const {
    merchantId,
    transactionId,
    refundNo,
    amount,
    status = "submitted",
    reason = null,
    completedAt = null,
  } = req.body;

  if (!merchantId || !transactionId || !refundNo || amount === undefined) {
    return res.status(400).json({
      error: "merchantId, transactionId, refundNo, amount are required.",
    });
  }

  try {
    const matched = await ensureTransactionBelongsToMerchant(
      merchantId,
      transactionId,
    );
    if (!matched) {
      return res
        .status(400)
        .json({ error: "transactionId does not belong to merchantId." });
    }

    const result = await query(
      `
        INSERT INTO refunds
        (merchant_id, transaction_id, refund_no, amount, status, reason, completed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `,
      [
        merchantId,
        transactionId,
        refundNo,
        amount,
        status,
        reason,
        toSqlDate(completedAt),
      ],
    );
    return res.status(201).json({
      id: result.insertId,
      refundNo,
    });
  } catch (error) {
    if (error && error.code === "ER_DUP_ENTRY") {
      return res.status(409).json({ error: "refundNo already exists." });
    }
    if (error && error.code === "ER_TRUNCATED_WRONG_VALUE_FOR_FIELD") {
      return res.status(400).json({ error: "Invalid refund status." });
    }
    return res.status(500).json({ error: "Failed to create refund." });
  }
});

app.post("/api/chargebacks", async (req, res) => {
  const {
    merchantId,
    transactionId,
    chargebackNo,
    amount,
    stage = "pre_arbitration",
    reason = null,
    openedAt = null,
    closedAt = null,
  } = req.body;

  if (!merchantId || !transactionId || !chargebackNo || amount === undefined) {
    return res.status(400).json({
      error: "merchantId, transactionId, chargebackNo, amount are required.",
    });
  }

  try {
    const matched = await ensureTransactionBelongsToMerchant(
      merchantId,
      transactionId,
    );
    if (!matched) {
      return res
        .status(400)
        .json({ error: "transactionId does not belong to merchantId." });
    }

    const result = await query(
      `
        INSERT INTO chargebacks
        (merchant_id, transaction_id, chargeback_no, amount, stage, reason, opened_at, closed_at)
        VALUES (?, ?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP), ?)
      `,
      [
        merchantId,
        transactionId,
        chargebackNo,
        amount,
        stage,
        reason,
        toSqlDate(openedAt),
        toSqlDate(closedAt),
      ],
    );
    return res.status(201).json({
      id: result.insertId,
      chargebackNo,
    });
  } catch (error) {
    if (error && error.code === "ER_DUP_ENTRY") {
      return res.status(409).json({ error: "chargebackNo already exists." });
    }
    if (error && error.code === "ER_TRUNCATED_WRONG_VALUE_FOR_FIELD") {
      return res.status(400).json({ error: "Invalid chargeback stage." });
    }
    return res.status(500).json({ error: "Failed to create chargeback." });
  }
});

app.post("/api/fraud-cases", async (req, res) => {
  const {
    merchantId,
    transactionId = null,
    caseNo,
    riskScore,
    decision = "review",
    status = "open",
    detectedAt = null,
    closedAt = null,
  } = req.body;

  if (!merchantId || !caseNo || riskScore === undefined) {
    return res
      .status(400)
      .json({ error: "merchantId, caseNo, riskScore are required." });
  }

  try {
    if (transactionId) {
      const matched = await ensureTransactionBelongsToMerchant(
        merchantId,
        transactionId,
      );
      if (!matched) {
        return res
          .status(400)
          .json({ error: "transactionId does not belong to merchantId." });
      }
    }

    const result = await query(
      `
        INSERT INTO fraud_cases
        (merchant_id, transaction_id, case_no, risk_score, decision, status, detected_at, closed_at)
        VALUES (?, ?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP), ?)
      `,
      [
        merchantId,
        transactionId,
        caseNo,
        riskScore,
        decision,
        status,
        toSqlDate(detectedAt),
        toSqlDate(closedAt),
      ],
    );
    return res.status(201).json({
      id: result.insertId,
      caseNo,
    });
  } catch (error) {
    if (error && error.code === "ER_DUP_ENTRY") {
      return res.status(409).json({ error: "caseNo already exists." });
    }
    if (error && error.code === "ER_TRUNCATED_WRONG_VALUE_FOR_FIELD") {
      return res.status(400).json({ error: "Invalid fraud decision or status." });
    }
    return res.status(500).json({ error: "Failed to create fraud case." });
  }
});

app.get("/api/dashboard/platform", async (req, res) => {
  const range = parseDateRange(req, res);
  if (!range) {
    return;
  }

  try {
    const kpi = await getMerchantKpi(range);
    const coverageRows = await query(
      `
        SELECT
          COUNT(*) AS total_merchants,
          SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active_merchants
        FROM merchants
      `,
    );
    const transactingParams = [];
    let transactingWhere = " WHERE status = 'success'";
    transactingWhere += buildDateFilter(
      "processed_at",
      range.startDate,
      range.endDate,
      transactingParams,
    );
    const transactingRows = await query(
      `
        SELECT COUNT(DISTINCT merchant_id) AS transacting_merchants
        FROM transactions
        ${transactingWhere}
      `,
      transactingParams,
    );

    return res.json({
      timeframe: range,
      merchantCoverage: {
        totalMerchants: toNumber(coverageRows[0].total_merchants),
        activeMerchants: toNumber(coverageRows[0].active_merchants),
        transactingMerchants: toNumber(transactingRows[0].transacting_merchants),
      },
      dashboard: buildDashboardSummary(kpi),
    });
  } catch (error) {
    return res.status(500).json({ error: "Failed to build platform dashboard." });
  }
});

app.get("/api/dashboard/merchants", async (req, res) => {
  const range = parseDateRange(req, res);
  if (!range) {
    return;
  }

  try {
    const merchants = await query(
      `
        SELECT id, merchant_code, name, status, risk_level, created_at
        FROM merchants
        ORDER BY id DESC
      `,
    );
    const rows = await Promise.all(
      merchants.map(async (merchant) => ({
        ...merchant,
        dashboard: buildDashboardSummary(
          await getMerchantKpi({
            merchantId: merchant.id,
            startDate: range.startDate,
            endDate: range.endDate,
          }),
        ),
      })),
    );
    return res.json({
      timeframe: range,
      merchants: rows,
    });
  } catch (error) {
    return res.status(500).json({ error: "Failed to build merchants dashboard." });
  }
});

app.get("/api/dashboard/merchants/:merchantId", async (req, res) => {
  const range = parseDateRange(req, res);
  if (!range) {
    return;
  }

  const merchantId = Number(req.params.merchantId);
  if (!Number.isInteger(merchantId) || merchantId <= 0) {
    return res.status(400).json({ error: "merchantId must be a positive integer." });
  }

  try {
    const merchant = await getMerchantById(merchantId);
    if (!merchant) {
      return res.status(404).json({ error: "Merchant not found." });
    }

    const kpi = await getMerchantKpi({
      merchantId,
      startDate: range.startDate,
      endDate: range.endDate,
    });

    return res.json({
      timeframe: range,
      merchant,
      dashboard: buildDashboardSummary(kpi),
    });
  } catch (error) {
    return res.status(500).json({ error: "Failed to build merchant dashboard." });
  }
});

async function bootstrap() {
  try {
    await initializeDatabase();
    app.listen(port, () => {
      console.log(`Server started on http://localhost:${port}`);
    });
  } catch (error) {
    console.error("Failed to start application:", error.message);
    process.exit(1);
  }
}

bootstrap();
