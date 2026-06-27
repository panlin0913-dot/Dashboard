let merchants = [];
const AUTH_KEY = "pay_monitor_auth";
let currentScope = "platform";
let detailState = {
  type: "",
  period: "",
  page: 1,
  totalPages: 1,
};

function fallbackMccFromMerchantId(merchantId) {
  const n = Number(String(merchantId || "").replace("M", ""));
  if (!Number.isFinite(n) || n <= 0) return "-";
  const mod = (n - 1) % 3;
  if (mod === 0) return "5816";
  if (mod === 1) return "5817";
  return "5399";
}

function normalizeMerchant(raw) {
  const merchantId = raw.merchant_id || raw.merchantId || "";
  const merchantName = raw.merchant_name || raw.merchantName || "";
  const mcc = raw.mcc || raw.MCC || raw.merchant_mcc || fallbackMccFromMerchantId(merchantId);
  return {
    merchant_id: merchantId,
    merchant_name: merchantName,
    mcc,
  };
}

function ensureAuthenticated() {
  const auth = sessionStorage.getItem(AUTH_KEY);
  if (!auth) {
    window.location.href = "/";
    return false;
  }
  return true;
}

function formatInt(value) {
  return new Intl.NumberFormat("zh-CN").format(value);
}

function formatCurrency(value) {
  return new Intl.NumberFormat("zh-CN", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0,
  }).format(value);
}

function formatCurrencyDetail(value) {
  return new Intl.NumberFormat("zh-CN", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(value);
}

function formatRate(value) {
  return `${(value * 100).toFixed(2)}%`;
}

function readRowMetric(row, camelKey, snakeKey, fallback = 0) {
  const value = row?.[camelKey] ?? row?.[snakeKey];
  const num = Number(value);
  return Number.isFinite(num) ? num : fallback;
}

function buildSummary(rows) {
  const totals = rows.reduce(
    (acc, item) => {
      const txCount = Number(item.txCount ?? item.tx_count ?? 0);
      const volume = Number(item.volume ?? item.tx_success_amount ?? 0);
      const refundRate = Number(item.refundRate ?? item.refund_rate ?? 0);
      const chargebackRate = Number(item.chargebackRate ?? item.chargeback_rate ?? 0);
      const fraudRate = Number(item.fraudRate ?? item.fraud_rate ?? 0);

      const refundCountRaw = item.refundCount ?? item.refund_count;
      const chargebackCountRaw = item.chargebackCount ?? item.chargeback_count;
      const fraudCountRaw = item.fraudCount ?? item.fraud_count;

      // Fallback to rate-based estimate if count field is missing in payload.
      const refundCount = Number(
        refundCountRaw !== undefined ? refundCountRaw : Math.round(txCount * refundRate)
      );
      const chargebackCount = Number(
        chargebackCountRaw !== undefined ? chargebackCountRaw : Math.round(txCount * chargebackRate)
      );
      const fraudCount = Number(
        fraudCountRaw !== undefined ? fraudCountRaw : Math.round(txCount * fraudRate)
      );

      acc.txCount += txCount;
      acc.volume += volume;
      acc.refundCount += refundCount;
      acc.chargebackCount += chargebackCount;
      acc.fraudCount += fraudCount;
      acc.refund += refundRate;
      acc.chargeback += chargebackRate;
      acc.fraud += fraudRate;
      return acc;
    },
    {
      txCount: 0,
      volume: 0,
      refundCount: 0,
      chargebackCount: 0,
      fraudCount: 0,
      refund: 0,
      chargeback: 0,
      fraud: 0,
    }
  );

  const n = rows.length || 1;
  return {
    txCount: totals.txCount,
    volume: totals.volume,
    refundCount: totals.refundCount,
    chargebackCount: totals.chargebackCount,
    fraudCount: totals.fraudCount,
    refundRate: totals.refund / n,
    chargebackRate: totals.chargeback / n,
    fraudRate: totals.fraud / n,
  };
}

function renderCards(targetId, summary) {
  const container = document.getElementById(targetId);
  container.innerHTML = `
    <article class="metric-card">
      <p class="metric-title">交易笔数</p>
      <div class="metric-risk-line">
        <button class="metric-count-btn transaction" data-detail-type="transaction" type="button">交易笔数${formatInt(summary.txCount)}</button>
      </div>
    </article>
    <article class="metric-card">
      <p class="metric-title">交易量</p>
      <p class="metric-value">${formatCurrency(summary.volume)}</p>
    </article>
    <article class="metric-card">
      <p class="metric-title">退款率</p>
      <div class="metric-risk-line">
        <button class="metric-count-btn refund" data-detail-type="refund" type="button">退款笔数${formatInt(summary.refundCount)}</button>
        <span class="metric-risk-rate refund">(${formatRate(summary.refundRate)})</span>
      </div>
    </article>
    <article class="metric-card">
      <p class="metric-title">拒付率</p>
      <div class="metric-risk-line">
        <button class="metric-count-btn chargeback" data-detail-type="chargeback" type="button">拒付笔数${formatInt(summary.chargebackCount)}</button>
        <span class="metric-risk-rate chargeback">(${formatRate(summary.chargebackRate)})</span>
      </div>
    </article>
    <article class="metric-card">
      <p class="metric-title">欺诈率</p>
      <div class="metric-risk-line">
        <button class="metric-count-btn fraud" data-detail-type="fraud" type="button">欺诈笔数${formatInt(summary.fraudCount)}</button>
        <span class="metric-risk-rate fraud">(${formatRate(summary.fraudRate)})</span>
      </div>
    </article>
  `;

  container.querySelectorAll(".metric-count-btn").forEach((btn) => {
    btn.addEventListener("click", async () => {
      try {
        await loadDetails(btn.dataset.detailType, "");
      } catch (err) {
        setStatus(`明细加载失败：${err.message}`, "error");
      }
    });
  });
}

function renderTable(targetId, rows) {
  const tbody = document.getElementById(targetId);
  tbody.innerHTML = rows
    .map(
      (r) => `
        <tr>
          <td>${r.period}</td>
          <td><button class="metric-count-btn transaction" data-detail-type="transaction" data-period="${r.period}" type="button">${formatInt(readRowMetric(r, "txCount", "tx_count"))}</button></td>
          <td>${formatCurrency(readRowMetric(r, "volume", "tx_success_amount"))}</td>
          <td>${formatCurrency(readRowMetric(r, "refundAmount", "refund_amount"))}</td>
          <td><button class="metric-count-btn refund" data-detail-type="refund" data-period="${r.period}" type="button">${formatInt(readRowMetric(r, "refundCount", "refund_count"))}</button></td>
          <td>${formatRate(readRowMetric(r, "refundRate", "refund_rate"))}</td>
          <td>${formatCurrency(readRowMetric(r, "chargebackAmount", "chargeback_amount"))}</td>
          <td><button class="metric-count-btn chargeback" data-detail-type="chargeback" data-period="${r.period}" type="button">${formatInt(readRowMetric(r, "chargebackCount", "chargeback_count"))}</button></td>
          <td>${formatRate(readRowMetric(r, "chargebackRate", "chargeback_rate"))}</td>
          <td>${formatCurrency(readRowMetric(r, "fraudAmount", "fraud_amount"))}</td>
          <td><button class="metric-count-btn fraud" data-detail-type="fraud" data-period="${r.period}" type="button">${formatInt(readRowMetric(r, "fraudCount", "fraud_count"))}</button></td>
          <td>${formatRate(readRowMetric(r, "fraudRate", "fraud_rate"))}</td>
        </tr>
      `
    )
    .join("");

  tbody.querySelectorAll(".metric-count-btn").forEach((btn) => {
    btn.addEventListener("click", async () => {
      try {
        await loadDetails(btn.dataset.detailType, btn.dataset.period || "");
      } catch (err) {
        setStatus(`明细加载失败：${err.message}`, "error");
      }
    });
  });
}

function renderMerchantSelect() {
  const merchantSelect = document.getElementById("merchantSelect");
  merchantSelect.innerHTML = merchants.length
    ? merchants
        .map((m) => `<option value="${m.merchant_id}">${m.merchant_id} - ${m.merchant_name} (MCC ${m.mcc})</option>`)
        .join("")
    : `<option value="">暂无商户</option>`;
}

function setMerchantMeta(merchantId, merchantName, mcc, isBadMerchant = false) {
  const meta = document.getElementById("merchantMeta");
  if (!meta) return;
  if (!merchantId) {
    meta.textContent = "";
    return;
  }
  const baseText = `当前商户：${merchantId} - ${merchantName || ""} | MCC：${mcc || "-"}`;
  if (isBadMerchant) {
    meta.innerHTML = `${baseText}<span class="merchant-warning">高危预警</span>`;
  } else {
    meta.textContent = baseText;
  }
}

function setStatus(message, type = "") {
  const el = document.getElementById("statusBar");
  el.textContent = message;
  el.className = `status-bar${type ? ` ${type}` : ""}`;
}

function closeDetailPanel() {
  const panel = document.getElementById("detailPanel");
  const body = document.getElementById("detailTableBody");
  if (panel) panel.classList.add("hidden");
  if (body) body.innerHTML = "";
  const pageInfo = document.getElementById("detailPageInfo");
  if (pageInfo) pageInfo.textContent = "第 1 / 1 页";
  detailState = { type: "", period: "", page: 1, totalPages: 1 };
}

function openDetailPanel(title, rows, page, totalPages) {
  const panel = document.getElementById("detailPanel");
  const titleEl = document.getElementById("detailTitle");
  const body = document.getElementById("detailTableBody");
  const pageInfo = document.getElementById("detailPageInfo");
  const prevBtn = document.getElementById("detailPrevBtn");
  const nextBtn = document.getElementById("detailNextBtn");
  if (!panel || !titleEl || !body) return;

  titleEl.textContent = title;
  body.innerHTML = rows.length
    ? rows
        .map(
          (r) => `
            <tr>
              <td>${r.merchant_id || ""}</td>
              <td>${r.order_id || ""}</td>
              <td>${r.mcc || ""}</td>
              <td>${r.currency || ""}</td>
              <td>${formatCurrencyDetail(Number(r.amount || 0))}</td>
              <td>${r.detail_status || ""}</td>
              <td>${r.event_time || ""}</td>
            </tr>
          `
        )
        .join("")
    : `<tr><td colspan="7">暂无明细</td></tr>`;

  panel.classList.remove("hidden");
  if (pageInfo) pageInfo.textContent = `第 ${page} / ${totalPages} 页`;
  if (prevBtn) prevBtn.disabled = page <= 1;
  if (nextBtn) nextBtn.disabled = page >= totalPages;
}

async function loadDetails(detailType, period = "", page = 1) {
  const merchantId = document.getElementById("merchantSelect").value;
  const scope = currentScope;
  const params = new URLSearchParams({
    type: detailType,
    scope,
    page: String(page),
    page_size: "50",
  });
  if (period) {
    params.set("period", period);
  }
  if (scope === "merchant" && merchantId) {
    params.set("merchant_id", merchantId);
  }

  setStatus(`正在加载${detailType}明细...`);
  const data = await fetchJson(`/api/details?${params.toString()}`);
  const cnType =
    detailType === "transaction"
      ? "交易"
      : detailType === "refund"
      ? "退款"
      : detailType === "chargeback"
      ? "拒付"
      : "欺诈";
  const title =
    scope === "merchant"
      ? `商户${cnType}明细（${merchantId}${period ? ` / ${period}` : ""}）`
      : `平台${cnType}明细${period ? `（${period}）` : ""}`;
  const totalPages = Number(data.total_pages || 1);
  const currentPage = Number(data.page || page);
  detailState = {
    type: detailType,
    period,
    page: currentPage,
    totalPages,
  };
  openDetailPanel(title, data.rows || [], currentPage, totalPages);
  setStatus(`${cnType}明细加载成功（第 ${currentPage}/${totalPages} 页）`, "success");
}

async function fetchJson(url) {
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}`);
  }
  return res.json();
}

async function renderPlatform() {
  currentScope = "platform";
  closeDetailPanel();
  setStatus("正在读取平台数据...");
  const data = await fetchJson("/api/platform");
  const rows = data.rows || [];
  renderCards("platformCards", buildSummary(rows));
  renderTable("platformTableBody", rows);
  setStatus(`平台数据读取成功（${rows.length} 条）`, "success");
}

async function renderMerchant() {
  currentScope = "merchant";
  closeDetailPanel();
  const merchantId = document.getElementById("merchantSelect").value;
  if (!merchantId) {
    renderCards("merchantCards", buildSummary([]));
    renderTable("merchantTableBody", []);
    setMerchantMeta("", "", "", false);
    return;
  }
  setStatus(`正在读取商户 ${merchantId} 数据...`);
  const data = await fetchJson(
    `/api/merchant?merchant_id=${encodeURIComponent(merchantId)}`
  );
  const rows = data.rows || [];
  const avg = rows.reduce(
    (acc, row) => {
      acc.refund += Number(row.refundRate || 0);
      acc.chargeback += Number(row.chargebackRate || 0);
      acc.fraud += Number(row.fraudRate || 0);
      return acc;
    },
    { refund: 0, chargeback: 0, fraud: 0 }
  );
  const n = rows.length || 1;
  const isBadMerchant = avg.refund / n >= 0.08 || avg.chargeback / n >= 0.015 || avg.fraud / n >= 0.03;
  renderCards("merchantCards", buildSummary(rows));
  renderTable("merchantTableBody", rows);
  setMerchantMeta(data.merchant_id, data.merchant_name, data.mcc, isBadMerchant);
  setStatus(`商户 ${merchantId} 数据读取成功（${rows.length} 条）`, "success");
}

async function setTab(tab) {
  const platformTab = document.getElementById("platformTab");
  const merchantTab = document.getElementById("merchantTab");
  const merchantFilterWrap = document.getElementById("merchantFilterWrap");
  const menuItems = document.querySelectorAll(".menu-item");

  menuItems.forEach((item) => {
    item.classList.toggle("active", item.dataset.tab === tab);
  });

  if (tab === "platform") {
    platformTab.classList.add("active");
    merchantTab.classList.remove("active");
    merchantFilterWrap.classList.add("hidden");
    await renderPlatform();
  } else {
    merchantTab.classList.add("active");
    platformTab.classList.remove("active");
    merchantFilterWrap.classList.remove("hidden");
    await renderMerchant();
  }
}

function bindEvents() {
  document.querySelectorAll(".menu-item").forEach((item) => {
    item.addEventListener("click", async () => {
      try {
        await setTab(item.dataset.tab);
      } catch (err) {
        setStatus(`加载失败：${err.message}`, "error");
      }
    });
  });

  document.getElementById("merchantSelect").addEventListener("change", async () => {
    try {
      await renderMerchant();
    } catch (err) {
      setStatus(`加载失败：${err.message}`, "error");
    }
  });

  const logoutBtn = document.getElementById("logoutBtn");
  if (logoutBtn) {
    logoutBtn.addEventListener("click", () => {
      sessionStorage.removeItem(AUTH_KEY);
      window.location.href = "/";
    });
  }

  const closeBtn = document.getElementById("detailCloseBtn");
  if (closeBtn) {
    closeBtn.addEventListener("click", closeDetailPanel);
  }

  const prevBtn = document.getElementById("detailPrevBtn");
  const nextBtn = document.getElementById("detailNextBtn");
  if (prevBtn) {
    prevBtn.addEventListener("click", async () => {
      if (!detailState.type || detailState.page <= 1) return;
      try {
        await loadDetails(detailState.type, detailState.period, detailState.page - 1);
      } catch (err) {
        setStatus(`明细翻页失败：${err.message}`, "error");
      }
    });
  }
  if (nextBtn) {
    nextBtn.addEventListener("click", async () => {
      if (!detailState.type || detailState.page >= detailState.totalPages) return;
      try {
        await loadDetails(detailState.type, detailState.period, detailState.page + 1);
      } catch (err) {
        setStatus(`明细翻页失败：${err.message}`, "error");
      }
    });
  }
}

async function loadMerchants() {
  setStatus("正在读取商户列表...");
  const data = await fetchJson("/api/merchants");
  merchants = (data.rows || []).map(normalizeMerchant);
  renderMerchantSelect();
}

async function init() {
  if (!ensureAuthenticated()) {
    return;
  }
  try {
    await loadMerchants();
  } catch (err) {
    setStatus(`商户列表加载失败：${err.message}`, "error");
    renderMerchantSelect();
  }
  bindEvents();
  try {
    await setTab("platform");
  } catch (err) {
    setStatus(`初始化失败：${err.message}`, "error");
  }
}

init();
