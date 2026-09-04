const $ = (id) => document.getElementById(id);
const $$ = (sel) => Array.from(document.querySelectorAll(sel));
const RING_CIRCUMFERENCE = 2 * Math.PI * 52;
const UNITS = ["B", "KB", "MB", "GB", "TB", "PB"];

function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (ch) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[ch]));
}

function formatBytes(value) {
  let n = Number(value || 0);
  if (!Number.isFinite(n)) return "—";
  const sign = n < 0 ? "-" : "";
  n = Math.abs(n);
  if (n < 1024) return `${sign}${n} B`;
  let unit = 0;
  while (n >= 1024 && unit < UNITS.length - 1) { n /= 1024; unit += 1; }
  return `${sign}${n.toFixed(n >= 10 ? 1 : 2)} ${UNITS[unit]}`;
}

function formatSpeed(value) { return `${formatBytes(value)}/s`; }
function pad(value) { return String(value).padStart(2, "0"); }

function formatTime(ts, withTime = true) {
  if (!ts) return "—";
  const date = new Date(ts < 1e12 ? ts * 1000 : ts);
  if (Number.isNaN(date.getTime())) return "—";
  const day = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  return withTime ? `${date.getMonth() + 1}/${date.getDate()} ${pad(date.getHours())}:${pad(date.getMinutes())}` : day;
}

function relative(ts) {
  if (!ts) return "从未";
  const delta = Date.now() - (ts < 1e12 ? ts * 1000 : ts);
  if (delta < 0) return formatTime(ts);
  const minutes = Math.floor(delta / 60000);
  if (minutes < 1) return "刚刚";
  if (minutes < 60) return `${minutes} 分钟前`;
  const hours = Math.floor(minutes / 60);
  if (hours < 48) return `${hours} 小时前`;
  return `${Math.floor(hours / 24)} 天前`;
}

function daysLeft(resetAt) {
  if (!resetAt) return "—";
  const ms = resetAt < 1e12 ? resetAt * 1000 : resetAt;
  return `${Math.max(0, (ms - Date.now()) / 86400000).toFixed(1)} 天`;
}

function cssToken(name, fallback) {
  const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return value || fallback;
}

function chartColors() {
  return {
    in: cssToken("--teal", "#19705e"),
    out: cssToken("--blue", "#356ae6"),
    grid: cssToken("--line", "#dce2e8"),
    text: cssToken("--text-3", "#66707d"),
    surface: cssToken("--surface", "#ffffff"),
    textStrong: cssToken("--text", "#20242b"),
  };
}

function setRing(pct, ids = ["ringArc", "ovrArc"]) {
  const p = Math.max(0, Math.min(100, Number(pct) || 0));
  const dash = `${(p / 100) * RING_CIRCUMFERENCE} ${RING_CIRCUMFERENCE}`;
  for (const id of ids) {
    const circle = $(id);
    if (!circle) continue;
    circle.setAttribute("stroke-dasharray", dash);
    circle.setAttribute("stroke", p >= 90 ? cssToken("--red", "#b4232f") : p >= 75 ? cssToken("--amber", "#a86700") : cssToken("--blue", "#356ae6"));
  }
}

let toastTimer = null;
function showToast(message, type = "info") {
  const el = $("toast");
  if (!el) return;
  clearTimeout(toastTimer);
  el.textContent = message;
  el.className = `toast show ${type}`;
  toastTimer = setTimeout(() => { el.className = "toast"; }, 2400);
}

async function copyText(text, label = "内容") {
  try {
    if (navigator.clipboard && window.isSecureContext) await navigator.clipboard.writeText(text);
    else {
      const area = document.createElement("textarea");
      area.value = text;
      area.style.position = "fixed";
      area.style.opacity = "0";
      document.body.appendChild(area);
      area.select();
      document.execCommand("copy");
      area.remove();
    }
    showToast(`已复制${label}`, "ok");
  } catch (error) {
    showToast("复制失败", "bad");
  }
}

let chartRange = localStorage.getItem("wagongChartRange") || "24h";
let chartModel = null;
let chartHover = -1;
let snapshot = null;

function chartDataFor(range) {
  const points = snapshot?.bwhHistory || [];
  const now = Date.now() / 1000;
  const days = range === "7d" ? 7 : range === "30d" ? 30 : range === "24h" ? 1 : 400;
  const filtered = points.filter((point) => point.t >= now - days * 86400);
  const byBucket = new Map();
  for (const point of filtered) {
    const date = new Date(point.t * 1000);
    const hourly = range === "24h";
    const key = hourly
      ? `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}-${date.getHours()}`
      : `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
    if (!byBucket.has(key)) {
      const bucket = hourly
        ? new Date(date.getFullYear(), date.getMonth(), date.getDate(), date.getHours())
        : new Date(date.getFullYear(), date.getMonth(), date.getDate());
      byBucket.set(key, { t: bucket.getTime() / 1000, in: 0, out: 0 });
    }
    const item = byBucket.get(key);
    item.in += Number(point.in || 0);
    item.out += Number(point.out || 0);
  }
  const rows = [...byBucket.values()].sort((a, b) => a.t - b.t);
  return { mode: range === "24h" ? "line" : rows.length < 2 ? "bar" : "line", rows };
}

function updateChartMeta(model) {
  const el = $("chartMeta");
  if (!el) return;
  if (!model.rows.length) {
    el.innerHTML = '<span class="chiplet hintc">暂无历史流量记录</span>';
    return;
  }
  const sumIn = model.rows.reduce((sum, row) => sum + row.in, 0);
  const sumOut = model.rows.reduce((sum, row) => sum + row.out, 0);
  const peak = model.rows.reduce((a, b) => (a.in + a.out > b.in + b.out ? a : b));
  el.innerHTML = `
    <span class="chiplet"><i class="dotc in"></i>合计 ↑ ${formatBytes(sumIn)} · ↓ ${formatBytes(sumOut)}</span>
    <span class="chiplet">峰值 ${formatTime(peak.t)} · ${formatBytes(peak.in + peak.out)}</span>`;
}

function barTop(ctx, x, yTop, width, height, radius) {
  const r = Math.min(radius, width / 2, Math.max(0, height));
  ctx.beginPath();
  ctx.moveTo(x, yTop + height);
  ctx.lineTo(x, yTop + r);
  ctx.arcTo(x, yTop, x + r, yTop, r);
  ctx.arcTo(x + width, yTop, x + width, yTop + r, r);
  ctx.lineTo(x + width, yTop + height);
  ctx.closePath();
}

function drawChart() {
  const canvas = $("netChart");
  if (!canvas || !canvas.parentElement) return;
  const ctx = canvas.getContext("2d");
  const colors = chartColors();
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.parentElement.getBoundingClientRect();
  const width = Math.max(1, rect.width);
  const height = Math.max(1, rect.height);
  canvas.width = Math.floor(width * dpr);
  canvas.height = Math.floor(height * dpr);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, width, height);
  const rows = chartModel?.rows || [];
  let tip = canvas.parentElement.querySelector(".chart-tip");
  if (rows.length < 2 || width < 120) {
    if (tip) tip.style.opacity = "0";
    ctx.fillStyle = colors.text;
    ctx.font = "12px -apple-system, PingFang SC, sans-serif";
    ctx.textAlign = "left";
    ctx.fillText(rows.length ? "历史点不足，继续采集后显示趋势" : "暂无历史数据", 14, height / 2);
    canvas._model = chartModel;
    canvas._geom = null;
    return;
  }
  const pad = { l: 58, r: 18, t: 18, b: 30 };
  const max = Math.max(...rows.map((row) => row.in + row.out), 1);
  const nice = 10 ** Math.floor(Math.log10(max));
  const chartMax = [1, 2, 5, 10].find((m) => max <= m * nice) * nice;
  const plotW = width - pad.l - pad.r;
  const plotH = height - pad.t - pad.b;
  const x = (index) => pad.l + plotW * index / (rows.length - 1);
  const y = (value) => pad.t + (1 - value / chartMax) * plotH;

  ctx.font = "10px -apple-system, PingFang SC, sans-serif";
  ctx.textAlign = "right";
  for (let grid = 0; grid <= 4; grid += 1) {
    const value = chartMax * grid / 4;
    const yy = y(value);
    ctx.strokeStyle = colors.grid;
    ctx.globalAlpha = .65;
    ctx.beginPath(); ctx.moveTo(pad.l, yy); ctx.lineTo(width - pad.r, yy); ctx.stroke();
    ctx.globalAlpha = 1;
    ctx.fillStyle = colors.text;
    ctx.fillText(formatBytes(value), pad.l - 8, yy + 3);
  }
  ctx.textAlign = "center";
  const step = Math.max(1, Math.ceil(rows.length / 6));
  rows.forEach((row, index) => {
    if (index % step !== 0 && index !== rows.length - 1) return;
    ctx.fillStyle = colors.text;
    ctx.fillText(formatTime(row.t), x(index), height - 8);
  });

  for (const key of ["out", "in"]) {
    const color = colors[key];
    ctx.beginPath();
    ctx.moveTo(x(0), y(rows[0][key] || 0));
    for (let index = 1; index < rows.length; index += 1) {
      const mid = (x(index - 1) + x(index)) / 2;
      ctx.bezierCurveTo(mid, y(rows[index - 1][key] || 0), mid, y(rows[index][key] || 0), x(index), y(rows[index][key] || 0));
    }
    ctx.lineTo(x(rows.length - 1), y(0)); ctx.lineTo(x(0), y(0)); ctx.closePath();
    ctx.fillStyle = color; ctx.globalAlpha = .1; ctx.fill(); ctx.globalAlpha = 1;
    ctx.beginPath();
    ctx.moveTo(x(0), y(rows[0][key] || 0));
    for (let index = 1; index < rows.length; index += 1) {
      const mid = (x(index - 1) + x(index)) / 2;
      ctx.bezierCurveTo(mid, y(rows[index - 1][key] || 0), mid, y(rows[index][key] || 0), x(index), y(rows[index][key] || 0));
    }
    ctx.strokeStyle = color; ctx.lineWidth = 2; ctx.lineJoin = "round"; ctx.lineCap = "round"; ctx.stroke();
  }

  if (chartHover >= 0 && chartHover < rows.length) {
    const row = rows[chartHover];
    const hx = x(chartHover);
    ctx.save(); ctx.strokeStyle = colors.grid; ctx.setLineDash([4, 4]); ctx.beginPath(); ctx.moveTo(hx, pad.t); ctx.lineTo(hx, height - pad.b); ctx.stroke(); ctx.restore();
    for (const key of ["in", "out"]) {
      ctx.beginPath(); ctx.arc(hx, y(row[key] || 0), 4, 0, Math.PI * 2); ctx.fillStyle = colors[key]; ctx.fill();
      ctx.strokeStyle = colors.surface; ctx.lineWidth = 2; ctx.stroke();
    }
    if (!tip) { tip = document.createElement("div"); tip.className = "chart-tip"; canvas.parentElement.appendChild(tip); }
    tip.innerHTML = `<b>${formatTime(row.t)}</b><br><span class="t-up">↑ 入站 ${formatBytes(row.in)}</span><br><span class="t-down">↓ 出站 ${formatBytes(row.out)}</span><br><span class="t-tot">合计 ${formatBytes(row.in + row.out)}</span>`;
    tip.style.opacity = "1";
    tip.style.transform = "translateY(0)";
    const tipWidth = tip.offsetWidth;
    tip.style.left = `${Math.max(6, Math.min(width - tipWidth - 6, hx + 16 + tipWidth > width ? hx - tipWidth - 16 : hx + 16))}px`;
    tip.style.top = `${Math.max(6, y(row.in + row.out) - 10)}px`;
  } else if (tip) {
    tip.style.opacity = "0";
    tip.style.transform = "translateY(4px)";
  }
  canvas._model = chartModel;
  canvas._geom = { pad, plotW, x };
}

function renderChart() {
  const canvas = $("netChart");
  if (!canvas) return;
  chartModel = chartDataFor(chartRange);
  chartHover = -1;
  updateChartMeta(chartModel);
  drawChart();
}

function updateChartHover(clientX) {
  const canvas = $("netChart");
  const model = canvas?._model;
  const geom = canvas?._geom;
  if (!canvas || !model || !geom || !model.rows.length) return;
  const rect = canvas.getBoundingClientRect();
  const mx = clientX - rect.left;
  if (mx < geom.pad.l || mx > geom.pad.l + geom.plotW) { chartHover = -1; drawChart(); return; }
  chartHover = Math.max(0, Math.min(model.rows.length - 1, Math.round((mx - geom.pad.l) / geom.plotW * (model.rows.length - 1))));
  drawChart();
}

function bindChartEvents() {
  const canvas = $("netChart");
  if (!canvas || canvas.dataset.bound === "1") return;
  canvas.dataset.bound = "1";
  canvas.addEventListener("mousemove", (event) => updateChartHover(event.clientX));
  canvas.addEventListener("mouseleave", () => { chartHover = -1; drawChart(); });
  canvas.addEventListener("touchstart", (event) => { if (event.touches.length) updateChartHover(event.touches[0].clientX); }, { passive: true });
  canvas.addEventListener("touchmove", (event) => { if (event.touches.length) updateChartHover(event.touches[0].clientX); }, { passive: true });
  document.querySelectorAll("#chartRangeSeg button").forEach((button) => {
    button.classList.toggle("active", button.dataset.range === chartRange);
    button.addEventListener("click", () => {
      chartRange = button.dataset.range;
      localStorage.setItem("wagongChartRange", chartRange);
      document.querySelectorAll("#chartRangeSeg button").forEach((item) => item.classList.toggle("active", item === button));
      renderChart();
    });
  });
}

let sortKey = "used";
let sortDir = -1;
let clientFilter = "all";

function clientState(row) {
  const expiry = Number(row.expiryTime || 0);
  const now = Date.now();
  if (!row.enable || (expiry > 0 && expiry < now)) return "off";
  if ((row.percent != null && row.percent >= 80) || (expiry > 0 && expiry - now < 5 * 86400000)) return "warn";
  return row.online ? "online" : "ok";
}

function renderClientSummary(clients) {
  const list = $("clientSummary");
  if (!list) return;
  const sorted = [...clients].sort((a, b) => Number(b.used || 0) - Number(a.used || 0)).slice(0, 3);
  list.innerHTML = sorted.length ? sorted.map((row) => {
    const state = clientState(row);
    const tag = state === "off" ? "停用/到期" : state === "warn" ? "预警" : row.online ? "在线" : "正常";
    const tagClass = state === "off" ? "bad" : state === "warn" ? "warn" : "ok";
    return `<div class="client-summary-row"><div><strong>${esc(row.comment || row.email)}</strong><small>${esc(row.inbound || row.protocol || "节点客户端")}</small></div><div class="usage">${formatBytes(row.used)}<small>${row.percent == null ? "不限额" : `${Number(row.percent).toFixed(1)}% 配额`}</small></div><span class="client-tag ${tagClass}">${tag}</span></div>`;
  }).join("") : '<div class="empty-state compact">暂无客户端数据</div>';
}

function renderResources(server) {
  const list = $("resourceSummary");
  if (!list) return;
  const memPct = server.memTotal ? server.memUsed / server.memTotal * 100 : null;
  const diskPct = server.diskTotal ? server.diskUsed / server.diskTotal * 100 : null;
  const resources = [
    ["CPU", Number(server.cpu || 0), `${Number(server.cpu || 0).toFixed(1)}%`],
    ["内存", memPct, server.memTotal ? `${formatBytes(server.memUsed)} / ${formatBytes(server.memTotal)}` : "—"],
    ["磁盘", diskPct, server.diskTotal ? `${formatBytes(server.diskUsed)} / ${formatBytes(server.diskTotal)}` : "—"],
  ];
  list.innerHTML = resources.map(([label, pct, value]) => `<div class="resource"><label>${label}</label><div class="resource-bar"><i style="width:${Math.max(0, Math.min(100, pct || 0))}%"></i></div><b>${value}</b></div>`).join("") + `<div class="resource"><label>Xray</label><div class="resource-bar"><i style="width:${server.xray === "running" ? 100 : 0}%"></i></div><b>${esc(server.xray || "未连接")}</b></div>`;
}

function deriveAttention(data) {
  const items = [];
  const bwh = data.bwh || {};
  const budget = data.budget || {};
  const xui = data.xui || {};
  const server = xui.server || {};
  (xui.clients || []).forEach((row) => {
    const state = clientState(row);
    if (state === "off") items.push({ tone: "bad", title: `${row.comment || row.email} 已停用或到期`, detail: `${row.inbound || row.protocol || "客户端"} · 可进入客户端页查看`, tab: "clients", filter: "off" });
    else if (state === "warn") items.push({ tone: "warn", title: `${row.comment || row.email} 需要关注`, detail: `${row.percent != null ? `配额已用 ${Number(row.percent).toFixed(1)}%` : "即将到期"} · 查看用量详情`, tab: "clients", filter: "warn" });
  });
  if (server.diskTotal && server.diskUsed / server.diskTotal >= .8) items.push({ tone: "warn", title: "磁盘占用超过 80%", detail: `${formatBytes(server.diskUsed)} / ${formatBytes(server.diskTotal)} · 查看 VPS 资源`, tab: "bwh" });
  if (server.xray && server.xray !== "running") items.push({ tone: "bad", title: "Xray 核心状态异常", detail: server.xrayError || "查看 VPS 资源和面板连接", tab: "bwh" });
  if (budget.status === "urgent" || budget.status === "warning") items.push({ tone: "warn", title: budget.status === "urgent" ? "流量预算紧张" : "流量消耗偏快", detail: `建议日均不超过 ${formatBytes(budget.dailyBudgetBytes)}`, tab: "bwh" });
  if (bwh.error) items.push({ tone: "bad", title: "搬瓦工数据暂时不可用", detail: bwh.error, tab: "bwh" });
  if (xui.error) items.push({ tone: "bad", title: "3X-UI 数据暂时不可用", detail: xui.error, tab: "clients" });
  return items.slice(0, 3);
}

function renderAttention(data) {
  const list = $("attentionList");
  const count = $("attentionCount");
  if (!list) return;
  const items = deriveAttention(data);
  if (count) count.textContent = items.length ? `${items.length} 项` : "无需处理";
  list.innerHTML = items.length ? items.map((item) => `<div class="attention-item"><span class="attention-symbol ${item.tone}">${item.tone === "bad" ? "!" : "·"}</span><div class="attention-copy"><strong>${esc(item.title)}</strong><span>${esc(item.detail)}</span></div><button class="attention-link" type="button" data-go-tab="${item.tab}" data-filter="${item.filter || ""}">查看</button></div>`).join("") : '<div class="empty-state compact">当前没有需要处理的事项。</div>';
}

function renderShellStatus(data) {
  const bwh = data.bwh || {};
  const xui = data.xui || {};
  const errors = [bwh.error, xui.error].filter(Boolean);
  const server = xui.server || {};
  const warning = !errors.length && server.xray && server.xray !== "running";
  const banner = $("healthSummary");
  const title = $("healthTitle");
  const detail = $("healthDetail");
  const symbol = $("healthSymbol");
  if (banner) banner.className = `status-banner ${errors.length ? "is-error" : warning || data.demo ? "is-warning" : ""}`;
  if (symbol) symbol.textContent = errors.length ? "!" : warning || data.demo ? "·" : "✓";
  if (title) title.textContent = errors.length ? "存在异常" : warning ? "需要关注" : data.demo ? "演示数据" : "运行正常";
  if (detail) detail.textContent = errors.length ? "部分数据源没有返回数据，请检查连接或稍后重试" : warning ? "Xray 核心状态需要确认" : data.demo ? "当前使用演示数据，可在设置中连接真实数据源" : "搬瓦工套餐、3X-UI 面板和客户端数据均已连接";
  const left = (bwh.quotaBytes || 0) - (bwh.usedBytes || 0);
  if ($("healthLeft")) $("healthLeft").textContent = bwh.quotaBytes ? formatBytes(left) : "—";
  if ($("healthReset")) $("healthReset").textContent = bwh.resetAt ? daysLeft(bwh.resetAt) : "—";
  if ($("healthOnline")) $("healthOnline").textContent = `${xui.onlineCount || 0} / ${xui.clientCount || 0}`;
  const chip = $("modeChip");
  if (chip) { chip.textContent = data.demo ? "演示数据" : data.ok ? "实时数据" : "部分失败"; chip.className = `status-chip ${data.demo ? "demo" : data.ok ? "ok" : "bad"}`; }
  if ($("stamp")) $("stamp").textContent = data.fetchedAt ? `更新于 ${formatTime(data.fetchedAt)}` : "—";
  const bannerEl = $("banner");
  if (bannerEl) { bannerEl.className = `banner ${data.demo || errors.length ? "show" : ""}`; bannerEl.textContent = data.demo ? "当前为演示数据。打开设置并填入真实凭证后即可开始监控。" : errors.join("  |  "); }
}

function renderOverview(data) {
  const bwh = data.bwh || {};
  const xui = data.xui || {};
  const server = xui.server || {};
  const budget = data.budget || {};
  const pct = Number(bwh.usedPercent || 0);
  if ($("ovrPct")) $("ovrPct").textContent = bwh.quotaBytes ? `${pct.toFixed(1)}%` : "—";
        const budgetPct = Number(budget.usedPercent || 0);
  setRing(budgetPct || pct, ["ovrArc"]);
  const status = $("budgetStatusBadge");
  if (status) { status.className = `section-note ${budget.status === "urgent" ? "status-red" : budget.status === "warning" || budget.status === "moderate" ? "status-amber" : "status-green"}`; status.textContent = budget.hasBudget ? ({ urgent: "预算紧张", warning: "消耗偏快", moderate: "节奏适中", healthy: "充裕正常" }[budget.status] || "已计算") : "未配置"; }
  if ($("budgetHeadline")) $("budgetHeadline").innerHTML = budget.hasBudget ? `按当前速度，预计还能使用 <em>${budget.projectedDaysLeft} 天</em>` : "配置搬瓦工凭证后显示预算判断";
  if ($("trafficProgressBar")) $("trafficProgressBar").style.width = `${Math.min(100, budget.usedPercent || pct)}%`;
  if ($("trafficProgressVal")) $("trafficProgressVal").textContent = budget.hasBudget ? `${budget.usedPercent}%` : "—";
  if ($("timeProgressBar")) $("timeProgressBar").style.width = `${Math.min(100, budget.timePercent || 0)}%`;
  if ($("timeProgressVal")) $("timeProgressVal").textContent = budget.hasBudget ? `${budget.timePercent}%` : "—";
  if ($("budgetTips")) $("budgetTips").innerHTML = budget.hasBudget ? `剩余 <b>${budget.daysLeft}</b> 天 · 建议每日不超过 <b>${formatBytes(budget.dailyBudgetBytes)}</b> · 当前日均 <b>${formatBytes(budget.currentDailyBytes)}</b>` : "配置搬瓦工凭证后可计算流量节奏与预算。";
  renderAttention(data);
  renderResources(server);
  const clients = xui.clients || [];
  if ($("clientOnlineSummary")) $("clientOnlineSummary").textContent = `${xui.onlineCount || 0} / ${xui.clientCount || clients.length}`;
  if ($("clientTotalSummary")) $("clientTotalSummary").textContent = `已用 ${formatBytes(xui.clientUsedBytes)}`;
  renderClientSummary(clients);
  const inbounds = xui.inbounds || [];
  if ($("inboundCountSummary")) $("inboundCountSummary").textContent = `${inbounds.length} 个入站`;
  if ($("inboundList")) $("inboundList").innerHTML = inbounds.length ? inbounds.map((item) => `<div><span class="inbound-title"><b class="badge">${esc(item.protocol)}</b>${esc(item.remark || "入站")} <span class="t-mute">:${esc(item.port)}</span></span><b>${formatBytes((item.up || 0) + (item.down || 0))}</b></div>`).join("") : '<div class="empty-state compact">暂无入站记录</div>';
  if ($("liveIoUp")) $("liveIoUp").textContent = server.netIoUp != null ? formatSpeed(server.netIoUp) : "—";
  if ($("liveIoDown")) $("liveIoDown").textContent = server.netIoDown != null ? formatSpeed(server.netIoDown) : "—";
  if ($("liveTcp")) $("liveTcp").textContent = server.tcp != null ? `${server.tcp} 连接` : "—";
  if ($("liveUdp")) $("liveUdp").textContent = server.udp != null ? `${server.udp} 连接` : "—";
}

function renderBwh(data) {
  const bwh = data.bwh || {};
  const xui = data.xui || {};
  const server = xui.server || {};
  const pct = Number(bwh.usedPercent || 0);
  if ($("bwhPct")) $("bwhPct").textContent = bwh.quotaBytes ? `${pct.toFixed(1)}%` : "—";
  if ($("bwhUsed")) $("bwhUsed").textContent = formatBytes(bwh.usedBytes);
  if ($("bwhQuota")) $("bwhQuota").textContent = formatBytes(bwh.quotaBytes);
  if ($("bwhLeft")) $("bwhLeft").textContent = formatBytes((bwh.quotaBytes || 0) - (bwh.usedBytes || 0));
  if ($("bwhReset")) $("bwhReset").textContent = bwh.resetAt ? `${formatTime(bwh.resetAt)}（还剩 ${daysLeft(bwh.resetAt)}）` : "—";
  if ($("bwhMultiplier")) $("bwhMultiplier").textContent = bwh.multiplier ? `${bwh.multiplier}x 计费倍率` : "1.0x";
  if ($("bwhWhere")) $("bwhWhere").textContent = `${bwh.status || "running"} · ${bwh.location || "—"}`;
  setRing(pct, ["ringArc"]);
  if ($("metaGrid")) $("metaGrid").innerHTML = [meta("主机名", bwh.hostname), meta("IP 地址", (bwh.ips || []).join(", ") || bwh.ip), meta("套餐规格", bwh.plan), meta("操作系统", bwh.os), meta("内存分配", bwh.ramBytes ? `${formatBytes(bwh.ramBytes)}（Swap ${formatBytes(bwh.swapBytes)}）` : "—"), meta("硬盘空间", bwh.diskBytes ? `${formatBytes(bwh.diskUsedBytes)} / ${formatBytes(bwh.diskBytes)}` : "—"), meta("虚拟化架构", bwh.vmType), meta("节点别名", bwh.node || bwh.location)].join("");
  if ($("xuiMetaGrid")) $("xuiMetaGrid").innerHTML = [meta("Xray 核心", server.xray ? `${server.xray} v${server.xrayVersion || ""}` : xui.configured ? "已配置" : "未配置"), meta("在线客户端", `${xui.onlineCount || 0} 在线 / ${xui.clientCount || 0} 总数`), meta("客户端已用流量", formatBytes(xui.clientUsedBytes)), meta("入站端口数", String((xui.inbounds || []).length))].join("");
}

function meta(label, value) { return `<div class="meta"><span>${esc(label)}</span><b title="${esc(value)}">${esc(value || "—")}</b></div>`; }

function renderClients() {
  const tbody = $("tbody");
  const allClients = snapshot?.xui?.clients || [];
  if (!tbody) return;
  let online = 0, warn = 0, off = 0, unlimited = 0;
  allClients.forEach((row) => { const state = clientState(row); if (row.online) online += 1; if (state === "warn") warn += 1; if (state === "off") off += 1; if (!row.total) unlimited += 1; });
  [["countAll", allClients.length], ["countOnline", online], ["countWarn", warn], ["countOff", off]].forEach(([id, value]) => { if ($(id)) $(id).textContent = value; });
  const query = ($("q")?.value || "").trim().toLowerCase();
  const rows = allClients.filter((row) => {
    const haystack = `${row.comment} ${row.email}`.toLowerCase();
    if (query && !haystack.includes(query)) return false;
    const state = clientState(row);
    if (clientFilter === "online") return row.online;
    if (clientFilter === "warn") return state === "warn";
    if (clientFilter === "off") return state === "off";
    return true;
  }).sort((a, b) => { const av = a[sortKey]; const bv = b[sortKey]; if (av == null && bv == null) return 0; if (av == null) return 1; if (bv == null) return -1; return (typeof av === "string" ? av.localeCompare(bv) : av - bv) * sortDir; });
  document.querySelectorAll("th[data-sort]").forEach((th) => { const icon = th.querySelector(".sort-ic"); if (!icon) return; const active = th.dataset.sort === sortKey; th.classList.toggle("sorted", active); th.setAttribute("aria-sort", active ? (sortDir === 1 ? "ascending" : "descending") : "none"); icon.textContent = active ? (sortDir === 1 ? "▲" : "▼") : ""; });
  tbody.innerHTML = rows.length ? rows.map((row) => {
    const state = clientState(row);
    const statusTag = state === "off" ? '<span class="tag bad">停用/到期</span>' : state === "warn" ? '<span class="tag warn">预警</span>' : row.online ? '<span class="tag ok">在线</span>' : '<span class="tag">离线</span>';
    const upShare = row.used ? row.up / row.used * 100 : 0;
    const downShare = row.used ? row.down / row.used * 100 : 0;
    const copyValue = esc(row.comment ? `${row.comment} (${row.email})` : row.email);
    const rowClass = state === "off" ? "row-off" : state === "warn" ? "row-warn" : row.online ? "row-online" : "";
    return `<tr class="${rowClass}"><td><span class="dot ${row.online ? "on" : ""}" title="${row.online ? "在线" : "离线"}"></span><span class="name">${esc(row.comment || row.email)}</span></td><td class="num">${formatBytes(row.used)}</td><td>${statusTag}</td><td class="usage"><div class="track"><i class="up" style="width:${upShare}%"></i><i class="down" style="width:${downShare}%"></i></div><div class="tiny">${row.percent == null ? "不限额" : `${Number(row.percent).toFixed(1)}%`} · ${row.total ? formatBytes(row.total) : "不限"}</div></td><td>${row.expiryTime ? formatTime(row.expiryTime) : '<span class="t-mute">长期</span>'}</td><td>${relative(row.lastOnline)}</td><td style="text-align:center"><button class="mini-btn" type="button" data-copy="${copyValue}" title="复制客户端信息">复制</button></td></tr>`;
  }).join("") : '<tr><td colspan="7"><div class="empty-state"><p>没有匹配的节点客户端</p><span>调整搜索词或筛选条件后重试。</span></div></td></tr>';
}

function render(data) {
  snapshot = data || {};
  renderShellStatus(snapshot);
  renderOverview(snapshot);
  renderBwh(snapshot);
  renderClients();
  renderChart();
}

let refreshIntervalSec = 20;
let countdown = refreshIntervalSec;
let isFetching = false;

async function load(force = false) {
  if (isFetching) return;
  isFetching = true;
  const button = $("refreshBtn");
  button?.classList.add("spinning");
  try {
    const response = await fetch(force ? "/api/refresh" : "/api/overview", { method: force ? "POST" : "GET" });
    if (response.status === 401) { location.href = "/login"; return; }
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    render(await response.json());
    countdown = refreshIntervalSec;
  } catch (error) {
    showToast("数据刷新失败，请检查连接", "bad");
  } finally {
    isFetching = false;
    button?.classList.remove("spinning");
  }
}

async function openSettings() {
  ["settingsErr", "testBwhRes", "testXuiRes"].forEach((id) => { if ($(id)) $(id).textContent = ""; });
  if ($("clearSecrets")) $("clearSecrets").checked = false;
  try {
    const response = await fetch("/api/settings");
    if (response.status === 401) { location.href = "/login"; return; }
    const data = await response.json();
    $("bwhVeid").value = data.bwhVeid || "";
    $("bwhApiKey").value = "";
    $("bwhApiKey").placeholder = data.bwhApiKeySet ? "已保存，留空保持不变" : "KiwiVM API Key";
    $("bwhApiBase").value = data.bwhApiBase || "https://api.64clouds.com/v1";
    $("xuiBaseUrl").value = data.xuiBaseUrl || "";
    $("xuiApiToken").value = "";
    $("xuiApiToken").placeholder = data.xuiApiTokenSet ? "已保存，留空保持不变" : "推荐使用 Token";
    $("xuiUsername").value = data.xuiUsername || "";
    $("xuiPassword").value = "";
    $("xuiPassword").placeholder = data.xuiPasswordSet ? "已保存，留空保持不变" : "无 Token 时必填";
    $("xuiTwoFactor").value = "";
    $("xuiTwoFactor").placeholder = data.xuiTwoFactorSet ? "已保存两步验证" : "两步验证 Code（可选）";
    $("xuiVerifySsl").checked = data.xuiVerifySsl !== false;
    refreshIntervalSec = Number(data.refreshInterval) || 20;
    $("refreshInterval").value = String(refreshIntervalSec);
    if (data.theme) applyTheme(data.theme);
    $("settingsMask").hidden = false;
    $("bwhVeid").focus();
  } catch (error) { showToast("加载设置失败", "bad"); }
}

function closeSettings() { if ($("settingsMask")) $("settingsMask").hidden = true; }

function applyTheme(theme) {
  const value = theme === "dark" ? "dark" : "light";
  document.documentElement.dataset.theme = value;
  localStorage.setItem("wagongTheme", value);
  if ($("themeSelect")) $("themeSelect").value = value;
  if (chartModel) renderChart();
}

async function testBwh() {
  const resultEl = $("testBwhRes");
  resultEl.textContent = "测试中…";
  resultEl.className = "test-res";
  try {
    const response = await fetch("/api/test-connection", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ target: "bwh", bwhVeid: $("bwhVeid").value.trim(), bwhApiKey: $("bwhApiKey").value.trim(), bwhApiBase: $("bwhApiBase").value.trim() }) });
    const result = await response.json();
    resultEl.className = `test-res ${result.ok ? "ok" : "bad"}`;
    resultEl.textContent = result.ok ? `✓ 连接成功（${result.latencyMs}ms · ${result.location || result.plan || "KiwiVM"}）` : `✕ 失败：${result.error || "无法连接"}`;
  } catch (error) { resultEl.className = "test-res bad"; resultEl.textContent = `✕ 请求出错：${error.message}`; }
}

async function testXui() {
  const resultEl = $("testXuiRes");
  resultEl.textContent = "测试中…";
  resultEl.className = "test-res";
  try {
    const response = await fetch("/api/test-connection", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ target: "xui", xuiBaseUrl: $("xuiBaseUrl").value.trim(), xuiApiToken: $("xuiApiToken").value, xuiUsername: $("xuiUsername").value.trim(), xuiPassword: $("xuiPassword").value, xuiTwoFactor: $("xuiTwoFactor").value.trim(), xuiVerifySsl: $("xuiVerifySsl").checked }) });
    const result = await response.json();
    resultEl.className = `test-res ${result.ok ? "ok" : "bad"}`;
    resultEl.textContent = result.ok ? `✓ 连接成功（${result.latencyMs}ms · ${result.clientsCount} 个客户端）` : `✕ 失败：${result.error || "无法连接"}`;
  } catch (error) { resultEl.className = "test-res bad"; resultEl.textContent = `✕ 请求出错：${error.message}`; }
}

function goTab(key, filter = "") {
  const button = document.querySelector(`.nav-item[data-tab="${key}"]`);
  if (button) button.click();
  if (filter) {
    clientFilter = filter;
    document.querySelectorAll("#statePills .pill").forEach((pill) => pill.classList.toggle("active", pill.dataset.filter === filter));
    renderClients();
  }
}

function initEvents() {
  $("settingsBtn")?.addEventListener("click", openSettings);
  $("settingsCloseBtn")?.addEventListener("click", closeSettings);
  $("settingsCancel")?.addEventListener("click", closeSettings);
  document.querySelectorAll(".settings-section-title").forEach((title) => {
    title.addEventListener("click", () => {
      const body = title.nextElementSibling;
      const expanded = title.getAttribute("aria-expanded") === "true";
      title.setAttribute("aria-expanded", String(!expanded));
      if (body) body.hidden = expanded;
    });
  });
  $("settingsMask")?.addEventListener("click", (event) => { if (event.target === $("settingsMask")) closeSettings(); });
  $("testBwhBtn")?.addEventListener("click", testBwh);
  $("testXuiBtn")?.addEventListener("click", testXui);
  document.querySelectorAll(".eye-btn").forEach((button) => button.addEventListener("click", () => { const input = $(button.dataset.for); if (!input) return; input.type = input.type === "password" ? "text" : "password"; button.textContent = input.type === "password" ? "显示" : "隐藏"; }));

  $("settingsForm")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if ($("clearSecrets")?.checked && !window.confirm("确定清除所有已保存的 API Key、Token 和密码吗？此操作不可撤销。")) return;
    $("settingsErr").textContent = "";
    const payload = { bwhVeid: $("bwhVeid").value.trim(), bwhApiBase: $("bwhApiBase").value.trim(), xuiBaseUrl: $("xuiBaseUrl").value.trim(), xuiUsername: $("xuiUsername").value.trim(), xuiVerifySsl: $("xuiVerifySsl").checked, refreshInterval: Number($("refreshInterval").value) || 20, theme: $("themeSelect").value };
    if ($("bwhApiKey").value) payload.bwhApiKey = $("bwhApiKey").value;
    if ($("xuiApiToken").value) payload.xuiApiToken = $("xuiApiToken").value;
    if ($("xuiPassword").value) payload.xuiPassword = $("xuiPassword").value;
    if ($("xuiTwoFactor").value) payload.xuiTwoFactor = $("xuiTwoFactor").value.trim();
    if ($("clearSecrets")?.checked) { payload.bwhApiKey = ""; payload.xuiApiToken = ""; payload.xuiPassword = ""; payload.xuiTwoFactor = ""; }
    try {
      const response = await fetch("/api/settings", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) });
      const data = await response.json();
      if (!response.ok || !data.ok) { $("settingsErr").textContent = data.error || "保存失败"; return; }
      refreshIntervalSec = payload.refreshInterval;
      applyTheme(payload.theme);
      closeSettings();
      showToast("设置已保存，数据已刷新", "ok");
      if (data.overview) render(data.overview); else load(true);
    } catch (error) { $("settingsErr").textContent = "网络请求失败，请稍后重试"; }
  });
  $("refreshBtn")?.addEventListener("click", () => load(true));
  $("quickRefresh")?.addEventListener("click", () => load(true));
  $("quickSettings")?.addEventListener("click", openSettings);
  $("quickCopy")?.addEventListener("click", () => copyText(`Bandwagon 状态：${$("modeChip")?.textContent || ""}，${$("stamp")?.textContent || ""}`, "状态摘要"));
  $("attentionAction")?.addEventListener("click", () => $("attentionPanel")?.scrollIntoView({ behavior: "smooth", block: "center" }));
  $("q")?.addEventListener("input", renderClients);
  $("tbody")?.addEventListener("click", (event) => { const button = event.target.closest("[data-copy]"); if (button) copyText(button.dataset.copy, "客户端信息"); });
  document.querySelectorAll("#statePills .pill").forEach((pill) => pill.addEventListener("click", () => { clientFilter = pill.dataset.filter; document.querySelectorAll("#statePills .pill").forEach((item) => item.classList.toggle("active", item === pill)); renderClients(); }));
  document.querySelectorAll("th[data-sort]").forEach((th) => {
    const sort = () => { const key = th.dataset.sort; if (sortKey === key) sortDir *= -1; else { sortKey = key; sortDir = key === "comment" || key === "inbound" ? 1 : -1; } renderClients(); };
    th.addEventListener("click", sort);
    th.addEventListener("keydown", (event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); sort(); } });
  });
  document.querySelectorAll(".nav-item[data-tab]").forEach((button) => button.addEventListener("click", () => {
    const key = button.dataset.tab;
    document.querySelectorAll(".nav-item[data-tab]").forEach((item) => { item.classList.toggle("active", item === button); if (item === button) item.setAttribute("aria-current", "page"); else item.removeAttribute("aria-current"); });
    document.querySelectorAll(".tab").forEach((section) => section.classList.toggle("active", section.id === `tab-${key}`));
    const titles = { overview: "总览", bwh: "VPS 资源", clients: "客户端" };
    const subtitles = { overview: "先看结论，再进入详情。保持清晰，减少打扰。", bwh: "查看套餐、服务器资源和网络历史。", clients: "搜索、筛选和查看每个代理客户端的用量。" };
    if ($("pageTitle")) $("pageTitle").textContent = titles[key] || key;
    if ($("pageSubtitle")) $("pageSubtitle").textContent = subtitles[key] || "";
    if (key === "bwh") requestAnimationFrame(renderChart);
  }));
  document.addEventListener("click", (event) => {
    const button = event.target.closest("[data-go-tab]");
    if (button) goTab(button.dataset.goTab, button.dataset.filter || "");
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeSettings();
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "r") { event.preventDefault(); load(true); }
    if ((event.metaKey || event.ctrlKey) && event.key === ",") { event.preventDefault(); openSettings(); }
  });
  window.addEventListener("resize", renderChart);
}

function initPoller() {
  setInterval(() => {
    if (document.hidden) return;
    countdown -= 1;
    if ($("countdownChip")) $("countdownChip").textContent = `${Math.max(0, countdown)}s`;
    if (countdown <= 0) { countdown = refreshIntervalSec; load(false); }
  }, 1000);
}

window.openSettings = openSettings;
window.load = load;
window.copyText = copyText;

const initialTheme = localStorage.getItem("wagongTheme") || "light";
applyTheme(initialTheme);
initEvents();
bindChartEvents();
initPoller();
load(false);
