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
