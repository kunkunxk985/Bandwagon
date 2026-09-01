const $ = (id) => document.getElementById(id);

const UNITS = ["B", "KB", "MB", "GB", "TB", "PB"];

function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (ch) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  }[ch]));
}

function formatBytes(n) {
  n = Number(n || 0);
  if (!Number.isFinite(n)) return "—";
  const sign = n < 0 ? "-" : "";
  n = Math.abs(n);
  if (n < 1024) return `${sign}${n} B`;
  let i = 0;
  while (n >= 1024 && i < UNITS.length - 1) {
    n /= 1024;
    i += 1;
  }
  return `${sign}${n.toFixed(n >= 10 ? 1 : 2)} ${UNITS[i]}`;
}

function formatSpeed(n) {
  return `${formatBytes(n)}/s`;
}

function pad(n) {
  return String(n).padStart(2, "0");
}

function formatTime(ts, withTime = true) {
  if (!ts) return "—";
  const d = new Date(ts < 1e12 ? ts * 1000 : ts);
  if (Number.isNaN(d.getTime())) return "—";
  const date = `${d.getMonth() + 1}/${d.getDate()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  return withTime ? date : `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function relative(ts) {
  if (!ts) return "从未";
  const ms = ts < 1e12 ? ts * 1000 : ts;
  const delta = Date.now() - ms;
  if (delta < 0) return formatTime(ms);
  const m = Math.floor(delta / 60000);
  if (m < 1) return "刚刚";
  if (m < 60) return `${m} 分钟前`;
  const h = Math.floor(m / 60);
  if (h < 48) return `${h} 小时前`;
  return `${Math.floor(h / 24)} 天前`;
}

function daysLeft(resetAt) {
  if (!resetAt) return "—";
  const ms = resetAt < 1e12 ? resetAt * 1000 : resetAt;
  const days = Math.max(0, (ms - Date.now()) / 86400000);
  return `${days.toFixed(1)} 天`;
}

function ringGradient(pct) {
  if (pct >= 95) return "url(#gradBad)";
  if (pct >= 80) return "url(#gradWarn)";
  return "url(#gradOk)";
}

function setRing(pct) {
  const r = 52;
  const c = 2 * Math.PI * r;
  const p = Math.max(0, Math.min(100, pct || 0));
  const grad = ringGradient(p);
  const dash = `${(p / 100) * c} ${c}`;
  for (const id of ["ringArc", "ovrArc"]) {
    const circle = document.getElementById(id);
    if (!circle) continue;
    circle.setAttribute("stroke", grad);
    circle.setAttribute("stroke-dasharray", dash);
  }
}

// ── Toast 轻提示 ──
let toastTimer = null;
function showToast(msg, type = "info") {
  const el = $("toast");
  if (!el) return;
  if (toastTimer) clearTimeout(toastTimer);
  el.textContent = msg;
  el.className = `toast show ${type}`;
  toastTimer = setTimeout(() => {
    el.className = "toast";
  }, 2200);
}

// ── 复制剪贴板 ──
async function copyText(text, label = "内容") {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
    } else {
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      document.body.removeChild(ta);
    }
    showToast(`已复制${label}`, "ok");
  } catch (err) {
    showToast("复制失败", "bad");
  }
}

// ── 图表模块 ──
const CHART_COLORS = { in: "#2dd4a7", out: "#5b9dff" };

function niceMax(v) {
  const pow = Math.pow(10, Math.floor(Math.log10(v || 1)));
  for (const m of [1, 2, 5, 10]) {
    if (v <= m * pow) return m * pow;
  }
  return 10 * pow;
}

let chartRange = localStorage.getItem("wagongChartRange") || "7d";
let chartModel = null;
let chartHover = -1;

function chartDataFor(range) {
  const pts = (snapshot && snapshot.bwhHistory) || [];
  const now = Date.now() / 1000;
  const days = range === "7d" ? 7 : range === "30d" ? 30 : range === "24h" ? 1 : 400;
  const filtered = pts.filter((p) => p.t >= now - days * 86400);
  const byDay = new Map();
  for (const p of filtered) {
    const d = new Date(p.t * 1000);
    const key = d.getFullYear() * 10000 + d.getMonth() * 100 + d.getDate();
    if (!byDay.has(key)) {
      byDay.set(key, { t: new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() / 1000, in: 0, out: 0 });
    }
    const b = byDay.get(key);
    b.in += p.in;
    b.out += p.out;
  }
  const rows = [...byDay.values()].sort((a, b) => a.t - b.t);
  if (rows.length < 2) {
    return { mode: "bar", rows };
  }
  return { mode: "line", rows };
}

function updateChartMeta(model) {
  const rows = model.rows;
  const el = $("chartMeta");
  if (!el) return;
  if (!rows || !rows.length) {
    el.innerHTML = '<span class="chiplet hintc">暂无历史流量记录</span>';
    return;
  }
  const sumIn = rows.reduce((s, r) => s + (r.in || 0), 0);
  const sumOut = rows.reduce((s, r) => s + (r.out || 0), 0);
  const peak = rows.reduce((a, b) => ((b.in + b.out) > (a.in + a.out) ? b : a), rows[0]);
  const fmtDay = (t) => {
    const d = new Date(t * 1000);
    return `${d.getMonth() + 1}/${d.getDate()}`;
  };
  let spanDays = 1;
  if (rows.length > 1) spanDays = Math.max(1, (rows[rows.length - 1].t - rows[0].t) / 86400 + 1);
  const unit = model.mode === "bar" ? "日均" : "小时均值";
  el.innerHTML = `
    <span class="chiplet"><i class="dotc in"></i>合计 ↑ ${formatBytes(sumIn)} · ↓ ${formatBytes(sumOut)}</span>
    <span class="chiplet">${unit} ↑ ${formatBytes(sumIn / spanDays)} · ↓ ${formatBytes(sumOut / spanDays)}</span>
    <span class="chiplet">峰值 ${model.mode === "bar" ? fmtDay(peak.t) : formatTime(peak.t)} · ${formatBytes((peak.in || 0) + (peak.out || 0))}</span>
    ${model.mode === "bar" ? '<span class="chiplet hintc">柱高 = 当天总流量</span>' : ""}`;
}

function barTop(ctx, x, yTop, w, h, r) {
  r = Math.min(r, w / 2, Math.max(0, h));
  ctx.beginPath();
  ctx.moveTo(x, yTop + h);
  ctx.lineTo(x, yTop + r);
  ctx.arcTo(x, yTop, x + r, yTop, r);
  ctx.arcTo(x + w, yTop, x + w, yTop + r, r);
  ctx.lineTo(x + w, yTop + h);
  ctx.closePath();
}

function drawChart() {
  const canvas = $("netChart");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.parentElement.getBoundingClientRect();
  canvas.width = Math.max(1, Math.floor(rect.width * dpr));
  canvas.height = Math.max(1, Math.floor(rect.height * dpr));
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  const w = rect.width;
  const h = rect.height;
  ctx.clearRect(0, 0, w, h);

  let tip = document.querySelector(".chart-tip");
  const rows = chartModel ? chartModel.rows : [];
  if (!rows || rows.length < 2 || w < 80) {
    if (tip) tip.style.opacity = 0;
    ctx.fillStyle = "#5d6678";
    ctx.font = "12px -apple-system, PingFang SC, sans-serif";
    ctx.textAlign = "left";
    ctx.fillText("暂无历史数据", 14, h / 2);
    return;
  }

  const pad = { l: 56, r: 16, t: 16, b: 28 };
  const max = niceMax(Math.max(...rows.map((r) => (r.in || 0) + (r.out || 0)), 1));
  const plotW = w - pad.l - pad.r;
  const plotH = h - pad.t - pad.b;
  const y = (v) => pad.t + (1 - v / max) * plotH;

  // 网格线 + Y 刻度
  ctx.font = "10.5px -apple-system, PingFang SC, sans-serif";
  ctx.textAlign = "right";
  for (let g = 0; g <= 4; g++) {
    const v = (max * g) / 4;
    const yy = y(v);
    ctx.strokeStyle = "rgba(148,163,184,0.08)";
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(pad.l, yy);
    ctx.lineTo(w - pad.r, yy);
    ctx.stroke();
    ctx.fillStyle = "#6d788e";
    ctx.fillText(formatBytes(v), pad.l - 8, yy + 3.5);
  }

  // X 轴时间刻度
  const xTicks = [];
  if (chartModel.mode === "bar") {
    const slot = plotW / rows.length;
    const step = Math.max(1, Math.ceil(rows.length / 8));
    for (let i = 0; i < rows.length; i += step) {
      const d = new Date(rows[i].t * 1000);
      xTicks.push({ x: pad.l + slot * (i + 0.5), label: `${d.getMonth() + 1}/${d.getDate()}` });
    }
  } else {
    const step = Math.max(1, Math.ceil(rows.length / 6));
    for (let i = 0; i < rows.length; i += step) {
      xTicks.push({ x: pad.l + (plotW * i) / (rows.length - 1), label: formatTime(rows[i].t) });
    }
    if ((rows.length - 1) % step !== 0) {
      xTicks.push({ x: w - pad.r, label: formatTime(rows[rows.length - 1].t), align: "right" });
    }
  }
  ctx.fillStyle = "#6d788e";
  for (const t of xTicks) {
    ctx.textAlign = t.align === "right" ? "right" : "center";
    ctx.fillText(t.label, t.x, h - 8);
  }

  if (chartModel.mode === "bar") {
    const slot = plotW / rows.length;
    const bw = Math.max(3, Math.min(slot * 0.64, 46));
    rows.forEach((r, i) => {
      const cx = pad.l + slot * (i + 0.5);
      const hovered = chartHover === i;
      const hIn = ((r.in || 0) / max) * plotH;
      const hOut = ((r.out || 0) / max) * plotH;

      // 出站（上段，蓝）
      if (r.out > 0) {
        const grad = ctx.createLinearGradient(0, y((r.in || 0) + r.out), 0, y(r.in || 0));
        grad.addColorStop(0, hovered ? "#85b7ff" : CHART_COLORS.out);
        grad.addColorStop(1, hovered ? "#5b9dff" : CHART_COLORS.out + "cc");
        ctx.fillStyle = grad;
        barTop(ctx, cx - bw / 2, y((r.in || 0) + r.out), bw, hOut, 3);
        ctx.fill();
      }
      // 入站（下段，青）
      if (r.in > 0) {
        const grad = ctx.createLinearGradient(0, y(r.in), 0, y(0));
        grad.addColorStop(0, hovered ? "#52e6bc" : CHART_COLORS.in);
        grad.addColorStop(1, hovered ? "#2dd4a7" : CHART_COLORS.in + "cc");
        ctx.fillStyle = grad;
        if (r.out > 0) {
          ctx.fillRect(cx - bw / 2, y(r.in) - 0.5, bw, hIn + 0.5);
        } else {
          barTop(ctx, cx - bw / 2, y(r.in), bw, hIn, 3);
          ctx.fill();
        }
      }
    });
  } else {
    // 平滑折线
    const x = (i) => pad.l + (plotW * i) / (rows.length - 1);
    function linePath(key) {
      ctx.beginPath();
      ctx.moveTo(x(0), y(rows[0][key] || 0));
      for (let i = 1; i < rows.length; i++) {
        const x0 = x(i - 1), x1 = x(i);
        const y0 = y(rows[i - 1][key] || 0);
        const y1 = y(rows[i][key] || 0);
        const mx = (x0 + x1) / 2;
        ctx.bezierCurveTo(mx, y0, mx, y1, x1, y1);
      }
    }
    for (const key of ["out", "in"]) {
      const color = CHART_COLORS[key];
      linePath(key);
      ctx.lineTo(x(rows.length - 1), y(0));
      ctx.lineTo(x(0), y(0));
      ctx.closePath();
      const fill = ctx.createLinearGradient(0, pad.t, 0, h - pad.b);
      fill.addColorStop(0, color + "33");
      fill.addColorStop(1, color + "00");
      ctx.fillStyle = fill;
      ctx.fill();

      linePath(key);
      ctx.strokeStyle = color;
      ctx.lineWidth = 2;
      ctx.lineJoin = "round";
      ctx.lineCap = "round";
      ctx.stroke();
    }
  }

  // 峰值标注
  let peakRow = null;
  if (rows.length) {
    peakRow = rows.reduce((a, b) => ((b.in + b.out) > (a.in + a.out) ? b : a), rows[0]);
  }
  if (peakRow && chartModel.mode === "bar") {
    const peakIdx = rows.indexOf(peakRow);
    if (peakIdx >= 0) {
      const px = pad.l + (plotW / rows.length) * (peakIdx + 0.5);
      const py = y((peakRow.in || 0) + (peakRow.out || 0));
      ctx.beginPath();
      ctx.arc(px, py, 4.5, 0, Math.PI * 2);
      ctx.fillStyle = "#fff";
      ctx.fill();
      ctx.strokeStyle = "var(--blue)";
      ctx.lineWidth = 2;
      ctx.stroke();
      ctx.fillStyle = "#1d1d1f";
      ctx.font = "600 11px -apple-system, PingFang SC, sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("峰值", px, py - 12);
    }
  }

  // 悬浮高亮与 Tooltip
  if (chartHover >= 0 && chartHover < rows.length) {
    const p = rows[chartHover];
    let hx;
    if (chartModel.mode === "bar") {
      hx = pad.l + (plotW / rows.length) * (chartHover + 0.5);
    } else {
      hx = pad.l + (plotW * chartHover) / (rows.length - 1);
      for (const [key, color] of [["in", CHART_COLORS.in], ["out", CHART_COLORS.out]]) {
        ctx.beginPath();
        ctx.arc(hx, y(p[key] || 0), 4, 0, Math.PI * 2);
        ctx.fillStyle = color;
        ctx.fill();
        ctx.strokeStyle = "#090c11";
        ctx.lineWidth = 2;
        ctx.stroke();
      }
    }
    ctx.strokeStyle = "rgba(232,236,244,0.22)";
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    ctx.moveTo(hx, pad.t);
    ctx.lineTo(hx, h - pad.b);
    ctx.stroke();
    ctx.setLineDash([]);

    if (!tip) {
      tip = document.createElement("div");
      tip.className = "chart-tip";
      canvas.parentElement.appendChild(tip);
    }
    const pd = new Date(p.t * 1000);
    const label = chartModel.mode === "bar" ? `${pd.getMonth() + 1}/${pd.getDate()} 当天` : formatTime(p.t);
    tip.innerHTML = `<b>${label}</b><br>`
      + `<span class="t-up">↑ 入站 ${formatBytes(p.in || 0)}</span><br>`
      + `<span class="t-down">↓ 出站 ${formatBytes(p.out || 0)}</span><br>`
      + `<span class="t-tot">∑ 合计 ${formatBytes((p.in || 0) + (p.out || 0))}</span>`;
    tip.style.opacity = 1;
    const tw = tip.offsetWidth;
    const left = hx + 14 + tw > w ? hx - tw - 14 : hx + 14;
    tip.style.left = `${Math.max(4, Math.min(w - tw - 4, left))}px`;
    tip.style.top = `${Math.max(4, y(Math.min(max, (p.in || 0) + (p.out || 0))) - 8)}px`;
  } else if (tip) {
    tip.style.opacity = 0;
  }

  canvas._model = chartModel;
  canvas._geom = { pad, plotW };
}

function renderChart() {
  const canvas = $("netChart");
  if (!canvas) return;
  const rect = canvas.parentElement.getBoundingClientRect();
  chartModel = chartDataFor(chartRange);
  chartHover = -1;
  updateChartMeta(chartModel);
  if (rect.width < 60) return;
  drawChart();
}

function bindChartEvents() {
  const canvas = $("netChart");
  if (!canvas) return;

  function showTouchTooltip(x, y) {
    const model = canvas._model;
    const geom = canvas._geom;
    if (!model || !geom || !model.rows.length) return;
    const rect = canvas.getBoundingClientRect();
    const mx = x - rect.left;
    const { pad, plotW } = geom;
    if (mx < pad.l || mx > pad.l + plotW) {
      if (chartHover !== -1) { chartHover = -1; drawChart(); }
      return;
    }
    const ratio = (mx - pad.l) / plotW;
    const idx = model.mode === "bar"
      ? Math.floor(ratio * model.rows.length)
      : Math.round(ratio * (model.rows.length - 1));
    const clamped = Math.max(0, Math.min(model.rows.length - 1, idx));
    if (clamped !== chartHover) {
      chartHover = clamped;
      drawChart();
    }
  }

  canvas.addEventListener("mousemove", (event) => {
    const model = canvas._model;
    const geom = canvas._geom;
    if (!model || !geom || !model.rows.length) return;
    const rect = canvas.getBoundingClientRect();
    const mx = event.clientX - rect.left;
    const { pad, plotW } = geom;
    if (mx < pad.l || mx > pad.l + plotW) {
      if (chartHover !== -1) { chartHover = -1; drawChart(); }
      return;
    }
    const ratio = (mx - pad.l) / plotW;
    const idx = model.mode === "bar"
      ? Math.floor(ratio * model.rows.length)
      : Math.round(ratio * (model.rows.length - 1));
    const clamped = Math.max(0, Math.min(model.rows.length - 1, idx));
    if (clamped !== chartHover) {
      chartHover = clamped;
      drawChart();
    }
  });
  canvas.addEventListener("mouseleave", () => {
    if (chartHover !== -1) {
      chartHover = -1;
      drawChart();
    }
  });

  // 移动端：轻触显示 tooltip，再次点击或滑动取消
  let touchTimer = null;
  canvas.addEventListener("touchstart", (event) => {
    if (!event.touches.length) return;
    const touch = event.touches[0];
    showTouchTooltip(touch.clientX, touch.clientY);
    if (touchTimer) clearTimeout(touchTimer);
    touchTimer = setTimeout(() => {
      if (chartHover !== -1) {
        chartHover = -1;
        drawChart();
      }
    }, 3000);
  }, { passive: true });

  canvas.addEventListener("touchmove", (event) => {
    if (!event.touches.length) return;
    const touch = event.touches[0];
    showTouchTooltip(touch.clientX, touch.clientY);
  }, { passive: true });

  canvas.addEventListener("touchend", () => {
    if (touchTimer) clearTimeout(touchTimer);
    touchTimer = setTimeout(() => {
      if (chartHover !== -1) {
        chartHover = -1;
        drawChart();
      }
    }, 1500);
  });

  document.querySelectorAll("#chartRangeSeg button").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.range === chartRange);
    btn.addEventListener("click", () => {
      chartRange = btn.dataset.range;
      localStorage.setItem("wagongChartRange", chartRange);
      document.querySelectorAll("#chartRangeSeg button").forEach((b) => b.classList.toggle("active", b === btn));
      renderChart();
    });
  });
}

// ── 客户端列表与排序 ──
const STAT_ICONS = {
  users: '<svg viewBox="0 0 24 24"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>',
  cpu: '<svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/><line x1="9" y1="1" x2="9" y2="4"/><line x1="15" y1="1" x2="15" y2="4"/><line x1="9" y1="20" x2="9" y2="23"/><line x1="15" y1="20" x2="15" y2="23"/><line x1="20" y1="9" x2="23" y2="9"/><line x1="20" y1="14" x2="23" y2="14"/><line x1="1" y1="9" x2="4" y2="9"/><line x1="1" y1="14" x2="4" y2="14"/></svg>',
  ram: '<svg viewBox="0 0 24 24"><rect x="2" y="7" width="20" height="11" rx="2"/><line x1="6" y1="7" x2="6" y2="18"/><line x1="10" y1="7" x2="10" y2="18"/><line x1="14" y1="7" x2="14" y2="18"/><line x1="18" y1="7" x2="18" y2="18"/></svg>',
  disk: '<svg viewBox="0 0 24 24"><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/></svg>',
};

function statCard(label, value, pct, color, icon, sub = "") {
  const width = pct == null ? 0 : Math.max(0, Math.min(100, pct));
  return `<div class="card stat">
    <div class="stat-top">
      <span class="stat-ic" style="color:${color}">${STAT_ICONS[icon] || ""}</span>
      <div class="lbl">${label}</div>
    </div>
    <div class="num">${value}</div>
    ${sub ? `<div class="sub-lbl">${sub}</div>` : ""}
    <div class="bar"><i style="width:${width}%;background:${color || "var(--teal)"}"></i></div>
  </div>`;
}

function meta(label, value) {
  return `<div class="meta"><span>${label}</span><b title="${esc(value)}">${value || "—"}</b></div>`;
}

let sortKey = "used";
let sortDir = -1;
let clientFilter = "all";
let snapshot = null;

function clientState(row) {
  const now = Date.now();
  const exp = row.expiryTime || 0;
  const expired = exp > 0 && exp < now;
  const expiring = exp > 0 && exp - now < 5 * 86400000;
  const hot = row.percent != null && row.percent >= 80;
  if (!row.enable || expired) return "off";
  if (hot || expiring) return "warn";
  if (row.online) return "online";
  return "ok";
}

function renderClients() {
  const q = ($("q")?.value || "").trim().toLowerCase();
  const allClients = snapshot?.xui?.clients || [];

  // 计算各状态数量
  let countOnline = 0, countWarn = 0, countOff = 0, countUnlimited = 0;
  allClients.forEach((c) => {
    const st = clientState(c);
    if (c.online) countOnline++;
    if (st === "warn") countWarn++;
    if (st === "off") countOff++;
    if (!c.total) countUnlimited++;
  });

  if ($("countAll")) $("countAll").textContent = allClients.length;
  if ($("countOnline")) $("countOnline").textContent = countOnline;
  if ($("countWarn")) $("countWarn").textContent = countWarn;
  if ($("countOff")) $("countOff").textContent = countOff;
  if ($("countUnlimited")) $("countUnlimited").textContent = countUnlimited;

  const rows = allClients
    .filter((row) => {
      const hay = `${row.email} ${row.comment} ${row.inbound} ${row.protocol} ${row.inboundId || ""}`.toLowerCase();
      if (q && !hay.includes(q)) return false;
      const st = clientState(row);
      if (clientFilter === "online") return row.online;
      if (clientFilter === "warn") return st === "warn";
      if (clientFilter === "off") return st === "off";
      if (clientFilter === "unlimited") return !row.total;
      return true;
    })
    .sort((a, b) => {
      const av = a[sortKey];
      const bv = b[sortKey];
      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;
      if (typeof av === "string") return av.localeCompare(bv) * sortDir;
      return (av - bv) * sortDir;
    });

  // 更新表头排序箭头
  document.querySelectorAll("th[data-sort]").forEach((th) => {
    const ic = th.querySelector(".sort-ic");
    if (!ic) return;
    if (th.dataset.sort === sortKey) {
      ic.textContent = sortDir === 1 ? "▲" : "▼";
      th.classList.add("sorted");
    } else {
      ic.textContent = "";
      th.classList.remove("sorted");
    }
  });

  const tbody = $("tbody");
  if (!tbody) return;

  tbody.innerHTML = rows.map((row) => {
    const usedPct = row.percent;
    const totalLabel = row.total ? formatBytes(row.total) : "不限";
    const upShare = row.used ? (row.up / row.used) * 100 : 0;
    const downShare = row.used ? (row.down / row.used) * 100 : 0;
    const st = clientState(row);
    const tag = st === "off" ? `<span class="tag bad">停用/到期</span>`
      : st === "warn" ? `<span class="tag warn">预警</span>`
      : row.online ? `<span class="tag ok">在线</span>` : "";

    const copyPayload = esc(row.comment ? `${row.comment} (${row.email})` : row.email);

    return `<tr>
      <td>
        <span class="dot ${row.online ? "on" : ""}" title="${row.online ? "在线" : "离线"}"></span>
        <span class="name">${esc(row.comment || row.email)}</span>
        <div class="tiny">${esc(row.email)}${tag ? " · " + tag : ""}</div>
      </td>
      <td>
        <span class="badge proto">${esc(row.protocol || "proxy")}</span>
        <span class="inbound-name">${esc(row.inbound || "—")}</span>
      </td>
      <td class="num font-bold">${formatBytes(row.used)}</td>
      <td class="num t-up">↑ ${formatBytes(row.up)}</td>
      <td class="num t-down">↓ ${formatBytes(row.down)}</td>
      <td class="usage">
        <div class="track"><i class="up" style="width:${upShare}%"></i><i class="down" style="width:${downShare}%"></i></div>
        <div class="tiny">${usedPct == null ? "不限额" : usedPct.toFixed(1) + "%"} · ${totalLabel}</div>
      </td>
      <td>${row.expiryTime ? formatTime(row.expiryTime) : "<span class='t-mute'>长期</span>"}</td>
      <td>${relative(row.lastOnline)}</td>
      <td style="text-align:center">
        <button class="mini-btn" type="button" onclick="copyText('${copyPayload}', '客户端信息')" title="复制客户端信息">复制</button>
      </td>
    </tr>`;
  }).join("") || `<tr><td colspan="9" class="empty-hint">没有匹配的节点客户端</td></tr>`;
}

// ── 渲染总览与各 Tab ──
function render(data) {
  snapshot = data;
  const bwh = data.bwh || {};
  const xui = data.xui || {};
  const server = xui.server || {};
  const budget = data.budget || {};
  const pct = bwh.usedPercent || 0;
  const errors = [bwh.error, xui.error].filter(Boolean);

  // 初次渲染后隐藏骨架屏，显示真实内容
  hideSkeleton("ovrSkel");
  hideSkeleton("inboundSkel");
  hideSkeleton("netSkel");
  const realIds = ["ovrReal", "statGrid", "inboundList", "networkLiveStats"];
  realIds.forEach(id => {
    const el = $(id);
    if (el) el.classList.remove("hide");
  });

  $("modeChip").textContent = data.demo ? "演示数据" : (data.ok ? "实时数据" : "部分失败");
  $("modeChip").className = "chip " + (data.demo ? "demo" : data.ok ? "ok" : "bad");
  $("stamp").textContent = data.fetchedAt ? `更新于 ${formatTime(data.fetchedAt)}` : "";
  $("banner").className = "banner" + (data.demo || errors.length ? " show" : "");
  if (data.demo) {
    $("banner").textContent = "当前为演示数据。可在右上角「设置与连接」中填入真实凭证或编辑 .env。";
  } else if (errors.length) {
    $("banner").textContent = errors.join("  |  ");
  }

  // 搬瓦工套餐流量卡
  $("bwhPct").textContent = bwh.quotaBytes ? `${pct.toFixed(1)}%` : "—";
  $("bwhUsed").textContent = formatBytes(bwh.usedBytes);
  $("bwhQuota").textContent = formatBytes(bwh.quotaBytes);
  $("bwhLeft").textContent = formatBytes((bwh.quotaBytes || 0) - (bwh.usedBytes || 0));
  $("bwhReset").textContent = `${formatTime(bwh.resetAt, true)} (还剩 ${daysLeft(bwh.resetAt)})`;
  $("bwhMultiplier").textContent = bwh.multiplier ? `${bwh.multiplier}x 计费倍率` : "1.0x";
  $("bwhWhere").textContent = `${bwh.status || "running"} · ${bwh.location || "—"}`;
  setRing(pct);

  // 总览页环
  $("ovrPct").textContent = bwh.quotaBytes ? `${pct.toFixed(1)}%` : "—";
  $("ovrUsed").textContent = formatBytes(bwh.usedBytes);
  $("ovrLeft").textContent = formatBytes((bwh.quotaBytes || 0) - (bwh.usedBytes || 0));
  $("ovrReset").textContent = bwh.resetAt ? `${daysLeft(bwh.resetAt)}后 (${formatTime(bwh.resetAt, false)})` : "—";

  // 预算节奏分析
  if (budget.hasBudget) {
    $("timeProgressBar").style.width = `${budget.timePercent}%`;
    $("timeProgressVal").textContent = `${budget.timePercent}% (第 ${budget.daysPassed} 天)`;
    $("trafficProgressBar").style.width = `${Math.min(100, budget.usedPercent)}%`;
    $("trafficProgressVal").textContent = `${budget.usedPercent}%`;

    const statusBadge = $("budgetStatusBadge");
    if (budget.status === "urgent") {
      statusBadge.className = "badge bad";
      statusBadge.textContent = "流量紧缺 ⚠️";
    } else if (budget.status === "warning") {
      statusBadge.className = "badge warn";
      statusBadge.textContent = "消耗偏快";
    } else if (budget.status === "moderate") {
      statusBadge.className = "badge warn";
      statusBadge.textContent = "节奏适中";
    } else {
      statusBadge.className = "badge ok";
      statusBadge.textContent = "充裕正常 ✓";
    }

    $("budgetTips").innerHTML = `剩余 <b>${budget.daysLeft}</b> 天 · 建议日均 <b>≤ ${formatBytes(budget.dailyBudgetBytes)}</b> · 当前日均 <b>${formatBytes(budget.currentDailyBytes)}</b>`;
  } else {
    $("budgetTips").textContent = "配置搬瓦工凭证后可计算流量节奏与预算。";
  }

  // 搬瓦工服务器规格卡
  $("metaGrid").innerHTML = [
    meta("主机名", esc(bwh.hostname)),
    meta("IP 地址", esc((bwh.ips || []).join(", ") || bwh.ip)),
    meta("套餐规格", esc(bwh.plan)),
    meta("操作系统", esc(bwh.os)),
    meta("内存分配", bwh.ramBytes ? `${formatBytes(bwh.ramBytes)} (Swap: ${formatBytes(bwh.swapBytes)})` : "—"),
    meta("硬盘空间", bwh.diskBytes ? `${formatBytes(bwh.diskUsedBytes)} / ${formatBytes(bwh.diskBytes)}` : "—"),
    meta("虚拟化架构", esc(bwh.vmType)),
    meta("节点别名", esc(bwh.node || bwh.location)),
  ].join("");

  // 节点客户端总览卡
  $("xuiMetaGrid").innerHTML = [
    meta("Xray 核心", esc(server.xray ? `${server.xray} v${server.xrayVersion || ""}` : (xui.configured ? "已配置" : "未配置"))),
    meta("在线客户端", `${xui.onlineCount || 0} 在线 / ${xui.clientCount || 0} 总数`),
    meta("客户端已用流量", formatBytes(xui.clientUsedBytes)),
    meta("入站端口数", String((xui.inbounds || []).length)),
  ].join("");

  // 总览页指标卡片
  const memPct = server.memTotal ? (server.memUsed / server.memTotal) * 100 : 0;
  const diskPct = server.diskTotal ? (server.diskUsed / server.diskTotal) * 100 : 0;
  $("statGrid").innerHTML = [
    statCard("活跃客户端", `${xui.onlineCount || 0} / ${xui.clientCount || 0}`, xui.clientCount ? (xui.onlineCount / xui.clientCount) * 100 : 0, "var(--teal)", "users", `启用 ${xui.enabledCount || 0} 个`),
    statCard("CPU 负载", server.cpu != null ? `${Number(server.cpu).toFixed(1)}%` : "—", server.cpu, "var(--amber)", "cpu", `${server.cpuCores || 1} 核心`),
    statCard("内存占用", server.memTotal ? `${formatBytes(server.memUsed)}` : "—", memPct, "var(--blue)", "ram", `总量 ${formatBytes(server.memTotal)}`),
    statCard("磁盘空间", server.diskTotal ? `${formatBytes(server.diskUsed)}` : "—", diskPct, "var(--red)", "disk", `总量 ${formatBytes(server.diskTotal)}`),
  ].join("");

  // 实时网络指标
  if ($("liveIoUp")) $("liveIoUp").textContent = server.netIoUp != null ? formatSpeed(server.netIoUp) : "—";
  if ($("liveIoDown")) $("liveIoDown").textContent = server.netIoDown != null ? formatSpeed(server.netIoDown) : "—";
  if ($("liveTcp")) $("liveTcp").textContent = server.tcp != null ? `${server.tcp} 连接` : "—";
  if ($("liveUdp")) $("liveUdp").textContent = server.udp != null ? `${server.udp} 连接` : "—";

  // 入站列表
  const inbounds = xui.inbounds || [];
  $("inboundList").innerHTML = inbounds.length
    ? inbounds.map((item) => `
        <div>
          <span class="inbound-title">
            <b class="badge">${esc(item.protocol)}</b>
            ${esc(item.remark || "入站")} <span class="t-mute">:${esc(item.port)}</span>
          </span>
          <b>${formatBytes((item.up || 0) + (item.down || 0))} · ${item.clientCount} 客户端</b>
        </div>`).join("")
    : "<div><span>暂无入站记录</span><b>—</b></div>";

  renderChart();
  renderClients();
}

// ── 数据加载与倒计时 ──
let refreshIntervalSec = 20;
let countdown = refreshIntervalSec;
let isFetching = false;

function showSkeleton(id) {
  const wrap = $(id);
  if (wrap) wrap.classList.remove("hide");
}
function hideSkeleton(id) {
  const wrap = $(id);
  if (wrap) wrap.classList.add("hide");
}

async function load(force = false) {
  if (isFetching) return;
  isFetching = true;
  const btn = $("refreshBtn");
  if (btn) btn.classList.add("spinning");

  showSkeleton("ovrSkel");
  showSkeleton("inboundSkel");
  showSkeleton("netSkel");

  try {
    const url = force ? "/api/refresh" : "/api/overview";
    const res = await fetch(url, { method: force ? "POST" : "GET" });
    if (res.status === 401) {
      location.href = "/login";
      return;
    }
    const data = await res.json();
    render(data);
    countdown = refreshIntervalSec;
  } catch (err) {
    showToast("数据刷新失败，请检查连接", "bad");
  } finally {
    isFetching = false;
    if (btn) btn.classList.remove("spinning");
    hideSkeleton("ovrSkel");
    hideSkeleton("inboundSkel");
    hideSkeleton("netSkel");
  }
}

// ── 设置弹窗与连接测试 ──
async function openSettings() {
  $("settingsErr").textContent = "";
  $("testBwhRes").textContent = "";
  $("testXuiRes").textContent = "";
  $("clearSecrets").checked = false;

  try {
    const res = await fetch("/api/settings");
    const data = await res.json();
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
    $("xuiTwoFactor").placeholder = data.xuiTwoFactorSet ? "已保存两步验证" : "两步验证 Code (可选)";
    $("xuiVerifySsl").checked = data.xuiVerifySsl !== false;

    if (data.refreshInterval && $("refreshInterval")) {
      $("refreshInterval").value = String(data.refreshInterval);
      refreshIntervalSec = Number(data.refreshInterval) || 20;
    }
    if (data.theme && $("themeSelect")) {
      $("themeSelect").value = data.theme;
      applyTheme(data.theme);
    }

    $("settingsMask").hidden = false;
    $("bwhVeid").focus();
  } catch (err) {
    showToast("加载设置失败", "bad");
  }
}

function closeSettings() {
  $("settingsMask").hidden = true;
}

function applyTheme(theme) {
  if (theme === "light") {
    document.documentElement.dataset.theme = "light";
  } else {
    document.documentElement.dataset.theme = "dark";
  }
  localStorage.setItem("wagongTheme", theme);
}

// ── 测试 KiwiVM 连接 ──
async function testBwh() {
  const resEl = $("testBwhRes");
  resEl.textContent = "测试中…";
  resEl.className = "test-res hintc";

  const payload = {
    target: "bwh",
    bwhVeid: $("bwhVeid").value.trim(),
    bwhApiKey: $("bwhApiKey").value.trim(),
    bwhApiBase: $("bwhApiBase").value.trim(),
  };

  try {
    const res = await fetch("/api/test-connection", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const result = await res.json();
    if (result.ok) {
      resEl.className = "test-res ok";
      resEl.textContent = `✓ 连接成功 (${result.latencyMs}ms · ${result.location || result.plan})`;
    } else {
      resEl.className = "test-res bad";
      resEl.textContent = `✕ 失败: ${result.error || "无法连接"}`;
    }
  } catch (err) {
    resEl.className = "test-res bad";
    resEl.textContent = `✕ 请求出错: ${err.message}`;
  }
}

// ── 测试 3X-UI 连接 ──
async function testXui() {
  const resEl = $("testXuiRes");
  resEl.textContent = "测试中…";
  resEl.className = "test-res hintc";

  const payload = {
    target: "xui",
    xuiBaseUrl: $("xuiBaseUrl").value.trim(),
    xuiApiToken: $("xuiApiToken").value,
    xuiUsername: $("xuiUsername").value.trim(),
    xuiPassword: $("xuiPassword").value,
    xuiTwoFactor: $("xuiTwoFactor").value.trim(),
    xuiVerifySsl: $("xuiVerifySsl").checked,
  };

  try {
    const res = await fetch("/api/test-connection", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const result = await res.json();
    if (result.ok) {
      resEl.className = "test-res ok";
      resEl.textContent = `✓ 成功 (${result.latencyMs}ms · Xray ${result.xrayVersion} · ${result.clientsCount}客户端)`;
    } else {
      resEl.className = "test-res bad";
      resEl.textContent = `✕ 失败: ${result.error || "无法连接"}`;
    }
  } catch (err) {
    resEl.className = "test-res bad";
    resEl.textContent = `✕ 请求出错: ${err.message}`;
  }
}

// ── 初始化事件绑定 ──
function initEvents() {
  // 设置按钮与关闭
  $("settingsBtn")?.addEventListener("click", openSettings);
  $("settingsCloseBtn")?.addEventListener("click", closeSettings);
  $("settingsCancel")?.addEventListener("click", closeSettings);
  $("settingsMask")?.addEventListener("click", (e) => {
    if (e.target === $("settingsMask")) closeSettings();
  });

  // 测试连接按钮
  $("testBwhBtn")?.addEventListener("click", testBwh);
  $("testXuiBtn")?.addEventListener("click", testXui);

  // 密码显示/隐藏切换
  document.querySelectorAll(".eye-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      const targetId = btn.dataset.for;
      const input = $(targetId);
      if (!input) return;
      input.type = input.type === "password" ? "text" : "password";
      btn.textContent = input.type === "password" ? "👁" : "🔒";
    });
  });

  // 表单提交
  $("settingsForm")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    $("settingsErr").textContent = "";
    const payload = {
      bwhVeid: $("bwhVeid").value.trim(),
      bwhApiBase: $("bwhApiBase").value.trim(),
      xuiBaseUrl: $("xuiBaseUrl").value.trim(),
      xuiUsername: $("xuiUsername").value.trim(),
      xuiVerifySsl: $("xuiVerifySsl").checked,
      refreshInterval: Number($("refreshInterval").value) || 20,
      theme: $("themeSelect").value,
    };
    if ($("bwhApiKey").value) payload.bwhApiKey = $("bwhApiKey").value;
    if ($("xuiApiToken").value) payload.xuiApiToken = $("xuiApiToken").value;
    if ($("xuiPassword").value) payload.xuiPassword = $("xuiPassword").value;
    if ($("xuiTwoFactor").value) payload.xuiTwoFactor = $("xuiTwoFactor").value.trim();

    if ($("clearSecrets").checked) {
      payload.bwhApiKey = "";
      payload.xuiApiToken = "";
      payload.xuiPassword = "";
      payload.xuiTwoFactor = "";
    }

    try {
      const res = await fetch("/api/settings", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const data = await res.json();
      if (!res.ok || !data.ok) {
        $("settingsErr").textContent = data.error || "保存失败";
        return;
      }
      refreshIntervalSec = payload.refreshInterval;
      applyTheme(payload.theme);
      closeSettings();
      showToast("设置已保存并刷新", "ok");
      if (data.overview) render(data.overview);
      else load(true);
    } catch (err) {
      $("settingsErr").textContent = "网络请求失败";
    }
  });

  // 刷新按钮
  $("refreshBtn")?.addEventListener("click", () => load(true));

  // 快捷操作按钮
  $("quickRefresh")?.addEventListener("click", () => load(true));
  $("quickSettings")?.addEventListener("click", openSettings);
  $("quickCopy")?.addEventListener("click", () => {
    const stamp = $("stamp")?.textContent || "";
    const mode = $("modeChip")?.textContent || "";
    const summary = `瓦工台状态：${mode}，${stamp}`;
    copyText(summary, "状态摘要");
  });

  // 客户端搜索与筛选
  $("q")?.addEventListener("input", renderClients);
  document.querySelectorAll("#statePills .pill").forEach((pill) => {
    pill.addEventListener("click", () => {
      clientFilter = pill.dataset.filter;
      document.querySelectorAll("#statePills .pill").forEach((p) => p.classList.toggle("active", p === pill));
      renderClients();
    });
  });

  // 客户端表格列排序
  document.querySelectorAll("th[data-sort]").forEach((th) => {
    th.addEventListener("click", () => {
      const key = th.dataset.sort;
      if (sortKey === key) {
        sortDir *= -1;
      } else {
        sortKey = key;
        sortDir = (key === "comment" || key === "inbound") ? 1 : -1;
      }
      renderClients();
    });
  });

  // Tab 切换
  const TAB_TITLES = { overview: "总览", bwh: "搬瓦工 VPS", clients: "节点客户端" };
  document.querySelectorAll(".nav-item[data-tab]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const key = btn.dataset.tab;
      document.querySelectorAll(".nav-item[data-tab]").forEach((b) => b.classList.toggle("active", b === btn));
      document.querySelectorAll(".tab").forEach((sec) => sec.classList.toggle("active", sec.id === `tab-${key}`));
      if ($("pageTitle")) $("pageTitle").textContent = TAB_TITLES[key] || key;
      if (key === "bwh") requestAnimationFrame(renderChart);
    });
  });

  // 全局键盘快捷键
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      closeSettings();
    }
    // Cmd+R / Ctrl+R 手动刷新
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "r") {
      event.preventDefault();
      load(true);
    }
    // Cmd+, / Ctrl+, 打开设置
    if ((event.metaKey || event.ctrlKey) && event.key === ",") {
      event.preventDefault();
      openSettings();
    }
  });

  window.addEventListener("resize", renderChart);
}

// ── 倒计时定时器 ──
function initPoller() {
  setInterval(() => {
    if (document.hidden) return;
    countdown--;
    if ($("countdownChip")) {
      $("countdownChip").textContent = `${Math.max(0, countdown)}s`;
    }
    if (countdown <= 0) {
      countdown = refreshIntervalSec;
      load(false);
    }
  }, 1000);
}

// 暴露全局方法
window.openSettings = openSettings;
window.load = load;
window.copyText = copyText;

// 启动执行
const savedTheme = localStorage.getItem("wagongTheme") || "dark";
applyTheme(savedTheme);

initEvents();
bindChartEvents();
initPoller();
load(false);

