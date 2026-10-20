// The challenge page your friend opens from the invite link. Plain HTML +
// JS, no build step. The token lives in the URL #fragment (and this
// browser's localStorage) and is sent only as a Bearer header to this
// same server.

export function page(id) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#F6F5F1" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0E0F11" media="(prefers-color-scheme: dark)">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="Challenge">
<meta name="robots" content="noindex">
<title>Weight-Loss Challenge</title>
<style>
  :root {
    --paper:#F6F5F1; --surface:#FFFFFF; --ink:#151619; --ink2:#6B6C72; --ink3:#A1A1A6;
    --track:rgba(0,0,0,.06); --hair:rgba(0,0,0,.07);
    --green:#4CB868; --greenSoft:#DDF3E1; --orange:#F59A4C; --orangeSoft:#FFE7D3;
    --lav:#A88BEB; --lavSoft:#ECE4FB; --rose:#EE7C8E; --sky:#5DB4F0; --skySoft:#DDF0FC;
    --shadow: 0 6px 24px rgba(20,20,30,.06);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --paper:#0E0F11; --surface:#18191D; --ink:#F2F2F3; --ink2:#A3A4AA; --ink3:#6B6B72;
      --track:rgba(255,255,255,.08); --hair:rgba(255,255,255,.08);
      --greenSoft:#1C3324; --orangeSoft:#3A2718; --lavSoft:#2B2342; --skySoft:#16293A;
      --shadow: none;
    }
  }
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  body { margin:0; background:var(--paper); color:var(--ink);
         font: 15px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
  main { max-width: 540px; margin: 0 auto; padding: calc(env(safe-area-inset-top) + 18px) 16px 56px; }
  .eyebrow { font-size: 11px; font-weight: 700; letter-spacing: .08em; text-transform: uppercase; color: var(--ink3); }
  h1 { font-size: 34px; line-height: 1.05; letter-spacing: -.8px; margin: 6px 0 4px; }
  h2 { font-size: 16px; margin: 0 0 12px; letter-spacing: -.2px; }
  .muted { color: var(--ink2); font-size: 13px; }
  .tiny { color: var(--ink3); font-size: 11px; }
  .card { background: var(--surface); border: 1px solid var(--hair); border-radius: 26px;
          padding: 18px; margin-bottom: 14px; box-shadow: var(--shadow); }
  .row { display:flex; gap:10px; align-items: stretch; }
  .row > * { flex:1; min-width: 0; }
  .between { display:flex; justify-content: space-between; align-items: center; gap: 8px; }
  .pill { display:inline-flex; align-items:center; gap:4px; padding: 4px 10px; border-radius: 99px;
          font-size: 11px; font-weight: 700; background: var(--track); color: var(--ink2); white-space: nowrap; }
  .pill.green { background: var(--greenSoft); color: var(--green); }
  .pill.orange { background: var(--orangeSoft); color: var(--orange); }
  .pill.lav { background: var(--lavSoft); color: var(--lav); }
  .bar { height: 8px; border-radius: 99px; background: var(--track); overflow: hidden; }
  .bar > i { display:block; height:100%; border-radius: 99px; }
  .banner { border-radius: 22px; padding: 14px 16px; margin: 14px 0; font-weight: 600;
            display:flex; align-items:center; gap: 12px; }
  .banner .big { font-size: 26px; }
  .player { border-radius: 22px; padding: 14px; position: relative; background: var(--track); }
  .player.lead { outline: 2px solid var(--green); }
  .avatar { width: 34px; height: 34px; border-radius: 50%; display:flex; align-items:center; justify-content:center;
            color:#fff; font-weight: 700; font-size: 15px; flex: 0 0 34px; }
  .who { display:flex; align-items:center; gap: 8px; font-weight: 650; font-size: 14px; min-width: 0; }
  .who span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .big { font-size: 32px; font-weight: 700; letter-spacing: -.8px; line-height: 1.1; }
  .kv { display:grid; grid-template-columns: 1fr auto; gap: 4px 8px; font-size: 12px; margin-top: 10px; }
  .kv b { font-weight: 650; text-align: right; }
  .kv span { color: var(--ink2); }
  .stats { display:grid; grid-template-columns: repeat(3, 1fr); gap: 8px; }
  .stat { background: var(--track); border-radius: 16px; padding: 10px; }
  .stat b { display:block; font-size: 18px; letter-spacing: -.3px; }
  .stat span { font-size: 11px; color: var(--ink2); }
  .badges { display:flex; flex-wrap: wrap; gap: 4px; margin-top: 10px; }
  .badges .pill { font-size: 10px; padding: 3px 7px; background: rgba(255,255,255,.55); }
  @media (prefers-color-scheme: dark) { .badges .pill { background: rgba(0,0,0,.25); } }
  label { font-size: 12px; color: var(--ink2); display:block; margin-bottom: 4px; }
  input { width:100%; font: inherit; font-size: 16px; color: var(--ink); background: var(--track); border: 0;
          border-radius: 14px; padding: 12px; -webkit-appearance: none; appearance: none; min-height: 46px; }
  input[type=date] { display:block; }
  button, .btn { font: inherit; font-weight: 650; border: 0; border-radius: 99px; padding: 14px 18px;
           background: var(--ink); color: var(--paper); width: 100%; cursor: pointer; text-align:center; text-decoration:none; display:block; }
  button.ghost { background: var(--track); color: var(--ink); width:auto; padding: 8px 12px; font-size: 13px; }
  button.step { background: var(--track); color: var(--ink); padding: 0; width: 46px; flex: 0 0 46px; font-size: 20px; }
  .list > div { display:flex; justify-content:space-between; align-items:center; padding: 10px 0; border-top: 1px solid var(--hair); font-size: 14px; }
  .msg { padding: 9px 13px; border-radius: 18px; background: var(--track); margin: 6px 0; max-width: 82%; width: fit-content; }
  .msg.me { margin-left:auto; background: var(--orangeSoft); }
  .msg small { display:block; color: var(--ink3); font-size: 10px; margin-top: 2px; }
  .reacts { display:flex; gap: 6px; margin: 8px 0; overflow-x: auto; }
  .reacts button { width:auto; flex: 0 0 auto; padding: 8px 12px; font-size: 13px; background: var(--track); color: var(--ink); }
  details summary { cursor: pointer; list-style: none; }
  details summary::-webkit-details-marker { display: none; }
  ol { padding-left: 20px; margin: 10px 0; }
  ol li { margin: 8px 0; font-size: 14px; }
  code { background: var(--track); border-radius: 6px; padding: 1px 5px; font-size: 12px; }
  .copy { display:flex; gap: 8px; margin: 8px 0; }
  .copy input { font-size: 12px; min-height: 40px; }
  .copy button { width: auto; padding: 10px 14px; font-size: 13px; }
  #toast { position: fixed; left: 50%; bottom: calc(env(safe-area-inset-bottom) + 20px); transform: translateX(-50%);
           background: var(--ink); color: var(--paper); padding: 10px 16px; border-radius: 99px; font-weight: 600;
           font-size: 14px; opacity: 0; transition: opacity .2s; pointer-events: none; }
  #err { color: var(--rose); }
  svg text { fill: var(--ink3); font-size: 10px; }
</style>
</head>
<body>
<main><div id="app"><p class="muted">Loading…</p></div></main>
<div id="toast"></div>
<script>
const ID = ${JSON.stringify(id)};
const KEY = "dialed-" + ID;
const token = new URLSearchParams(location.hash.slice(1)).get("t") || localStorage.getItem(KEY) || "";
if (token) { try { localStorage.setItem(KEY, token); } catch {} }
const api = (path, opts = {}) => fetch("/api/challenges/" + ID + path, {
  ...opts, headers: { "authorization": "Bearer " + token, "content-type": "application/json" }
}).then(async r => { const b = await r.json(); if (!r.ok) throw new Error(b.error || r.status); return b; });

let state = null;
const el = (tag, attrs = {}, ...kids) => {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (k.startsWith("on")) n.addEventListener(k.slice(2), v);
    else if (k === "style" && typeof v === "object") Object.assign(n.style, v);
    else n.setAttribute(k, v);
  }
  for (const k of kids.flat()) if (k !== null && k !== undefined && k !== false) n.append(k instanceof Node ? k : document.createTextNode(String(k)));
  return n;
};
const toast = (t) => { const e = document.getElementById("toast"); e.textContent = t; e.style.opacity = 1; setTimeout(() => e.style.opacity = 0, 1800); };
const DAY = 864e5;
const todayKey = () => { const d = new Date(); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 10); };
const t = (key) => Date.parse(key + "T12:00:00");
const f1 = (n) => (Math.round(n * 10) / 10).toFixed(1);
const signed = (n, unit = " lb") => (n > 0 ? "−" : n < 0 ? "+" : "±") + f1(Math.abs(n)) + unit;
const niceDate = (key) => new Date(t(key)).toLocaleDateString(undefined, { month: "short", day: "numeric" });
const ago = (iso) => {
  if (!iso) return "";
  const m = Math.round((Date.now() - Date.parse(iso)) / 6e4);
  if (m < 60) return m <= 1 ? "just now" : m + " min ago";
  const h = Math.round(m / 60); if (h < 24) return h + "h ago";
  return Math.round(h / 24) + "d ago";
};
const COLORS = { owner: "var(--orange)", friend: "var(--lav)" };
const SOFT = { owner: "var(--orangeSoft)", friend: "var(--lavSoft)" };

/** Everything we know about one side. */
function side(role) {
  const c = state.challenge;
  const series = state.weighins.filter(w => w.role === role).sort((a, b) => a.date < b.date ? -1 : 1);
  const startExplicit = role === "owner" ? c.ownerStart : c.friendStart;
  const start = startExplicit ?? series[0]?.pounds ?? null;
  const last = series[series.length - 1];
  const current = last?.pounds ?? null;
  const lost = start != null && current != null ? start - current : null;
  const pct = lost != null && start ? lost / start * 100 : null;
  // Trend: least squares over the last 21 days of weigh-ins (lb/day).
  const recent = series.filter(w => t(w.date) >= Date.now() - 21 * DAY);
  let slope = null;
  if (recent.length >= 2) {
    const xs = recent.map(w => t(w.date) / DAY), ys = recent.map(w => w.pounds);
    const mx = xs.reduce((a, b) => a + b) / xs.length, my = ys.reduce((a, b) => a + b) / ys.length;
    const den = xs.reduce((s, x) => s + (x - mx) ** 2, 0);
    if (den > 0) slope = xs.reduce((s, x, i) => s + (x - mx) * (ys[i] - my), 0) / den;
    if (slope != null) slope = Math.max(-0.43, Math.min(0.43, slope)); // ±3 lb/week sanity clamp
  }
  const daysLeft = Math.max(0, Math.round((t(c.endDate) - t(todayKey())) / DAY));
  const projected = current != null && slope != null ? current + slope * daysLeft : null;
  const projLost = projected != null && start != null ? start - projected : null;
  // Weigh-in streak: consecutive days ending today or yesterday.
  const have = new Set(series.map(w => w.date));
  let streak = 0; let d = new Date(t(todayKey()));
  if (!have.has(todayKey())) d = new Date(d - DAY);
  while (have.has(new Date(d).toISOString().slice(0, 10))) { streak++; d = new Date(d - DAY); }
  const auto = series.some(w => w.source === "scale");
  const stats = state.stats?.[role] || {};
  const goal = role === "owner" ? stats.goalLossLbs : stats.goalLossLbs;
  return { role, name: role === "owner" ? c.ownerName : c.friendName, series, start, current, lost, pct,
           weekly: slope != null ? -slope * 7 : null, projected, projLost, streak, last, auto, stats, goal };
}

function badges(s) {
  const out = [];
  if (s.lost != null) for (const lb of [20, 15, 10, 5, 1]) if (s.lost >= lb) { out.push("🏅 " + lb + " lb down"); break; }
  if (s.pct != null) for (const p of [5, 3, 2, 1]) if (s.pct >= p) { out.push("⚡ " + p + "%"); break; }
  if (s.streak >= 7) out.push("🔥 " + s.streak + "-day streak"); else if (s.streak >= 3) out.push("🔥 " + s.streak + " days");
  if (s.weekly != null && s.weekly >= 1) out.push("📉 " + f1(s.weekly) + " lb/wk");
  if (s.auto) out.push("⚖️ Auto-sync");
  return out;
}

function leaderInfo(a, b) {
  const byPounds = state.stats?.owner?.scoring === "pounds";
  const score = s => byPounds ? s.lost : s.pct;
  const sa = score(a), sb = score(b);
  if (sa == null && sb == null) return { leader: null, text: "First weigh-in sets the pace." };
  if (sb == null || (sa != null && sa > sb)) return { leader: a, margin: (sa ?? 0) - (sb ?? 0), byPounds };
  if (sa == null || sb > sa) return { leader: b, margin: (sb ?? 0) - (sa ?? 0), byPounds };
  return { leader: null, text: "Dead even. Tomorrow's weigh-in breaks the tie." };
}

function chart(a, b) {
  const c = state.challenge;
  const W = 500, H = 190, L = 30, R = 10, T = 14, B = 22;
  const x0 = t(c.startDate), x1 = Math.max(t(c.endDate), x0 + DAY);
  const pts = s => s.start == null ? [] : s.series.map(w => [t(w.date), (s.start - w.pounds) / s.start * 100]);
  const pa = pts(a), pb = pts(b);
  const proj = s => s.projected != null && s.start ? [[t(s.series[s.series.length - 1].date), (s.start - s.series[s.series.length - 1].pounds) / s.start * 100], [x1, (s.start - s.projected) / s.start * 100]] : [];
  const ys = [...pa, ...pb, ...proj(a), ...proj(b)].map(p => p[1]);
  if (pa.length + pb.length < 2) return el("p", { class: "muted" }, "The race chart fills in after a couple of weigh-ins.");
  const y0 = Math.min(0, ...ys), y1 = Math.max(1, ...ys) * 1.1;
  const X = v => L + (v - x0) / (x1 - x0) * (W - L - R), Y = v => T + (1 - (v - y0) / (y1 - y0)) * (H - T - B);
  const poly = (p, color, dash) => p.length ? '<polyline fill="none" stroke="' + color + '" stroke-width="' + (dash ? 2 : 3.5) + '"' +
    (dash ? ' stroke-dasharray="5 5" opacity=".7"' : '') + ' stroke-linecap="round" stroke-linejoin="round" points="' +
    p.map(q => X(q[0]).toFixed(1) + "," + Y(q[1]).toFixed(1)).join(" ") + '"/>' : "";
  const dots = (p, color) => p.length ? '<circle cx="' + X(p[p.length-1][0]) + '" cy="' + Y(p[p.length-1][1]) + '" r="5" fill="' + color + '" stroke="var(--surface)" stroke-width="2"/>' : "";
  const tx = X(Math.min(x1, Date.now()));
  let grid = "";
  const stepY = y1 - y0 > 8 ? 4 : y1 - y0 > 4 ? 2 : 1;
  for (let v = Math.ceil(y0 / stepY) * stepY; v <= y1; v += stepY) {
    grid += '<line x1="' + L + '" x2="' + (W - R) + '" y1="' + Y(v) + '" y2="' + Y(v) + '" stroke="currentColor" stroke-opacity="' + (v === 0 ? .18 : .06) + '"/>' +
            '<text x="' + (L - 6) + '" y="' + (Y(v) + 3) + '" text-anchor="end">' + v + '%</text>';
  }
  const svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" width="100%" role="img" aria-label="Percent lost over time" style="color:var(--ink)">' + grid +
    '<line x1="' + tx + '" x2="' + tx + '" y1="' + T + '" y2="' + (H - B) + '" stroke="currentColor" stroke-opacity=".15" stroke-dasharray="2 4"/>' +
    '<text x="' + tx + '" y="' + (H - 6) + '" text-anchor="middle">today</text>' +
    '<text x="' + L + '" y="' + (H - 6) + '">' + niceDate(c.startDate) + '</text>' +
    '<text x="' + (W - R) + '" y="' + (H - 6) + '" text-anchor="end">' + niceDate(c.endDate) + '</text>' +
    poly(proj(a), COLORS[a.role], true) + poly(proj(b), COLORS[b.role], true) +
    poly(pa, COLORS[a.role]) + poly(pb, COLORS[b.role]) + dots(pa, COLORS[a.role]) + dots(pb, COLORS[b.role]) + '</svg>';
  const box = el("div"); box.innerHTML = svg;
  box.append(el("div", { class: "between tiny", style: { marginTop: "6px" } },
    el("span", {}, el("span", { style: { color: COLORS[a.role] } }, "● "), a.name, "   ", el("span", { style: { color: COLORS[b.role] } }, "● "), b.name),
    el("span", {}, "dashed = on pace for")));
  return box;
}

function playerCard(s, isLead, isMe) {
  const initial = (s.name || "?").trim().charAt(0).toUpperCase();
  return el("div", { class: "player" + (isLead ? " lead" : ""), style: { background: SOFT[s.role] } },
    el("div", { class: "between" },
      el("div", { class: "who" }, el("div", { class: "avatar", style: { background: COLORS[s.role] } }, initial), el("span", {}, s.name + (isMe ? " · you" : ""))),
      isLead ? el("span", { class: "pill green" }, "👑") : null),
    el("div", { class: "big", style: { marginTop: "10px" } }, s.pct == null ? "—" : f1(s.pct) + "%"),
    el("div", { class: "muted" }, s.lost == null ? "Weigh in to start" : signed(s.lost) + " total"),
    el("div", { class: "kv" },
      el("span", {}, "Start"), el("b", {}, s.start != null ? f1(s.start) : "—"),
      el("span", {}, "Now"), el("b", {}, s.current != null ? f1(s.current) : "—"),
      el("span", {}, "Pace"), el("b", {}, s.weekly != null ? (s.weekly >= 0 ? "−" : "+") + f1(Math.abs(s.weekly)) + "/wk" : "—"),
      el("span", {}, "By the end"), el("b", {}, s.projLost != null ? signed(s.projLost) : "—"),
      el("span", {}, "Last"), el("b", {}, s.last ? niceDate(s.last.date) + (s.last.source === "scale" ? " ⚖️" : "") : "—")),
    s.goal ? el("div", { style: { marginTop: "10px" } },
      el("div", { class: "between tiny" }, el("span", {}, "Goal −" + f1(s.goal) + " lb"), el("span", {}, Math.round(Math.max(0, Math.min(1, (s.lost || 0) / s.goal)) * 100) + "%")),
      el("div", { class: "bar", style: { marginTop: "4px" } }, el("i", { style: { width: Math.max(2, Math.min(100, (s.lost || 0) / s.goal * 100)) + "%", background: COLORS[s.role] } }))) : null,
    el("div", { class: "badges" }, badges(s).map(b => el("span", { class: "pill" }, b))));
}

function statsCard(s, isMe) {
  const st = s.stats || {};
  const items = [];
  if (st.stepsAvg7 != null) items.push([Math.round(st.stepsAvg7).toLocaleString(), "steps/day (7d)"]);
  if (st.stepsToday != null) items.push([Math.round(st.stepsToday).toLocaleString(), "steps today"]);
  if (st.workoutsWeek != null) items.push([st.workoutsWeek, "workouts this week"]);
  if (st.workoutsTotal != null) items.push([st.workoutsTotal, "workouts total"]);
  if (st.proteinDays7 != null) items.push([st.proteinDays7 + "/7", "protein goal days"]);
  if (st.waterAvg7 != null) items.push([Math.round(st.waterAvg7) + " oz", "water/day (7d)"]);
  if (s.streak) items.push([s.streak, "day weigh-in streak"]);
  if (items.length < (isMe ? 2 : 1)) return null;
  return el("div", { class: "card" },
    el("div", { class: "between" }, el("h2", {}, (isMe ? "Your" : s.name + "'s") + " week"),
      st.updatedAt ? el("span", { class: "tiny" }, "updated " + ago(st.updatedAt)) : null),
    st.goalDayName ? el("p", { class: "muted", style: { margin: "-6px 0 10px" } }, "Training for: " + st.goalDayName + (st.goalDayDate ? " · " + niceDate(st.goalDayDate) : "")) : null,
    el("div", { class: "stats" }, items.slice(0, 6).map(([v, k]) => el("div", { class: "stat" }, el("b", {}, v), el("span", {}, k)))));
}

function autoSyncCard(me) {
  const link = location.origin + "/api/challenges/" + ID + "/scale?t=" + token;
  const ios = /iPhone|iPad|iPod/.test(navigator.userAgent);
  const android = /Android/.test(navigator.userAgent);
  const copy = () => el("div", { class: "copy" },
    el("input", { value: link, readonly: "readonly", onclick: e => e.target.select() }),
    el("button", { onclick: async () => { try { await navigator.clipboard.writeText(link); toast("Link copied"); } catch { toast("Press and hold to copy"); } } }, "Copy"));
  const iosSteps = el("div", {},
    el("h2", { style: { marginTop: "6px" } }, "iPhone: weigh in automatically (2 min, once)"),
    el("ol", {},
      el("li", {}, "In the ", el("b", {}, "Fitdays"), " app: ", el("b", {}, "Me → Apple Health"), " (or Settings → Connect) → turn on and allow ", el("b", {}, "Weight"), "."),
      el("li", {}, "Open ", el("b", {}, "Shortcuts"), " → ", el("b", {}, "Automation"), " → ", el("b", {}, "+"), " → ", el("b", {}, "Time of Day"), " → 10:00 AM, Daily → ", el("b", {}, "Run Immediately"), " → Next → ", el("b", {}, "New Blank Automation"), "."),
      el("li", {}, "Add ", el("b", {}, "Find Health Samples"), ": Type ", el("b", {}, "Weight"), ", add filter ", el("b", {}, "Start Date is today"), ", Sort by Start Date, ", el("b", {}, "Latest First"), ", Limit ", el("b", {}, "1"), "."),
      el("li", {}, "Add ", el("b", {}, "Get Contents of URL"), " and paste your link:", copy(),
        "Tap the arrow → Method ", el("b", {}, "POST"), " → Request Body ", el("b", {}, "JSON"), " → Add new field → ", el("b", {}, "Text"),
        ", key ", el("code", {}, "weight"), ", value: tap ", el("b", {}, "Select Variable → Health Samples"), "."),
      el("li", {}, "Tap ", el("b", {}, "Done"), ". Optional: duplicate it for 8 PM to catch late weigh-ins.")),
    el("p", { class: "tiny" }, "Every morning after you step on the scale, your weight lands here by itself. Run it once now to test — it'll show ⚖️ next to your weigh-in."));
  const androidSteps = el("div", {},
    el("h2", { style: { marginTop: "6px" } }, "Android"),
    el("ol", {},
      el("li", {}, "In ", el("b", {}, "Fitdays"), ": Me → connect ", el("b", {}, "Health Connect / Google Fit"), " so your history is saved."),
      el("li", {}, "Add this page to your home screen: Chrome ", el("b", {}, "⋮ → Add to Home screen"), ". After you step on the scale, open it — your last weight is pre-filled; nudge it and tap Save (5 seconds)."),
      el("li", {}, "Using an automation app (MacroDroid/Tasker)? Have it send an HTTP POST with JSON ", el("code", {}, '{"weight":"185.2"}'), " to:", copy())));
  const body = el("div", {}, ios ? iosSteps : android ? androidSteps : [iosSteps, androidSteps]);
  if (me.auto) {
    const det = el("details", {}, el("summary", {}, el("div", { class: "between" },
      el("div", {}, el("b", {}, "⚖️ Auto weigh-ins are on"), el("div", { class: "tiny" }, "Last from your scale: " + niceDate(me.series.filter(w => w.source === "scale").pop().date))),
      el("span", { class: "pill green" }, "Connected"))), body);
    return el("div", { class: "card" }, det);
  }
  return el("div", { class: "card", style: { background: "var(--skySoft)" } },
    el("div", { class: "between" }, el("h2", { style: { margin: 0 } }, "⚖️ Sync your scale"), el("span", { class: "pill" }, "set once")),
    el("p", { class: "muted", style: { margin: "6px 0 0" } }, "Step on your scale and your weigh-in posts here automatically — no typing."),
    body);
}

function weighInCard(me) {
  const date = el("input", { type: "date", value: todayKey(), max: todayKey() });
  const lbs = el("input", { type: "number", step: "0.1", inputmode: "decimal", value: me.current != null ? f1(me.current) : "", placeholder: "185.0" });
  const nudge = d => { const v = parseFloat(lbs.value || (me.current ?? 0)); lbs.value = f1((isFinite(v) ? v : 0) + d); };
  return el("div", { class: "card" },
    el("h2", {}, "Log a weigh-in"),
    el("div", { class: "row" }, el("div", {}, el("label", {}, "Date"), date)),
    el("div", { style: { height: "10px" } }),
    el("label", {}, "Pounds"),
    el("div", { class: "row", style: { gap: "8px" } },
      el("button", { class: "step", onclick: () => nudge(-0.2), "aria-label": "minus 0.2" }, "−"),
      lbs,
      el("button", { class: "step", onclick: () => nudge(0.2), "aria-label": "plus 0.2" }, "+")),
    el("div", { style: { height: "12px" } }),
    el("button", { onclick: async () => {
      const p = parseFloat(lbs.value);
      if (!(p > 50 && p < 1000)) return lbs.focus();
      state = await api("/weighins", { method: "PUT", body: JSON.stringify({ weighins: [{ date: date.value, pounds: p }] }) });
      toast("Saved " + f1(p) + " lb"); render();
    } }, "Save weigh-in"),
    me.series.length ? el("details", { style: { marginTop: "12px" } }, el("summary", { class: "muted" }, "Your weigh-ins (" + me.series.length + ") ›"),
      el("div", { class: "list" }, me.series.slice().reverse().map(w =>
        el("div", {}, el("span", {}, niceDate(w.date) + (w.source === "scale" ? " ⚖️" : "")), el("span", {}, f1(w.pounds) + " lb ",
          el("button", { class: "ghost", onclick: async () => { state = await api("/weighins/" + w.date, { method: "DELETE" }); render(); } }, "Remove")))))) : null);
}

// Weekly side bets: one metric, Monday–Sunday, a stake.
const BET_METRICS = {
  steps: ["👟", "Most steps", true], miles: ["🚶", "Most miles", true], workouts: ["🏋️", "Most workouts", true],
  prs: ["🏆", "Most PRs", true], skippedDays: ["📅", "Fewest skipped days", false], proteinDays: ["🥩", "Most protein days", true],
};
const STAKES = ["Loser buys wings 🍗", "Loser does 50 burpees", "Loser buys coffee for a week ☕️",
                "Loser picks the next cheat meal", "Loser posts a gym selfie 📸", "Loser buys the next round 🍺"];
const mondayKey = (key = todayKey()) => { const d = new Date(t(key)); d.setDate(d.getDate() - (d.getDay() + 6) % 7); return d.toISOString().slice(0, 10); };
const weekOver = (b) => t(todayKey()) >= t(b.week) + 7 * DAY - 12 * 36e5;
const betScore = (b, role) => role === "owner" ? b.ownerScore : b.friendScore;
const fmtScore = (metric, v) => v == null ? "—" : metric === "miles" ? f1(v) : Math.round(v).toLocaleString();
function betWinner(b) {
  const o = b.ownerScore, f = b.friendScore;
  if (b.status !== "active" || !weekOver(b) || o == null || f == null) return null;
  if (Math.abs(o - f) < 1e-4) return "tie";
  return (o > f) === BET_METRICS[b.metric][2] ? "owner" : "friend";
}
function owesLine(b, winner, me, them) {
  if (!winner || winner === "tie") return "Dead even — nobody owes anybody.";
  const loser = winner === me.role ? them.name : "You";
  const stake = b.stake.trim();
  if (/^loser /i.test(stake)) {
    let rest = stake.slice(6);
    if (loser === "You") rest = rest.replace(/^(\\S+)/, w => ({ does: "do", has: "have", is: "are", goes: "go" })[w] || w.replace(/ies$/, "y").replace(/(ch|sh|ss)es$/, "$1").replace(/([^s])s$/, "$1"));
    return loser + " " + rest;
  }
  return loser === "You" ? "You owe " + them.name + ": " + stake : them.name + " owes you: " + stake;
}

function betsCard(me, them) {
  const bets = state.bets || [];
  const week = mondayKey();
  const cur = bets.find(b => b.week === week && (b.status === "proposed" || b.status === "active"));
  const patchBet = async (b, body) => { state = await api("/bets/" + b.id, { method: "PATCH", body: JSON.stringify(body) }); render(); };
  const body = [];
  if (cur) {
    const [icon, title] = BET_METRICS[cur.metric] || ["🎲", cur.metric];
    body.push(el("div", { class: "between" }, el("b", {}, icon + " " + title), el("span", { class: "pill orange" }, cur.stake)));
    if (cur.status === "proposed" && cur.proposer !== me.role) {
      body.push(el("p", { class: "muted" }, them.name + " wants this bet for the week. You in?"),
        el("div", { class: "row" },
          el("button", { onclick: () => patchBet(cur, { action: "accept" }) }, "Accept 🤝"),
          el("button", { class: "ghost", style: { width: "100%" }, onclick: () => patchBet(cur, { action: "decline" }) }, "Pass")));
    } else if (cur.status === "proposed") {
      body.push(el("p", { class: "muted" }, "Waiting for " + them.name + " to accept."),
        el("button", { class: "ghost", onclick: () => patchBet(cur, { action: "cancel" }) }, "Cancel bet"));
    } else {
      const mine = betScore(cur, me.role), theirs = betScore(cur, them.role);
      const max = Math.max(1, mine || 0, theirs || 0);
      const bar = (s, v) => el("div", { style: { marginTop: "10px" } },
        el("div", { class: "between tiny" }, el("span", {}, s.name), el("b", {}, fmtScore(cur.metric, v))),
        el("div", { class: "bar", style: { marginTop: "4px" } }, el("i", { style: { width: Math.max(2, (v || 0) / max * 100) + "%", background: COLORS[s.role] } })));
      const input = el("input", { type: "number", inputmode: "decimal", step: cur.metric === "miles" ? "0.1" : "1", placeholder: "Your total this week", value: mine ?? "" });
      const daysLeft = Math.max(0, Math.round((t(week) + 7 * DAY - t(todayKey())) / DAY));
      body.push(bar(me, mine), bar(them, theirs),
        el("p", { class: "tiny" }, daysLeft + (daysLeft === 1 ? " day" : " days") + " left · update your number any time"),
        el("div", { class: "row" }, input, el("button", { style: { flex: "0 0 84px" }, onclick: async () => {
          const v = parseFloat(input.value); if (!(v >= 0)) return input.focus();
          await patchBet(cur, { score: v }); toast("Saved");
        } }, "Save")));
    }
  } else {
    const metric = el("select", { style: { width: "100%", font: "inherit", fontSize: "16px", padding: "12px", borderRadius: "14px", border: "0", background: "var(--track)", color: "var(--ink)" } },
      Object.entries(BET_METRICS).map(([k, [icon, title]]) => el("option", { value: k }, icon + " " + title)));
    const stake = el("input", { list: "stakes", placeholder: "Loser buys wings 🍗", maxlength: "80" });
    body.push(el("p", { class: "muted", style: { marginTop: 0 } }, "A mini-battle for this week, on top of the race."),
      el("label", {}, "Battle"), metric, el("div", { style: { height: "10px" } }),
      el("label", {}, "Stakes"), stake, el("datalist", { id: "stakes" }, STAKES.map(s => el("option", { value: s }))),
      el("div", { style: { height: "12px" } }),
      el("button", { onclick: async () => {
        state = await api("/bets", { method: "POST", body: JSON.stringify({ week, metric: metric.value, stake: stake.value.trim() || STAKES[0] }) });
        toast("Bet sent to " + them.name); render();
      } }, "Propose bet 🎲"));
  }
  const settled = bets.filter(b => b.status === "active" && b.week < week && betWinner(b));
  if (settled.length) {
    body.push(el("details", { style: { marginTop: "12px" } }, el("summary", { class: "muted" }, "Past bets (" + settled.length + ") ›"),
      el("div", { class: "list" }, settled.map(b => {
        const w = betWinner(b);
        return el("div", {}, el("span", {}, (w === me.role ? "🏆 " : w === "tie" ? "🤝 " : "😬 ") + owesLine(b, w, me, them),
            el("div", { class: "tiny" }, BET_METRICS[b.metric]?.[1] + " · " + fmtScore(b.metric, betScore(b, me.role)) + " vs " + fmtScore(b.metric, betScore(b, them.role)))),
          w === "tie" ? null : el("button", { class: "ghost", onclick: () => patchBet(b, { action: b.paid ? "unpaid" : "paid" }) }, b.paid ? "Paid ✓" : "Mark paid"));
      }))));
  }
  return el("div", { class: "card" }, el("h2", {}, "🎲 Side bet"), body);
}

function chatCard(me, them) {
  const c = state.challenge;
  const text = el("input", { maxlength: "280", placeholder: "Say something…", enterkeyhint: "send" });
  const send = async (v) => {
    const msg = (v ?? text.value).trim(); if (!msg) return;
    state = await api("/messages", { method: "POST", body: JSON.stringify({ text: msg }) }); render();
  };
  text.addEventListener("keydown", e => { if (e.key === "Enter") send(); });
  const quick = ["💪 Let's go", "🔥 Nice work", "😤 Catching up", "👀 Weigh in!", "🥗 Eating clean today"];
  return el("div", { class: "card" },
    el("h2", {}, "Trash talk"),
    state.messages.length ? state.messages.slice(-30).map(m => el("div", { class: "msg" + (m.role === me.role ? " me" : "") },
      m.text, el("small", {}, (m.role === "owner" ? c.ownerName : c.friendName) + " · " + ago(m.createdAt)))) :
      el("p", { class: "muted" }, "No smack talk yet. Start it."),
    el("div", { class: "reacts" }, quick.map(q => el("button", { onclick: () => send(q) }, q))),
    el("div", { class: "row" }, text, el("button", { style: { flex: "0 0 84px" }, onclick: () => send() }, "Send")));
}

function render() {
  const app = document.getElementById("app");
  app.replaceChildren();
  const c = state.challenge;
  const meRole = state.role, themRole = meRole === "owner" ? "friend" : "owner";
  const me = side(meRole), them = side(themRole);
  const owner = side("owner"), friend = side("friend");
  const total = Math.max(1, Math.round((t(c.endDate) - t(c.startDate)) / DAY));
  const daysLeft = Math.max(0, Math.round((t(c.endDate) - t(todayKey())) / DAY));
  const elapsed = Math.min(1, Math.max(0, 1 - daysLeft / total));
  const lead = leaderInfo(owner, friend);

  app.append(
    el("div", { class: "eyebrow" }, "Weight-loss challenge"),
    el("h1", {}, c.ownerName + " vs. " + c.friendName),
    el("div", { class: "between muted" }, el("span", {}, niceDate(c.startDate) + " – " + niceDate(c.endDate)), el("b", {}, daysLeft + " days left")),
    el("div", { class: "bar", style: { marginTop: "8px" } }, el("i", { style: { width: Math.max(2, elapsed * 100) + "%", background: "var(--ink)" } })),
    el("div", { class: "banner", style: { background: lead.leader ? SOFT[lead.leader.role] : "var(--track)" } },
      el("span", { class: "big" }, lead.leader ? (lead.leader.role === meRole ? "🏆" : "⏱️") : "🤝"),
      el("div", {}, lead.leader
        ? (lead.leader.role === meRole ? "You're leading by " : lead.leader.name + " leads by ") + (lead.byPounds ? f1(lead.margin) + " lb" : f1(lead.margin) + "%")
        : lead.text,
        el("div", { class: "tiny", style: { fontWeight: 500 } }, lead.leader && lead.leader.role !== meRole
          ? "≈ " + f1((lead.byPounds ? lead.margin : lead.margin / 100 * (me.start || 0)) || 0) + " lb to catch up. One good day closes a lot of that."
          : lead.leader ? "Keep weighing in daily to protect the lead." : "")))
  );

  app.append(el("div", { class: "card" },
    el("div", { class: "row" }, playerCard(me, lead.leader?.role === me.role, true), playerCard(them, lead.leader?.role === them.role, false)),
    el("div", { style: { height: "14px" } }),
    chart(me, them)));

  if (!me.series.some(w => w.date === todayKey())) {
    app.append(el("div", { class: "card", style: { background: "var(--orangeSoft)" } },
      el("b", {}, "No weigh-in yet today"), el("div", { class: "muted" }, me.auto ? "Your scale syncs this automatically after you step on it." : "Step on the scale and log it below — it keeps your streak alive.")));
  }

  app.append(betsCard(me, them), autoSyncCard(me), weighInCard(me));
  const theirs = statsCard(them, false), mine = statsCard(me, true);
  if (theirs) app.append(theirs);
  if (mine) app.append(mine);
  app.append(chatCard(me, them),
    el("p", { class: "tiny", style: { textAlign: "center" } }, "Tip: Share → Add to Home Screen to keep this one tap away."));
}

async function load() {
  try { state = await api(""); render(); }
  catch (e) {
    document.getElementById("app").replaceChildren(el("p", { id: "err" },
      token ? "Couldn't load the challenge (" + e.message + "). Ask for a fresh invite link." : "This link is missing its invite code. Ask for a fresh invite link."));
  }
}
load();
document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") load(); });
setInterval(() => { if (document.visibilityState === "visible" && !document.activeElement?.matches("input")) load(); }, 60000);
</script>
</body>
</html>`;
}
