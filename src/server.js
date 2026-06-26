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
  fraudRate,
}) {
  const penalty =
    (100 - successRate) * 0.35 +
    refundRate * 0.2 +
    chargebackRate * 1.5 +
    fraudRate * 1.8;
  const score = Math.max(0, Math.min(100, 100 - penalty));
  return Number(score.toFixed(2));
}

function normalizeCardFirst6Last4(input) {
  if (!input || typeof input !== "string") {
    return null;
  }

  const compactValue = input.trim().replace(/\s+/g, "");
  const pureDigitsPattern = /^\d{10}$/;
  const maskedPattern = /^\d{6}\*{0,6}\d{4}$/;

  if (pureDigitsPattern.test(compactValue) || maskedPattern.test(compactValue)) {
    return compactValue;
  }

  return null;
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

async function getTransactionOrderByNo(merchantId, orderNo) {
  const rows = await query(
    `
      SELECT id, order_no, merchant_id, payment_status
      FROM transaction_orders
      WHERE merchant_id = ? AND order_no = ?
    `,
    [merchantId, orderNo],
  );
  return rows[0] || null;
}

async function getMerchantKpi({ merchantId = null, startDate = null, endDate = null }) {
  const orderParams = [];
  let orderWhere = " WHERE 1=1";
  if (merchantId) {
    orderWhere += " AND merchant_id = ?";
    orderParams.push(merchantId);
  }
  orderWhere += buildDateFilter("created_at", startDate, endDate, orderParams);
  const orderRows = await query(
    `
      SELECT
        COUNT(*) AS total_transaction_orders,
        SUM(CASE WHEN payment_status = 'paid' THEN 1 ELSE 0 END) AS successful_payments,
        SUM(CASE WHEN payment_status = 'failed' THEN 1 ELSE 0 END) AS failed_payments,
        COALESCE(SUM(CASE WHEN payment_status = 'paid' THEN order_amount ELSE 0 END), 0) AS gmv
      FROM transaction_orders
      ${orderWhere}
    `,
    orderParams,
  );
  const order = orderRows[0];

  const refundParams = [];
  let refundWhere = " WHERE refund_status = 'completed'";
  if (merchantId) {
    refundWhere += " AND merchant_id = ?";
    refundParams.push(merchantId);
  }
  refundWhere += buildDateFilter("created_at", startDate, endDate, refundParams);
  const refundRows = await query(
    `
      SELECT
        COUNT(*) AS total_refunds,
        COALESCE(SUM(refund_amount), 0) AS refund_amount
      FROM order_refunds
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
  chargebackWhere += buildDateFilter(
    "created_at",
    startDate,
    endDate,
    chargebackParams,
  );
  const chargebackRows = await query(
    `
      SELECT
        COUNT(*) AS total_chargebacks,
        COALESCE(SUM(chargeback_amount), 0) AS chargeback_amount
      FROM order_chargebacks
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
  fraudWhere += buildDateFilter("created_at", startDate, endDate, fraudParams);
  const fraudRows = await query(
    `
      SELECT COUNT(*) AS fraud_cases
      FROM order_fraud_cases
      ${fraudWhere}
    `,
    fraudParams,
  );

  return {
    totalTransactionOrders: toNumber(order.total_transaction_orders),
    successfulPayments: toNumber(order.successful_payments),
    failedPayments: toNumber(order.failed_payments),
    gmv: toNumber(order.gmv),
    totalRefunds: toNumber(refundRows[0].total_refunds),
    refundAmount: toNumber(refundRows[0].refund_amount),
    totalChargebacks: toNumber(chargebackRows[0].total_chargebacks),
    chargebackAmount: toNumber(chargebackRows[0].chargeback_amount),
    totalFraudCases: toNumber(fraudRows[0].fraud_cases),
  };
}

function buildDashboardSummary(kpi) {
  const successRate = toPercentage(kpi.successfulPayments, kpi.totalTransactionOrders);
  const refundRate = toPercentage(kpi.totalRefunds, kpi.successfulPayments);
  const chargebackRate = toPercentage(kpi.totalChargebacks, kpi.successfulPayments);
  const fraudRate = toPercentage(kpi.totalFraudCases, kpi.totalTransactionOrders);
  const healthScore = calculateHealthScore({
    successRate,
    refundRate,
    chargebackRate,
    fraudRate,
  });

  return {
    ...kpi,
    successRate,
    refundRate,
    chargebackRate,
    fraudRate,
    healthScore,
    healthLevel: classifyHealth(healthScore),
  };
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

async function createTransactionOrder(req, res) {
  const {
    merchantId,
    orderNo,
    merchantName = null,
    cardNumberFirst6Last4,
    channelName,
    orderAmount,
    orderCurrency = "CNY",
    payerEmail,
    payerName,
    paymentStatus = "pending",
    paidAt = null,
  } = req.body;

  if (
    !merchantId ||
    !orderNo ||
    !cardNumberFirst6Last4 ||
    !channelName ||
    orderAmount === undefined ||
    !orderCurrency ||
    !payerEmail ||
    !payerName
  ) {
    return res.status(400).json({
      error:
        "merchantId, orderNo, cardNumberFirst6Last4, channelName, orderAmount, orderCurrency, payerEmail, payerName are required.",
    });
  }

  const normalizedCard = normalizeCardFirst6Last4(cardNumberFirst6Last4);
  if (!normalizedCard) {
    return res.status(400).json({
      error:
        "cardNumberFirst6Last4 must be 10 digits or masked in first6+last4 format.",
    });
  }

  try {
    const merchant = await getMerchantById(merchantId);
    if (!merchant) {
      return res.status(400).json({ error: "merchantId does not exist." });
    }

    const storedMerchantName = merchantName || merchant.name;
    const result = await query(
      `
        INSERT INTO transaction_orders
          (merchant_id, order_no, merchant_name, card_number_first6_last4, channel_name, order_amount, order_currency, payer_email, payer_name, payment_status, paid_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        merchantId,
        orderNo,
        storedMerchantName,
        normalizedCard,
        channelName,
        orderAmount,
        orderCurrency,
        payerEmail,
        payerName,
        paymentStatus,
        toSqlDate(paidAt),
      ],
    );

    return res.status(201).json({
      id: result.insertId,
      merchantId,
      orderNo,
      merchantName: storedMerchantName,
      paymentStatus,
    });
  } catch (error) {
    if (error && error.code === "ER_DUP_ENTRY") {
      return res.status(409).json({ error: "orderNo already exists." });
    }
    if (error && error.code === "ER_TRUNCATED_WRONG_VALUE_FOR_FIELD") {
      return res.status(400).json({ error: "Invalid paymentStatus." });
    }
    return res.status(500).json({ error: "Failed to create transaction order." });
  }
}

app.post("/api/transaction-orders", createTransactionOrder);
app.post("/api/orders", createTransactionOrder);

app.get("/api/transaction-orders", async (_req, res) => {
  try {
    const rows = await query(
      `
        SELECT
          id,
          merchant_id,
          order_no,
          merchant_name,
          card_number_first6_last4,
          channel_name,
          order_amount,
          order_currency,
          payer_email,
          payer_name,
          payment_status,
          created_at,
          paid_at
        FROM transaction_orders
        ORDER BY id DESC
      `,
    );
    return res.json(rows);
  } catch (error) {
    return res.status(500).json({ error: "Failed to fetch transaction orders." });
  }
});

app.post("/api/refunds", async (req, res) => {
  const {
    merchantId,
    refundNo,
    originalOrderNo,
    refundCurrency = "CNY",
    refundAmount,
    refundStatus = "submitted",
  } = req.body;

  if (!merchantId || !refundNo || !originalOrderNo || refundAmount === undefined) {
    return res.status(400).json({
      error:
        "merchantId, refundNo, originalOrderNo, refundAmount are required.",
    });
  }

  try {
    const order = await getTransactionOrderByNo(merchantId, originalOrderNo);
    if (!order) {
      return res
        .status(400)
        .json({ error: "originalOrderNo does not belong to merchantId." });
    }

    const result = await query(
      `
        INSERT INTO order_refunds
          (merchant_id, refund_no, original_order_no, refund_currency, refund_amount, refund_status)
        VALUES (?, ?, ?, ?, ?, ?)
      `,
      [
        merchantId,
        refundNo,
        originalOrderNo,
        refundCurrency,
        refundAmount,
        refundStatus,
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
      return res.status(400).json({ error: "Invalid refundStatus." });
    }
    return res.status(500).json({ error: "Failed to create refund." });
  }
});

app.post("/api/chargebacks", async (req, res) => {
  const {
    merchantId,
    chargebackNo,
    originalOrderNo,
    chargebackAmount,
    chargebackStatus = "open",
    chargebackReason,
  } = req.body;

  if (
    !merchantId ||
    !chargebackNo ||
    !originalOrderNo ||
    chargebackAmount === undefined ||
    !chargebackReason
  ) {
    return res.status(400).json({
      error:
        "merchantId, chargebackNo, originalOrderNo, chargebackAmount, chargebackReason are required.",
    });
  }

  try {
    const order = await getTransactionOrderByNo(merchantId, originalOrderNo);
    if (!order) {
      return res
        .status(400)
        .json({ error: "originalOrderNo does not belong to merchantId." });
    }

    const result = await query(
      `
        INSERT INTO order_chargebacks
          (merchant_id, chargeback_no, original_order_no, chargeback_amount, chargeback_status, chargeback_reason)
        VALUES (?, ?, ?, ?, ?, ?)
      `,
      [
        merchantId,
        chargebackNo,
        originalOrderNo,
        chargebackAmount,
        chargebackStatus,
        chargebackReason,
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
      return res.status(400).json({ error: "Invalid chargebackStatus." });
    }
    return res.status(500).json({ error: "Failed to create chargeback." });
  }
});

app.post("/api/fraud-cases", async (req, res) => {
  const {
    merchantId,
    caseNo,
    originalOrderNo,
    currency = "CNY",
    amount,
    fraudReason,
  } = req.body;

  if (
    !merchantId ||
    !caseNo ||
    !originalOrderNo ||
    amount === undefined ||
    !fraudReason
  ) {
    return res.status(400).json({
      error:
        "merchantId, caseNo, originalOrderNo, currency, amount, fraudReason are required.",
    });
  }

  try {
    const order = await getTransactionOrderByNo(merchantId, originalOrderNo);
    if (!order) {
      return res
        .status(400)
        .json({ error: "originalOrderNo does not belong to merchantId." });
    }

    const result = await query(
      `
        INSERT INTO order_fraud_cases
          (merchant_id, case_no, original_order_no, currency, amount, fraud_reason)
        VALUES (?, ?, ?, ?, ?, ?)
      `,
      [
        merchantId,
        caseNo,
        originalOrderNo,
        currency,
        amount,
        fraudReason,
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
    let transactingWhere = " WHERE payment_status = 'paid'";
    transactingWhere += buildDateFilter(
      "created_at",
      range.startDate,
      range.endDate,
      transactingParams,
    );
    const transactingRows = await query(
      `
        SELECT COUNT(DISTINCT merchant_id) AS transacting_merchants
        FROM transaction_orders
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
