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
| GET | `/c/:id#t=<token>` | the friend's page |
