const refs = {
  startDate: document.getElementById("startDate"),
  endDate: document.getElementById("endDate"),
  refreshBtn: document.getElementById("refreshBtn"),
  applyFilterBtn: document.getElementById("applyFilterBtn"),
  metricTotalMerchants: document.getElementById("metricTotalMerchants"),
  metricActiveMerchants: document.getElementById("metricActiveMerchants"),
  metricTransactingMerchants: document.getElementById("metricTransactingMerchants"),
  metricOrders: document.getElementById("metricOrders"),
  metricSuccessRate: document.getElementById("metricSuccessRate"),
  metricGmv: document.getElementById("metricGmv"),
  metricRefundRate: document.getElementById("metricRefundRate"),
  metricChargebackRate: document.getElementById("metricChargebackRate"),
  metricFraudRate: document.getElementById("metricFraudRate"),
  metricHealthScore: document.getElementById("metricHealthScore"),
  metricHealthLevel: document.getElementById("metricHealthLevel"),
  merchantRankingBody: document.getElementById("merchantRankingBody"),
  riskAlertsList: document.getElementById("riskAlertsList"),
  emptyRowTemplate: document.getElementById("emptyRowTemplate"),
  emptyAlertTemplate: document.getElementById("emptyAlertTemplate"),
};

function initDefaultDates() {
  const today = new Date();
  const past = new Date();
  past.setDate(today.getDate() - 30);
  refs.endDate.value = toInputDate(today);
  refs.startDate.value = toInputDate(past);
}

function toInputDate(date) {
  return new Date(date).toISOString().slice(0, 10);
}

function buildQuery() {
  const params = new URLSearchParams();
  if (refs.startDate.value) {
    params.set("startDate", refs.startDate.value);
  }
  if (refs.endDate.value) {
    params.set("endDate", refs.endDate.value);
  }
  return params.toString();
}

async function fetchJson(url) {
  const res = await fetch(url);
  if (!res.ok) {
    const errPayload = await res.json().catch(() => ({}));
    throw new Error(errPayload.error || `Request failed: ${res.status}`);
  }
  return res.json();
}

function formatNumber(value) {
  return Number(value || 0).toLocaleString("en-US");
}

function formatCurrency(value) {
  return Number(value || 0).toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function formatPercent(value) {
  return `${Number(value || 0).toFixed(2)}%`;
}

function toHealthClass(level) {
  if (level === "healthy") {
    return "healthy";
  }
  if (level === "watch") {
    return "watch";
  }
  return "critical";
}

function renderOverview(platformData) {
  const coverage = platformData.merchantCoverage || {};
  const dashboard = platformData.dashboard || {};

  refs.metricTotalMerchants.textContent = formatNumber(coverage.totalMerchants);
  refs.metricActiveMerchants.textContent = formatNumber(coverage.activeMerchants);
  refs.metricTransactingMerchants.textContent = formatNumber(
    coverage.transactingMerchants,
  );
  refs.metricOrders.textContent = formatNumber(dashboard.totalTransactionOrders);
  refs.metricSuccessRate.textContent = formatPercent(dashboard.successRate);
  refs.metricGmv.textContent = formatCurrency(dashboard.gmv);
  refs.metricRefundRate.textContent = formatPercent(dashboard.refundRate);
  refs.metricChargebackRate.textContent = formatPercent(dashboard.chargebackRate);
  refs.metricFraudRate.textContent = formatPercent(dashboard.fraudRate);
  refs.metricHealthScore.textContent = Number(dashboard.healthScore || 0).toFixed(2);
  refs.metricHealthLevel.textContent = dashboard.healthLevel || "-";
  refs.metricHealthLevel.className = `tag ${toHealthClass(dashboard.healthLevel)}`;
}

function renderMerchantRanking(merchantRows) {
  refs.merchantRankingBody.innerHTML = "";

  if (!merchantRows.length) {
    refs.merchantRankingBody.appendChild(
      refs.emptyRowTemplate.content.cloneNode(true),
    );
    return;
  }

  merchantRows.forEach((merchant, index) => {
    const dashboard = merchant.dashboard || {};
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${index + 1}</td>
      <td>${merchant.name}</td>
      <td>${merchant.status}</td>
      <td>${Number(dashboard.healthScore || 0).toFixed(2)} (${dashboard.healthLevel || "-"})</td>
      <td>${formatPercent(dashboard.successRate)}</td>
      <td>${formatPercent(dashboard.refundRate)}</td>
      <td>${formatPercent(dashboard.chargebackRate)}</td>
      <td>${formatPercent(dashboard.fraudRate)}</td>
      <td>${formatCurrency(dashboard.gmv)}</td>
    `;
    refs.merchantRankingBody.appendChild(tr);
  });
}

function buildRiskAlerts(merchantRows) {
  return merchantRows
    .map((merchant) => {
      const d = merchant.dashboard || {};
      const reasons = [];

      if ((d.healthScore || 0) < 70) {
        reasons.push(`健康分过低 (${Number(d.healthScore || 0).toFixed(2)})`);
      }
      if ((d.chargebackRate || 0) >= 1.5) {
        reasons.push(`拒付率偏高 (${formatPercent(d.chargebackRate)})`);
      }
      if ((d.fraudRate || 0) >= 1) {
        reasons.push(`欺诈率偏高 (${formatPercent(d.fraudRate)})`);
      }
      if ((d.refundRate || 0) >= 8) {
        reasons.push(`退款率偏高 (${formatPercent(d.refundRate)})`);
      }
      if ((d.successRate || 0) < 80) {
        reasons.push(`支付成功率偏低 (${formatPercent(d.successRate)})`);
      }

      if (!reasons.length) {
        return null;
      }

      return {
        name: merchant.name,
        merchantCode: merchant.merchant_code,
        level: d.healthLevel,
        reasons,
      };
    })
    .filter(Boolean)
    .sort((a, b) => b.reasons.length - a.reasons.length);
}

function renderRiskAlerts(alerts) {
  refs.riskAlertsList.innerHTML = "";

  if (!alerts.length) {
    refs.riskAlertsList.appendChild(
      refs.emptyAlertTemplate.content.cloneNode(true),
    );
    return;
  }

  alerts.forEach((alert) => {
    const li = document.createElement("li");
    li.className = "alert-item";
    li.innerHTML = `
      <p class="alert-title">${alert.name} (${alert.merchantCode})</p>
      <p class="alert-meta">等级：${alert.level || "unknown"} | 触发：${alert.reasons.join(" / ")}</p>
    `;
    refs.riskAlertsList.appendChild(li);
  });
}

function sortMerchantsForRanking(merchantRows) {
  return [...merchantRows].sort((a, b) => {
    const aScore = Number(a.dashboard?.healthScore || 0);
    const bScore = Number(b.dashboard?.healthScore || 0);
    if (aScore !== bScore) {
      return aScore - bScore;
    }
    const aFraud = Number(a.dashboard?.fraudRate || 0);
    const bFraud = Number(b.dashboard?.fraudRate || 0);
    return bFraud - aFraud;
  });
}

async function loadDashboard() {
  const query = buildQuery();
  const suffix = query ? `?${query}` : "";

  try {
    refs.refreshBtn.disabled = true;
    refs.applyFilterBtn.disabled = true;

    const [platformData, merchantsData] = await Promise.all([
      fetchJson(`/api/dashboard/platform${suffix}`),
      fetchJson(`/api/dashboard/merchants${suffix}`),
    ]);

    renderOverview(platformData);

    const merchantRows = merchantsData.merchants || [];
    const sortedMerchants = sortMerchantsForRanking(merchantRows);
    renderMerchantRanking(sortedMerchants);
    renderRiskAlerts(buildRiskAlerts(sortedMerchants));
  } catch (error) {
    alert(`加载失败: ${error.message}`);
  } finally {
    refs.refreshBtn.disabled = false;
    refs.applyFilterBtn.disabled = false;
  }
}

refs.refreshBtn.addEventListener("click", loadDashboard);
refs.applyFilterBtn.addEventListener("click", loadDashboard);

initDefaultDates();
loadDashboard();
