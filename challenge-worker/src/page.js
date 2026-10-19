// The page your friend opens from the invite link. Plain HTML + JS, no
// build step. The token lives in the URL #fragment and is sent only as a
// Bearer header to this same server.

export function page(id) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#F6F5F1">
<meta name="robots" content="noindex">
<title>Weight-Loss Challenge</title>
<style>
  :root {
    --paper:#F6F5F1; --surface:#FFFFFF; --ink:#151619; --ink2:#6B6C72; --ink3:#A1A1A6;
    --track:rgba(0,0,0,.06); --hair:rgba(0,0,0,.08);
    --green:#4CB868; --greenSoft:#DDF3E1; --orange:#F59A4C; --orangeSoft:#FFE7D3;
    --rose:#EE7C8E; --lav:#A88BEB; --sky:#5DB4F0;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --paper:#0E0F11; --surface:#1A1B1F; --ink:#F2F2F3; --ink2:#A3A4AA; --ink3:#6B6B72;
      --track:rgba(255,255,255,.09); --hair:rgba(255,255,255,.1);
      --greenSoft:#1C3324; --orangeSoft:#3A2718;
    }
  }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--paper); color:var(--ink);
         font: 15px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
  main { max-width: 520px; margin: 0 auto; padding: 20px 16px 48px; }
  h1 { font-size: 30px; letter-spacing: -.6px; margin: 8px 0 2px; }
  .sub { color: var(--ink2); margin: 0 0 16px; }
  .card { background: var(--surface); border: 1px solid var(--hair); border-radius: 24px;
          padding: 16px; margin-bottom: 14px; box-shadow: 0 4px 16px rgba(0,0,0,.04); }
  .row { display:flex; gap:12px; }
  .row > * { flex:1; }
  .side { border-radius: 18px; padding: 14px; background: var(--track); }
  .side.lead { background: var(--greenSoft); }
  .name { font-weight: 600; font-size: 14px; }
  .big { font-size: 30px; font-weight: 650; letter-spacing: -.5px; }
  .muted { color: var(--ink2); font-size: 12px; }
  .pill { display:inline-block; padding: 3px 9px; border-radius: 99px; font-size: 11px; font-weight: 700;
          background: var(--green); color: #fff; }
  label { font-size: 12px; color: var(--ink2); display:block; margin-bottom: 4px; }
  input, textarea { width:100%; font: inherit; color: var(--ink); background: var(--track); border: 0;
                    border-radius: 14px; padding: 12px; }
  button { font: inherit; font-weight: 650; border: 0; border-radius: 99px; padding: 13px 18px;
           background: var(--ink); color: var(--paper); width: 100%; cursor: pointer; }
  button.ghost { background: var(--track); color: var(--ink); width:auto; padding: 6px 12px; font-size: 12px; }
  h2 { font-size: 16px; margin: 0 0 10px; }
  .list div { display:flex; justify-content:space-between; padding: 8px 0; border-top: 1px solid var(--hair); }
  .msg { padding: 8px 12px; border-radius: 16px; background: var(--track); margin: 6px 0; max-width: 85%; }
  .msg.me { margin-left:auto; background: var(--orangeSoft); }
  .msg small { display:block; color: var(--ink3); font-size: 10px; }
  #err { color: var(--rose); }
  svg text { fill: var(--ink3); font-size: 10px; }
</style>
</head>
<body>
<main>
  <div id="app"><p class="muted">Loading…</p></div>
</main>
<script>
const ID = ${JSON.stringify(id)};
const token = new URLSearchParams(location.hash.slice(1)).get("t") || localStorage.getItem("dialed-" + ID) || "";
if (token) localStorage.setItem("dialed-" + ID, token);
const api = (path, opts = {}) => fetch("/api/challenges/" + ID + path, {
  ...opts, headers: { "authorization": "Bearer " + token, "content-type": "application/json" }
}).then(async r => { const b = await r.json(); if (!r.ok) throw new Error(b.error || r.status); return b; });

let state = null;
const el = (tag, attrs = {}, ...kids) => {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) k.startsWith("on") ? n.addEventListener(k.slice(2), v) : n.setAttribute(k, v);
  for (const k of kids.flat()) n.append(k instanceof Node ? k : document.createTextNode(String(k)));
  return n;
};
const today = () => { const d = new Date(); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 10); };
const fmt = (n) => (Math.round(n * 10) / 10).toFixed(1);

function side(role) {
  const c = state.challenge;
  const mine = state.weighins.filter(w => w.role === role);
  const start = (role === "owner" ? c.ownerStart : c.friendStart) ?? mine[0]?.pounds ?? null;
  const current = mine.length ? mine[mine.length - 1].pounds : null;
  const lost = start != null && current != null ? start - current : null;
  return { role, name: role === "owner" ? c.ownerName : c.friendName, start, current, lost,
           pct: lost != null && start ? lost / start * 100 : null, series: mine };
}

function chart(a, b) {
  const W = 480, H = 160, P = 22;
  const all = [...a.series, ...b.series];
  if (all.length < 2) return el("p", { class: "muted" }, "The chart fills in after a few weigh-ins.");
  const dates = all.map(w => Date.parse(w.date));
  const x0 = Math.min(...dates), x1 = Math.max(...dates, x0 + 864e5);
  const pts = s => s.series.map(w => [Date.parse(w.date), (s.start ?? s.series[0].pounds) - w.pounds]);
  const ys = [...pts(a), ...pts(b)].map(p => p[1]);
  const y0 = Math.min(0, ...ys), y1 = Math.max(1, ...ys);
  const X = t => P + (t - x0) / (x1 - x0) * (W - 2 * P), Y = v => H - P - (v - y0) / (y1 - y0) * (H - 2 * P);
  const line = (s, color) => {
    const p = pts(s);
    if (!p.length) return "";
    return '<polyline fill="none" stroke="' + color + '" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" points="' +
      p.map(q => X(q[0]).toFixed(1) + "," + Y(q[1]).toFixed(1)).join(" ") + '"/>';
  };
  const svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" width="100%" role="img" aria-label="Pounds lost over time">' +
    '<line x1="' + P + '" x2="' + (W - P) + '" y1="' + Y(0) + '" y2="' + Y(0) + '" stroke="currentColor" stroke-opacity=".15"/>' +
    line(a, "var(--orange)") + line(b, "var(--lav)") +
    '<text x="' + P + '" y="12">lb lost</text></svg>';
  const box = el("div"); box.innerHTML = svg;
  box.append(el("div", { class: "muted" },
    el("span", { style: "color:var(--orange)" }, "● "), a.name + "   ",
    el("span", { style: "color:var(--lav)" }, "● "), b.name));
  return box;
}

function render() {
  const app = document.getElementById("app");
  app.replaceChildren();
  const c = state.challenge;
  const me = state.role, them = me === "owner" ? "friend" : "owner";
  const mine = side(me), theirs = side(them);
  const daysLeft = Math.max(0, Math.ceil((Date.parse(c.endDate) - Date.parse(today())) / 864e5));
  const lead = (mine.pct ?? -1e9) === (theirs.pct ?? -1e9) ? null : ((mine.pct ?? -1e9) > (theirs.pct ?? -1e9) ? me : them);

  app.append(
    el("h1", {}, c.ownerName + " vs. " + c.friendName),
    el("p", { class: "sub" }, c.startDate + " → " + c.endDate + " · " + daysLeft + " days left"),
  );

  const card = s => el("div", { class: "side" + (lead === s.role ? " lead" : "") },
    el("div", { class: "name" }, s.role === me ? s.name + " (you)" : s.name, " ", lead === s.role ? el("span", { class: "pill" }, "LEADING") : ""),
    el("div", { class: "big" }, s.lost == null ? "—" : (s.lost >= 0 ? "−" : "+") + fmt(Math.abs(s.lost)) + " lb"),
    el("div", { class: "muted" }, s.pct == null ? "Weigh in to start" : fmt(s.pct) + "% · now " + fmt(s.current)));
  app.append(el("div", { class: "card" }, el("div", { class: "row" }, card(mine), card(theirs)), chart(side("owner"), side("friend"))));

  const date = el("input", { type: "date", value: today(), max: today() });
  const lbs = el("input", { type: "number", step: "0.1", inputmode: "decimal", placeholder: mine.current ? fmt(mine.current) : "185.0" });
  app.append(el("div", { class: "card" },
    el("h2", {}, "Log your weigh-in"),
    el("div", { class: "row" }, el("div", {}, el("label", {}, "Date"), date), el("div", {}, el("label", {}, "Pounds"), lbs)),
    el("div", { style: "height:10px" }),
    el("button", { onclick: async () => {
      const p = parseFloat(lbs.value);
      if (!(p > 50 && p < 1000)) return lbs.focus();
      state = await api("/weighins", { method: "PUT", body: JSON.stringify({ weighins: [{ date: date.value, pounds: p }] }) });
      render();
    } }, "Save weigh-in"),
    el("p", { class: "muted" }, "Tip: Share → Add to Home Screen to keep this one tap away."),
    el("div", { class: "list" }, mine.series.slice().reverse().slice(0, 10).map(w =>
      el("div", {}, el("span", {}, w.date), el("span", {}, fmt(w.pounds) + " lb ",
        el("button", { class: "ghost", onclick: async () => { state = await api("/weighins/" + w.date, { method: "DELETE" }); render(); } }, "Remove")))))
  ));

  const text = el("input", { maxlength: "280", placeholder: "Say something…" });
  app.append(el("div", { class: "card" },
    el("h2", {}, "Trash talk"),
    state.messages.length ? state.messages.map(m => el("div", { class: "msg" + (m.role === me ? " me" : "") },
      m.text, el("small", {}, (m.role === "owner" ? c.ownerName : c.friendName) + " · " + new Date(m.createdAt).toLocaleString()))) :
      el("p", { class: "muted" }, "No smack talk yet. Start it."),
    el("div", { style: "height:8px" }),
    el("div", { class: "row" }, text, el("button", { style: "flex:0 0 90px", onclick: async () => {
      if (!text.value.trim()) return;
      state = await api("/messages", { method: "POST", body: JSON.stringify({ text: text.value }) });
      render();
    } }, "Send"))
  ));
}

async function load() {
  try { state = await api(""); render(); }
  catch (e) {
    document.getElementById("app").replaceChildren(el("p", { id: "err" },
      token ? "Couldn't load the challenge (" + e.message + "). Ask for a fresh invite link." : "This link is missing its invite code. Ask for a fresh invite link."));
  }
}
load();
setInterval(() => { if (document.visibilityState === "visible") load(); }, 60000);
</script>
</body>
</html>`;
}
