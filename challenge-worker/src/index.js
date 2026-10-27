// Dialed live challenge.
//
// Two people, one challenge: the owner (the Dialed app) and a friend (any
// browser). Each side holds a random token; the server stores only its
// SHA-256 hash and uses it to tell who's posting. The friend's token rides
// in the invite link's #fragment, so it never reaches server logs.
//
//   POST   /api/challenges                    create (owner) → ids + tokens
//   GET    /api/challenges/:id                challenge, weigh-ins, messages
//   PATCH  /api/challenges/:id                owner edits names/dates/starts
//   PUT    /api/challenges/:id/weighins       upsert your own weigh-ins
//   DELETE /api/challenges/:id/weighins/:date
//   POST   /api/challenges/:id/messages       trash talk (≤ 280 chars)
//   PUT    /api/challenges/:id/stats          your own stats card (goal, steps, workouts…)
//   POST   /api/challenges/:id/scale?t=…      automatic weigh-in from a phone automation
//   POST   /api/challenges/:id/bets           propose this week's side bet { week, metric, stake }
//   PATCH  /api/challenges/:id/bets/:betId    { action: accept|decline|cancel|paid|unpaid } and/or { score }
//   GET    /c/:id                             the friend's page
//   POST   /api/food/parse                    itemize a meal (app only — see food.js)
//   GET    /api/food/menu?chain=…             a restaurant's full menu (app only)

import { page } from "./page.js";
import { parseMeal, menu } from "./food.js";

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, content-type, x-create-key",
  "access-control-allow-methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
  "cache-control": "no-store",
};

const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
const fail = (status, error) => json({ error }, status);

const isDate = (s) => typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s);
const isWeight = (n) => typeof n === "number" && isFinite(n) && n > 50 && n < 1000;
const cleanName = (s) => String(s ?? "").trim().slice(0, 40);

function randomToken(bytes = 16) {
  const a = new Uint8Array(bytes);
  crypto.getRandomValues(a);
  return [...a].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** "owner" | "friend" | null for the bearer token on this challenge. */
async function roleFor(request, challenge, allowQueryToken = false) {
  const auth = request.headers.get("authorization") || "";
  let token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  // Phone automations (Apple Shortcuts) are simplest with the token in the URL.
  if (!token && allowQueryToken) token = new URL(request.url).searchParams.get("t") || "";
  if (!token) return null;
  const hash = await sha256(token);
  if (hash === challenge.owner_token_hash) return "owner";
  if (hash === challenge.friend_token_hash) return "friend";
  return null;
}

async function loadChallenge(env, id) {
  return env.DB.prepare("SELECT * FROM challenges WHERE id = ?").bind(id).first();
}

function publicChallenge(c) {
  return {
    id: c.id,
    ownerName: c.owner_name,
    friendName: c.friend_name,
    startDate: c.start_date,
    endDate: c.end_date,
    ownerStart: c.owner_start,
    friendStart: c.friend_start,
  };
}

async function readBody(request) {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

async function create(request, env, url) {
  if (env.CREATE_KEY && request.headers.get("x-create-key") !== env.CREATE_KEY) return fail(403, "bad create key");
  const b = await readBody(request);
  if (!b) return fail(400, "expected JSON");
  const ownerName = cleanName(b.ownerName) || "Me";
  const friendName = cleanName(b.friendName) || "Friend";
  if (!isDate(b.startDate) || !isDate(b.endDate) || b.endDate < b.startDate) return fail(400, "bad dates");
  const id = randomToken(6);
  const ownerToken = randomToken();
  const friendToken = randomToken();
  await env.DB.prepare(
    `INSERT INTO challenges (id, owner_name, friend_name, start_date, end_date, owner_token_hash, friend_token_hash, owner_start, friend_start, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  )
    .bind(id, ownerName, friendName, b.startDate, b.endDate, await sha256(ownerToken), await sha256(friendToken),
          isWeight(b.ownerStart) ? b.ownerStart : null, isWeight(b.friendStart) ? b.friendStart : null, new Date().toISOString())
    .run();
  const inviteUrl = `${url.origin}/c/${id}#t=${friendToken}`;
  return json({ id, ownerToken, friendToken, inviteUrl }, 201);
}

const METRICS = ["steps", "miles", "workouts", "prs", "skippedDays", "proteinDays"];

/** Side bets, newest week first. A database without the table just has none. */
async function loadBets(env, c) {
  try {
    const r = await env.DB.prepare(
      `SELECT id, week, metric, stake, proposer, status, owner_score AS ownerScore, friend_score AS friendScore, paid,
              created_at AS createdAt FROM bets WHERE challenge_id = ? ORDER BY week DESC, created_at DESC LIMIT 40`
    ).bind(c.id).all();
    return r.results;
  } catch {
    return [];
  }
}

/** Each side's latest weekly report. A database without the table just has none. */
async function loadReports(env, c) {
  try {
    const r = await env.DB.prepare("SELECT role, week, json, updated_at AS updatedAt FROM reports WHERE challenge_id = ?").bind(c.id).all();
    const out = {};
    for (const row of r.results) {
      try { out[row.role] = { ...JSON.parse(row.json), week: row.week, updatedAt: row.updatedAt }; } catch {}
    }
    return out;
  } catch {
    return {};
  }
}

async function get(env, c, role) {
  const [w, m, st, bets, reports] = await Promise.all([
    env.DB.prepare("SELECT role, date, pounds, source, updated_at AS updatedAt FROM weighins WHERE challenge_id = ? ORDER BY date").bind(c.id).all(),
    env.DB.prepare("SELECT id, role, text, created_at AS createdAt FROM messages WHERE challenge_id = ? ORDER BY id DESC LIMIT 50")
      .bind(c.id).all(),
    env.DB.prepare("SELECT role, json, updated_at AS updatedAt FROM stats WHERE challenge_id = ?").bind(c.id).all(),
    loadBets(env, c),
    loadReports(env, c),
  ]);
  const stats = {};
  for (const row of st.results) {
    try { stats[row.role] = { ...JSON.parse(row.json), updatedAt: row.updatedAt }; } catch {}
  }
  return json({ role, challenge: publicChallenge(c), weighins: w.results, messages: m.results.reverse(), stats, bets, reports });
}

/** Today's date where the request came from (Cloudflare knows the caller's timezone). */
function localToday(request) {
  const tz = request.cf?.timezone || "America/New_York";
  try {
    return new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
  } catch {
    return new Date().toISOString().slice(0, 10);
  }
}

/** "185.2", 185.2, "185.2 lb", "84 kg" → pounds, or null. */
function parseWeight(value, unit) {
  const text = String(value ?? "").trim().toLowerCase();
  const n = parseFloat(text.replace(",", "."));
  if (!isFinite(n)) return null;
  const kg = /kg/.test(text) || String(unit || "").toLowerCase().startsWith("kg");
  const pounds = kg ? n * 2.2046226 : n;
  return isWeight(pounds) ? Math.round(pounds * 10) / 10 : null;
}

async function upsertStats(env, c, role, patch) {
  const row = await env.DB.prepare("SELECT json FROM stats WHERE challenge_id = ? AND role = ?").bind(c.id, role).first();
  let current = {};
  try { current = row ? JSON.parse(row.json) : {}; } catch {}
  const next = JSON.stringify({ ...current, ...patch }).slice(0, 4000);
  await env.DB.prepare(
    `INSERT INTO stats (challenge_id, role, json, updated_at) VALUES (?, ?, ?, ?)
     ON CONFLICT (challenge_id, role) DO UPDATE SET json = excluded.json, updated_at = excluded.updated_at`
  ).bind(c.id, role, next, new Date().toISOString()).run();
}

async function putStats(request, env, c, role) {
  const b = await readBody(request);
  if (!b || typeof b !== "object" || Array.isArray(b)) return fail(400, "expected an object");
  // Small, flat, numbers/strings only.
  const clean = {};
  for (const [k, v] of Object.entries(b).slice(0, 30)) {
    if (typeof v === "number" && isFinite(v)) clean[k.slice(0, 40)] = v;
    else if (typeof v === "string") clean[k.slice(0, 40)] = v.slice(0, 120);
    else if (typeof v === "boolean") clean[k.slice(0, 40)] = v;
  }
  await upsertStats(env, c, role, clean);
  return get(env, c, role);
}

/** One call from a phone automation: { weight, unit?, steps?, date? }. */
async function scale(request, env, c, role) {
  let b = await readBody(request);
  if (b === null) b = { weight: new URL(request.url).searchParams.get("weight") };
  const pounds = parseWeight(b.weight ?? b.Weight ?? b.value, b.unit);
  const date = isDate(b.date) ? b.date : localToday(request);
  const steps = parseInt(b.steps, 10);
  if (isFinite(steps) && steps >= 0 && steps < 200000) await upsertStats(env, c, role, { stepsToday: steps, stepsDate: date });
  if (pounds === null) return json({ ok: true, saved: false, note: "No weight today yet — nothing to save." });
  await env.DB.prepare(
    `INSERT INTO weighins (challenge_id, role, date, pounds, updated_at, source) VALUES (?, ?, ?, ?, ?, 'scale')
     ON CONFLICT (challenge_id, role, date) DO UPDATE SET pounds = excluded.pounds, updated_at = excluded.updated_at, source = 'scale'`
  ).bind(c.id, role, date, pounds, new Date().toISOString()).run();
  return json({ ok: true, saved: true, date, pounds });
}

async function patch(request, env, c, role) {
  if (role !== "owner") return fail(403, "owner only");
  const b = (await readBody(request)) || {};
  const next = {
    owner_name: b.ownerName !== undefined ? cleanName(b.ownerName) || c.owner_name : c.owner_name,
    friend_name: b.friendName !== undefined ? cleanName(b.friendName) || c.friend_name : c.friend_name,
    start_date: isDate(b.startDate) ? b.startDate : c.start_date,
    end_date: isDate(b.endDate) ? b.endDate : c.end_date,
    owner_start: b.ownerStart === null ? null : isWeight(b.ownerStart) ? b.ownerStart : c.owner_start,
    friend_start: b.friendStart === null ? null : isWeight(b.friendStart) ? b.friendStart : c.friend_start,
  };
  await env.DB.prepare(
    "UPDATE challenges SET owner_name=?, friend_name=?, start_date=?, end_date=?, owner_start=?, friend_start=? WHERE id=?"
  ).bind(next.owner_name, next.friend_name, next.start_date, next.end_date, next.owner_start, next.friend_start, c.id).run();
  return get(env, { ...c, ...next }, role);
}

async function putWeighins(request, env, c, role) {
  const b = await readBody(request);
  const list = Array.isArray(b?.weighins) ? b.weighins.slice(0, 120) : null;
  if (!list) return fail(400, "expected { weighins: [{ date, pounds }] }");
  const now = new Date().toISOString();
  const source = ["manual", "app", "scale"].includes(b.source) ? b.source : "manual";
  const stmts = list
    .filter((w) => isDate(w.date) && isWeight(w.pounds))
    .map((w) =>
      env.DB.prepare(
        `INSERT INTO weighins (challenge_id, role, date, pounds, updated_at, source) VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT (challenge_id, role, date) DO UPDATE SET pounds = excluded.pounds, updated_at = excluded.updated_at, source = excluded.source`
      ).bind(c.id, role, w.date, Math.round(w.pounds * 10) / 10, now, source)
    );
  if (stmts.length) await env.DB.batch(stmts);
  return get(env, c, role);
}

async function deleteWeighin(env, c, role, date) {
  if (!isDate(date)) return fail(400, "bad date");
  await env.DB.prepare("DELETE FROM weighins WHERE challenge_id = ? AND role = ? AND date = ?").bind(c.id, role, date).run();
  return get(env, c, role);
}

async function proposeBet(request, env, c, role) {
  const b = await readBody(request);
  const stake = String(b?.stake ?? "").trim().slice(0, 80);
  if (!b || !isDate(b.week) || !METRICS.includes(b.metric) || !stake) return fail(400, "expected { week, metric, stake }");
  const open = await env.DB.prepare(
    "SELECT id FROM bets WHERE challenge_id = ? AND week = ? AND status IN ('proposed','active')"
  ).bind(c.id, b.week).first();
  if (open) return fail(409, "there's already a bet this week");
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO bets (id, challenge_id, week, metric, stake, proposer, status, paid, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, 'proposed', 0, ?, ?)`
  ).bind(randomToken(6), c.id, b.week, b.metric, stake, role, now, now).run();
  return get(env, c, role);
}

async function patchBet(request, env, c, role, betId) {
  const bet = await env.DB.prepare("SELECT * FROM bets WHERE id = ? AND challenge_id = ?").bind(betId, c.id).first();
  if (!bet) return fail(404, "no such bet");
  const b = (await readBody(request)) || {};
  let status = bet.status;
  let paid = bet.paid;
  switch (b.action) {
    case undefined: break;
    case "accept":
    case "decline":
      if (bet.status !== "proposed" || bet.proposer === role) return fail(403, "only the other side can answer");
      status = b.action === "accept" ? "active" : "declined";
      break;
    case "cancel":
      if (bet.status !== "proposed" || bet.proposer !== role) return fail(403, "only the proposer can cancel");
      status = "cancelled";
      break;
    case "paid": paid = 1; break;
    case "unpaid": paid = 0; break;
    default: return fail(400, "unknown action");
  }
  // Each side only ever writes its own score.
  const score = typeof b.score === "number" && isFinite(b.score) && b.score >= 0 && b.score < 1e7 ? b.score : null;
  const column = role === "owner" ? "owner_score" : "friend_score";
  await env.DB.prepare(
    `UPDATE bets SET status = ?, paid = ?, ${column} = COALESCE(?, ${column}), updated_at = ? WHERE id = ?`
  ).bind(status, paid, score, new Date().toISOString(), bet.id).run();
  return get(env, c, role);
}

/** The Sunday summary: { week, report: { headline, subline, rows: [{ title, you, friend, winner }], betLine, standing, nudge } }. */
async function postReport(request, env, c, role) {
  const b = await readBody(request);
  if (!b || !isDate(b.week) || !b.report || typeof b.report !== "object" || Array.isArray(b.report)) {
    return fail(400, "expected { week, report }");
  }
  const str = v => (typeof v === "string" ? v.slice(0, 200) : undefined);
  const r = b.report;
  const clean = {
    weekNumber: typeof r.weekNumber === "number" && isFinite(r.weekNumber) ? Math.round(r.weekNumber) : undefined,
    headline: str(r.headline), subline: str(r.subline), betLine: str(r.betLine), standing: str(r.standing), nudge: str(r.nudge),
    rows: Array.isArray(r.rows) ? r.rows.slice(0, 10).map(row => ({
      title: str(row?.title), you: str(row?.you), friend: str(row?.friend),
      winner: ["you", "friend", "tie"].includes(row?.winner) ? row.winner : undefined,
    })) : [],
  };
  await env.DB.prepare(
    `INSERT INTO reports (challenge_id, role, week, json, updated_at) VALUES (?, ?, ?, ?, ?)
     ON CONFLICT (challenge_id, role) DO UPDATE SET week = excluded.week, json = excluded.json, updated_at = excluded.updated_at`
  ).bind(c.id, role, b.week, JSON.stringify(clean), new Date().toISOString()).run();
  return get(env, c, role);
}

async function postMessage(request, env, c, role) {
  const b = await readBody(request);
  const text = String(b?.text ?? "").trim().slice(0, 280);
  if (!text) return fail(400, "empty message");
  await env.DB.prepare("INSERT INTO messages (challenge_id, role, text, created_at) VALUES (?, ?, ?, ?)")
    .bind(c.id, role, text, new Date().toISOString()).run();
  return get(env, c, role);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { headers: JSON_HEADERS });

    const pageMatch = url.pathname.match(/^\/c\/([a-f0-9]{12})\/?$/);
    if (pageMatch && request.method === "GET") {
      return new Response(page(pageMatch[1]), {
        headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "referrer-policy": "no-referrer" },
      });
    }

    if (url.pathname === "/api/challenges" && request.method === "POST") return create(request, env, url);

    // Food routes spend your Anthropic credits, so they always need the app's key.
    if (url.pathname.startsWith("/api/food/")) {
      if (!env.CREATE_KEY) return fail(403, "set CREATE_KEY on the server to use food logging");
      if (request.headers.get("x-create-key") !== env.CREATE_KEY) return fail(403, "bad create key");
      if (!env.ANTHROPIC_API_KEY) return fail(500, "set ANTHROPIC_API_KEY on the server");
      if (url.pathname === "/api/food/parse" && request.method === "POST") return parseMeal(request, env);
      if (url.pathname === "/api/food/menu" && request.method === "GET") return menu(request, env, url);
      return fail(404, "not found");
    }

    const m = url.pathname.match(/^\/api\/challenges\/([a-f0-9]{12})(\/weighins(?:\/(\d{4}-\d{2}-\d{2}))?|\/messages|\/stats|\/scale|\/reports|\/bets(?:\/([a-f0-9]{12}))?)?\/?$/);
    if (!m) return url.pathname === "/" ? new Response("Dialed challenge server is running.") : fail(404, "not found");

    const c = await loadChallenge(env, m[1]);
    if (!c) return fail(404, "no such challenge");
    const role = await roleFor(request, c, m[2] === "/scale");
    if (!role) return fail(401, "bad token");

    const sub = m[2] || "";
    if (!sub && request.method === "GET") return get(env, c, role);
    if (!sub && request.method === "PATCH") return patch(request, env, c, role);
    if (sub === "/weighins" && request.method === "PUT") return putWeighins(request, env, c, role);
    if (sub.startsWith("/weighins/") && request.method === "DELETE") return deleteWeighin(env, c, role, m[3]);
    if (sub === "/messages" && request.method === "POST") return postMessage(request, env, c, role);
    if (sub === "/stats" && request.method === "PUT") return putStats(request, env, c, role);
    if (sub === "/scale" && (request.method === "POST" || request.method === "GET")) return scale(request, env, c, role);
    if (sub === "/bets" && request.method === "POST") return proposeBet(request, env, c, role);
    if (sub === "/reports" && request.method === "POST") return postReport(request, env, c, role);
    if (sub.startsWith("/bets/") && request.method === "PATCH") return patchBet(request, env, c, role, m[4]);
    return fail(405, "method not allowed");
  },
};
