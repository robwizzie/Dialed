# Dialed live challenge server

A tiny Cloudflare Worker that lets your friend join your weight-loss
challenge from a link — any phone, any browser, no app.

- **Your app** creates the challenge, uploads your weigh-ins, pulls theirs.
- **Your friend** opens the invite link to log weigh-ins, see the
  scoreboard and chart, and trash talk.

Each side has a random token. The server stores only a hash of it. The
friend's token lives in the link's `#fragment`, so it never shows up in
server logs.

## Deploy (one time, ~1 minute)

The database (`dialed-challenge`, D1) already exists in your Cloudflare
account with the schema applied. From this folder:

```sh
npx wrangler login      # opens the browser once
npx wrangler deploy
```

Wrangler prints the address, e.g. `https://dialed-challenge.<you>.workers.dev`.

Then in Dialed: **Challenge → Make it live**, paste that address, and tap
**Create invite**. Send the link to your friend.

### Optional: lock down creating challenges

```sh
npx wrangler secret put CREATE_KEY
```

Paste the same key into the "Create key" field in the app.

## Automatic weigh-ins

The friend's page has a **Sync your scale** card. On iPhone it walks
through a Shortcuts automation (Time of Day → Find Health Samples:
Weight today → Get Contents of URL POST to the `/scale` link), so any scale
that writes to Apple Health (e.g. Fitdays/ABLEGRID) posts each morning's
weight automatically. On Android it offers a home-screen quick log plus the
same link for automation apps.

## Local test

```sh
npx wrangler d1 execute dialed-challenge --local --file schema.sql
npx wrangler dev
```

## API

| Method | Path | Who |
|---|---|---|
| POST | `/api/challenges` | anyone (or with `x-create-key`) |
| GET | `/api/challenges/:id` | owner or friend (Bearer token) |
| PATCH | `/api/challenges/:id` | owner |
| PUT | `/api/challenges/:id/weighins` | your own weigh-ins `{ weighins: [{ date, pounds }] }` |
| DELETE | `/api/challenges/:id/weighins/:date` | your own |
| POST | `/api/challenges/:id/messages` | `{ text }`, 280 chars max |
| PUT | `/api/challenges/:id/stats` | your stats card (goal, steps, workouts…) |
| POST | `/api/challenges/:id/scale?t=<token>` | automatic weigh-in: `{ "weight": "185.2 lb" }` (kg understood); dated by the caller's timezone |
| POST | `/api/challenges/:id/bets` | propose this week's side bet `{ week, metric, stake }` (one open bet per week) |
| PATCH | `/api/challenges/:id/bets/:betId` | `{ action: accept \| decline \| cancel \| paid \| unpaid }` and/or `{ score }` (your own number only) |
| POST | `/api/challenges/:id/reports` | your Sunday report `{ week, report: { weekNumber, headline, subline, rows: [{ title, you, friend, winner }], betLine, standing, nudge } }` (latest per side; shown on the other side's page) |
| GET | `/c/:id#t=<token>` | the friend's page |

## Side bets (v3)

Weekly mini-battles (most steps, miles, workouts, PRs, protein days, or
fewest skipped days) with a stake. Either side proposes; the other
accepts on the page or in the app. Each side posts only its own number;
the winner is worked out when the week (Mon–Sun) ends.

To turn them on for an existing server, add the table and redeploy:

```sh
npx wrangler d1 execute dialed-challenge --remote --file schema.sql
npx wrangler deploy
```

Until then the app keeps bets on the phone and you type your friend's
number in.

## Weekly reports (v4)

Every Sunday from 7 PM the app posts a summary of the week (who took it on
weight, steps, miles, workouts, PRs, the side bet and the overall
standing). The friend's page shows the latest one as a "Week N report"
card. GET responses include `reports` keyed "owner" / "friend".

To turn them on for an existing server, add the table and redeploy:

```sh
npx wrangler d1 execute dialed-challenge --remote --file schema.sql
npx wrangler deploy
```

Until then the app still builds the report and offers "Text it" to send
it over Messages.

## Food logging (v5)

The app's food logging can use this server to read meals with Claude
instead of the on-device model: typed descriptions, meal photos, and full
restaurant menus. Generic foods are re-priced from USDA FoodData Central
when you add a key.

| Method | Path | |
|---|---|---|
| POST | `/api/food/parse` | `{ text, image?, usuals? }` → itemized meal (`image` is base64 JPEG) |
| GET | `/api/food/menu?chain=Chick-fil-A` | full menu with nutrition; cached 30 days per chain (`&refresh=1` to rebuild) |

Both need the `x-create-key` header, so the server must have `CREATE_KEY`
set, with the same key entered in the app. These routes spend your
Anthropic credits.

To turn it on:

```sh
npm install                                   # the Anthropic SDK
npx wrangler secret put ANTHROPIC_API_KEY     # from console.anthropic.com
npx wrangler secret put CREATE_KEY            # if you haven't already; same key in the app
npx wrangler secret put FDC_API_KEY           # optional, free: fdc.nal.usda.gov/api-key-signup
npx wrangler d1 execute dialed-challenge --remote --file schema.sql
npx wrangler deploy
```

In Dialed, the server address and create key go in **Challenge → Live
sync** (the same fields the live challenge uses). Without them the app
keeps logging food on-device as before.
