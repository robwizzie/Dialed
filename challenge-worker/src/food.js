// Food logging for the Dialed app: Claude reads a meal (typed, or a photo)
// into itemized foods, and lists a restaurant's full menu. The on-device
// model is too small for nutrition; this is the accurate path, with the
// app's own food table and Apple Intelligence as the offline fallback.
//
//   POST /api/food/parse   { text, image?, usuals? } → { name, assumption, items[] }
//   GET  /api/food/menu?chain=Chick-fil-A          → { restaurant, known, items[], updatedAt }
//
// Numbers are grounded where possible: with FDC_API_KEY set, every generic
// food is re-priced from USDA FoodData Central (Claude only supplies the
// food and its grams); menus are cached in D1 for 30 days per chain.
//
// Secrets: ANTHROPIC_API_KEY (required), FDC_API_KEY (optional, free at
// https://fdc.nal.usda.gov/api-key-signup). Same CREATE_KEY gate as
// creating a challenge, so only your app can spend your API credits.

import Anthropic from "@anthropic-ai/sdk";

const MODEL = "claude-opus-5-5";
const MENU_TTL_MS = 30 * 24 * 3600 * 1000;

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "access-control-allow-origin": "*",
      "cache-control": "no-store",
    },
  });
const fail = (status, error) => json({ error }, status);

// ---------- Schemas (structured outputs: every field required, no extras)

const PARSED_ITEM = {
  type: "object",
  properties: {
    name: { type: "string", description: "Plain food name, e.g. 'Egg, scrambled' or 'Chick-fil-A 12-ct Grilled Nuggets'" },
    amount: { type: "number", description: "How much, as a number" },
    unit: { type: "string", description: "Household unit: large, cup, tbsp, tsp, oz, piece, slice, serving, grande…" },
    grams: { type: "number", description: "Best estimate of the edible weight in grams" },
    calories: { type: "number" },
    protein: { type: "number", description: "grams" },
    carbs: { type: "number", description: "grams" },
    fat: { type: "number", description: "grams" },
    usda_query: { type: "string", description: "Search phrase for USDA FoodData Central for a generic food (e.g. 'egg scrambled'); empty for branded or restaurant items" },
    usual: { type: "string", description: "Exact name from the person's usuals list when they refer to it ('my usual cold brew'); otherwise empty" },
  },
  required: ["name", "amount", "unit", "grams", "calories", "protein", "carbs", "fat", "usda_query", "usual"],
  additionalProperties: false,
};

const PARSED_MEAL = {
  type: "object",
  properties: {
    name: { type: "string", description: "Short tidy name for the whole meal" },
    assumption: { type: "string", description: "One short sentence on the biggest portion assumption, or empty" },
    items: { type: "array", items: PARSED_ITEM },
  },
  required: ["name", "assumption", "items"],
  additionalProperties: false,
};

const MENU_ITEM = {
  type: "object",
  properties: {
    name: { type: "string" },
    category: { type: "string", description: "Menu section, e.g. Entrées, Breakfast, Salads, Sides, Drinks, Desserts, Sauces" },
    calories: { type: "number" },
    protein: { type: "number" },
    carbs: { type: "number" },
    fat: { type: "number" },
    tip: { type: "string", description: "A swap that makes it lighter or higher-protein, with its calorie change, e.g. 'No bun −150'; or empty" },
  },
  required: ["name", "category", "calories", "protein", "carbs", "fat", "tip"],
  additionalProperties: false,
};

const MENU = {
  type: "object",
  properties: {
    restaurant: { type: "string", description: "The chain's proper name" },
    known: { type: "boolean", description: "True if this is a chain with published nutrition you know; false for an unknown or local place (then list a typical menu for that kind of place)" },
    items: { type: "array", items: MENU_ITEM },
  },
  required: ["restaurant", "known", "items"],
  additionalProperties: false,
};

// ---------- Claude

/** One structured call; returns the parsed JSON or throws {status, message}. */
async function structured(env, { system, content, schema, effort, maxTokens }) {
  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY });
  // Menus can run long, so stream and take the final message.
  const message = await client.beta.messages
    .stream({
      model: MODEL,
      max_tokens: maxTokens,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      system,
      output_config: { effort, format: { type: "json_schema", schema } },
      messages: [{ role: "user", content }],
    })
    .finalMessage();
  if (message.stop_reason === "refusal") throw { status: 422, message: "The model declined this request." };
  if (message.stop_reason === "max_tokens") throw { status: 502, message: "The answer was cut off; try a shorter description." };
  const text = message.content.filter((b) => b.type === "text").map((b) => b.text).join("");
  try {
    return JSON.parse(text);
  } catch {
    throw { status: 502, message: "Couldn't read the model's answer." };
  }
}

function errorResponse(error) {
  if (error instanceof Anthropic.RateLimitError) return fail(429, "Busy — try again in a moment.");
  if (error instanceof Anthropic.AuthenticationError) return fail(500, "The server's ANTHROPIC_API_KEY is missing or wrong.");
  if (error instanceof Anthropic.APIError) return fail(502, `Model error ${error.status ?? ""}`.trim());
  if (error && typeof error.status === "number") return fail(error.status, error.message);
  return fail(500, "Something went wrong.");
}

// ---------- USDA FoodData Central

const ENERGY = [1008, 2047, 2048]; // kcal; Foundation foods sometimes only carry the Atwater variants
const PROTEIN = 1003, CARBS = 1005, FAT = 1004;

/** Per-100 g nutrition for the best generic match, or null. */
async function usda(env, query) {
  if (!env.FDC_API_KEY || !query) return null;
  const url = new URL("https://api.nal.usda.gov/fdc/v1/foods/search");
  url.searchParams.set("api_key", env.FDC_API_KEY);
  url.searchParams.set("query", query);
  url.searchParams.set("dataType", "Survey (FNDDS),Foundation,SR Legacy");
  url.searchParams.set("pageSize", "1");
  try {
    const res = await fetch(url, { cf: { cacheTtl: 86400, cacheEverything: true } });
    if (!res.ok) return null;
    const food = (await res.json()).foods?.[0];
    if (!food) return null;
    const value = (id) => food.foodNutrients?.find((n) => n.nutrientId === id)?.value;
    const kcal = ENERGY.map(value).find((v) => typeof v === "number");
    if (typeof kcal !== "number") return null;
    return { kcal, protein: value(PROTEIN) ?? 0, carbs: value(CARBS) ?? 0, fat: value(FAT) ?? 0 };
  } catch {
    return null;
  }
}

const round = (n) => Math.round(Math.max(0, Number(n) || 0) * 10) / 10;

/** Swap Claude's numbers for USDA's when the match is plausible. */
async function grounded(env, item) {
  const base = {
    name: item.name,
    amount: item.amount,
    unit: item.unit,
    grams: round(item.grams),
    calories: round(item.calories),
    protein: round(item.protein),
    carbs: round(item.carbs),
    fat: round(item.fat),
    source: "estimate",
    usual: item.usual || null,
  };
  const per100 = item.grams > 0 ? await usda(env, item.usda_query) : null;
  if (!per100) return base;
  const f = item.grams / 100;
  const calories = per100.kcal * f;
  // A bad search hit (egg → eggnog) shows up as a wildly different total; keep Claude's then.
  const ratio = item.calories > 0 ? calories / item.calories : 1;
  if (ratio < 0.5 || ratio > 2) return base;
  return {
    ...base,
    calories: round(calories),
    protein: round(per100.protein * f),
    carbs: round(per100.carbs * f),
    fat: round(per100.fat * f),
    source: "usda",
  };
}

// ---------- Routes

const PARSE_SYSTEM = `You itemize what someone ate for a nutrition log. \
List each food they ate with a realistic amount in a household unit and its weight in grams, \
and your best calories, protein, carbs and fat for that amount. \
Only list what they ate; don't add sides or drinks they didn't mention. \
Restaurant and packaged items keep their real menu name (e.g. "Chipotle chicken burrito bowl") and the chain's published nutrition, with an empty usda_query. \
Generic foods get a short usda_query that would find them in USDA FoodData Central ("egg scrambled", "bread sourdough", "butter salted"). \
If the person refers to one of their usuals, copy its exact name into "usual" and use its numbers.`;

export async function parseMeal(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return fail(400, "bad json");
  }
  const text = String(body?.text ?? "").trim().slice(0, 1000);
  const image = typeof body?.image === "string" && body.image.length < 6_000_000 ? body.image : null;
  if (!text && !image) return fail(400, "describe the meal or add a photo");

  const usuals = Array.isArray(body?.usuals) ? body.usuals.slice(0, 40) : [];
  let prompt = "";
  if (usuals.length) {
    prompt += "Their usuals (name: calories / protein g / carbs g / fat g):\n";
    prompt += usuals
      .map((u) => `- ${String(u.name).slice(0, 80)}: ${round(u.calories)} / ${round(u.protein)} / ${round(u.carbs)} / ${round(u.fat)}`)
      .join("\n");
    prompt += "\n\n";
  }
  prompt += image
    ? `Itemize the meal in this photo.${text ? ` They add: ${text}` : ""}`
    : `They ate: ${text}`;

  const content = image
    ? [{ type: "image", source: { type: "base64", media_type: "image/jpeg", data: image } }, { type: "text", text: prompt }]
    : prompt;

  try {
    const meal = await structured(env, { system: PARSE_SYSTEM, content, schema: PARSED_MEAL, effort: "low", maxTokens: 8000 });
    const items = await Promise.all((meal.items ?? []).slice(0, 15).map((i) => grounded(env, i)));
    return json({ name: meal.name, assumption: meal.assumption, items });
  } catch (error) {
    return errorResponse(error);
  }
}

const MENU_SYSTEM = `You list a restaurant's full current US menu with its published nutrition, for a calorie-tracking app. \
Cover every regular menu item a customer can order — entrées, breakfast, salads, sides, kids' meals, drinks, desserts and sauces — \
one row per orderable size where sizes differ in nutrition (e.g. "Waffle Fries (medium)"). \
Use the chain's published numbers as best you know them. Keep names as they appear on the menu.`;

const chainKey = (name) => name.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, " ").trim();

export async function menu(request, env, url) {
  const chain = (url.searchParams.get("chain") || "").trim().slice(0, 80);
  if (!chain) return fail(400, "which restaurant?");
  const key = chainKey(chain);

  const cached = await env.DB.prepare("SELECT json, updated_at FROM menus WHERE chain_key = ?").bind(key).first();
  if (cached && Date.now() - Date.parse(cached.updated_at) < MENU_TTL_MS && url.searchParams.get("refresh") !== "1") {
    return json({ ...JSON.parse(cached.json), updatedAt: cached.updated_at });
  }

  try {
    const result = await structured(env, {
      system: MENU_SYSTEM,
      content: `Restaurant: ${chain}`,
      schema: MENU,
      effort: "medium",
      maxTokens: 64000,
    });
    const items = (result.items ?? []).slice(0, 400).map((i) => ({
      name: i.name,
      category: i.category || "Menu",
      calories: round(i.calories),
      protein: round(i.protein),
      carbs: round(i.carbs),
      fat: round(i.fat),
      tip: i.tip || null,
    }));
    const out = { restaurant: result.restaurant || chain, known: !!result.known, items };
    const now = new Date().toISOString();
    await env.DB.prepare("INSERT OR REPLACE INTO menus (chain_key, json, updated_at) VALUES (?, ?, ?)")
      .bind(key, JSON.stringify(out), now)
      .run();
    return json({ ...out, updatedAt: now });
  } catch (error) {
    return errorResponse(error);
  }
}
