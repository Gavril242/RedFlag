# iTEC OVERRIDE Backend

Node.js + Express + Socket.IO backend for the iTEC 2026 mobile challenge.

The server is ready to run with:

```bash
npm start
```

By default it starts on `http://localhost:3000` and serves:

- the REST API
- the Socket.IO realtime API
- the admin dashboard at `/`
- the interactive playground at `/playground.html`

State is persisted to `data/state.json`, so posters, stickers, teams, users,
and login sessions survive server restarts.

## Quick Start

```bash
npm install
npm start
```

Development mode:

```bash
npm run dev
```

Run tests:

```bash
npm test
```

## Configuration

Environment variables:

| Name | Default | Description |
| --- | --- | --- |
| `PORT` | `3000` | HTTP server port |
| `ADMIN_KEY` | `itec2026` | Required for `clear_canvas` |

PowerShell example:

```powershell
$env:ADMIN_KEY = "super-secret"
npm start
```

## Project Structure

```text
src/
  server.js
  posterManager.js
  persistenceStore.js
  teamSessionManager.js
  territoryEngine.js
  canvasHandlers.js
  territoryHandlers.js
public/
  index.html
  playground.html
data/
  state.json
test/
  backend.test.js
```

## REST API

Base URL: `http://localhost:3000`

### `GET /`

Returns the admin dashboard HTML.

### `GET /playground.html`

Returns an interactive browser client for testing the full flow:

- register/login with a real session
- create or join teams
- join poster rooms
- draw strokes
- place/remove stickers
- attach poster audio
- inspect territory and leaderboard updates

### `GET /api/health`

Response:

```json
{
  "ok": true,
  "service": "itec-override-backend"
}
```

### `POST /api/auth/register`

Creates a user and sets an `HttpOnly` session cookie.

Request:

```json
{
  "username": "Player1",
  "password": "test1234"
}
```

Response:

```json
{
  "ok": true,
  "user": {
    "id": "user_x",
    "username": "Player1",
    "teamId": null
  },
  "player": {
    "id": "user_x",
    "username": "Player1",
    "teamId": null
  },
  "team": null
}
```

### `POST /api/auth/login`

Logs in an existing user and sets an `HttpOnly` session cookie.

Request:

```json
{
  "username": "Player1",
  "password": "test1234"
}
```

Failure example:

```json
{
  "ok": false,
  "error": "invalid username or password"
}
```

### `GET /api/auth/session`

Returns the current logged-in user from the session cookie.

Success response:

```json
{
  "ok": true,
  "user": {
    "id": "user_x",
    "username": "Player1",
    "teamId": "my-team"
  },
  "player": {
    "id": "user_x",
    "username": "Player1",
    "teamId": "my-team"
  },
  "team": {
    "id": "my-team",
    "name": "My Team",
    "anthemTitle": "March",
    "anthemUrl": "https://example.com/anthem.mp3",
    "ownerUserId": "user_x",
    "memberCount": 1,
    "joinable": true
  }
}
```

If no valid cookie is present:

```json
{
  "ok": false,
  "error": "not logged in"
}
```

### `POST /api/auth/logout`

Clears the session cookie and removes the current session.

### `GET /api/teams`

Lists all current teams plus the logged-in session context if present.

Response:

```json
{
  "ok": true,
  "teams": [
    {
      "id": "my-team",
      "name": "My Team",
      "anthemTitle": "March",
      "anthemUrl": "https://example.com/anthem.mp3",
      "ownerUserId": "user_x",
      "memberCount": 1,
      "joinable": true
    }
  ],
  "currentUser": null,
  "currentPlayer": null,
  "currentTeam": null
}
```

### `POST /api/teams`

Requires a logged-in session cookie. Creates a custom team and assigns the current user to it.

Request:

```json
{
  "name": "My Team",
  "anthemTitle": "March",
  "anthemUrl": "https://example.com/anthem.mp3"
}
```

Failure example:

```json
{
  "ok": false,
  "error": "team name already exists"
}
```

### `POST /api/teams/:teamId/join`

Requires a logged-in session cookie. Assigns the current user to the selected team.

Success response:

```json
{
  "ok": true,
  "user": {
    "id": "user_y",
    "username": "Player2",
    "teamId": "my-team"
  },
  "player": {
    "id": "user_y",
    "username": "Player2",
    "teamId": "my-team"
  },
  "team": {
    "id": "my-team",
    "name": "My Team",
    "anthemTitle": "March",
    "anthemUrl": "https://example.com/anthem.mp3",
    "ownerUserId": "user_x",
    "memberCount": 2,
    "joinable": true
  },
  "teams": []
}
```

### `GET /api/posters`

Returns all active posters.

Response:

```json
[
  {
    "id": "POSTER_A",
    "createdAt": 1711111111111,
    "layout": {
      "width": 1000,
      "height": 1414,
      "aspectRatio": 0.7072135785007072,
      "origin": "top-left"
    },
    "audio": null,
    "strokeCount": 12,
    "stickerCount": 3
  }
]
```

### `GET /api/posters/:posterId/canvas`

Returns the full canvas state for one poster.

Response:

```json
{
  "layout": {
    "width": 1000,
    "height": 1414,
    "aspectRatio": 0.7072135785007072,
    "origin": "top-left"
  },
  "audio": null,
  "strokes": [],
  "stickers": []
}
```

### `GET /api/posters/:posterId/territory`

Returns territory ownership for one poster.

Response:

```json
{
  "posterId": "POSTER_A",
  "owner": "my-team",
  "teams": {
    "my-team": 0.62,
    "other-team": 0.38
  },
  "rawArea": {
    "my-team": 27.4,
    "other-team": 16.8
  }
}
```

Notes:

- `teams` is the share of claimed territory only
- `rawArea` is percentage of the full poster covered by each team
- territory is based on final visible content, not additive stacking
- stickers and GIFs count toward territory

### `GET /api/leaderboard`

Returns the global leaderboard.

Response:

```json
[
  {
    "teamId": "my-team",
    "totalArea": 14.2,
    "postersOwned": 3
  }
]
```

### `GET /api/posters/:posterId/audio`

Returns the poster audio metadata.

### `POST /api/posters/:posterId/audio`

Requires a logged-in session cookie and a current team.

Request:

```json
{
  "title": "March",
  "url": "https://example.com/anthem.mp3"
}
```

The backend fills in `teamId` and `userId` from the session automatically.

Playback notes:

- direct audio URLs such as `.mp3` are the safest option
- there is no backend YouTube-to-MP3 conversion or download path

### `DELETE /api/posters/:posterId/audio`

Requires a logged-in session cookie and a current team.

### `POST /api/posters/:posterId/audio/trigger`

Requires a logged-in session cookie and a current team.

Returns whether the current viewer should hear the poster's anthem.

### `GET /api/stickers/library`

Returns the built-in sticker library.

Response:

```json
{
  "ok": true,
  "stickers": [
    {
      "id": "bolt-badge",
      "name": "Bolt Badge",
      "url": "/stickers/bolt-badge.svg",
      "kind": "local"
    }
  ]
}
```

### `POST /api/stickers/generate`

Requires a logged-in session cookie.

Request:

```json
{
  "prompt": "cyber cat sticker, flat graphic, transparent background look"
}
```

Success response:

```json
{
  "ok": true,
  "sticker": {
    "id": "ai_123",
    "name": "cyber cat sticker, flat graphic, transparen",
    "url": "/generated-stickers/ai_123.png",
    "prompt": "cyber cat sticker, flat graphic, transparent background look",
    "kind": "generated",
    "model": "ByteDance/SDXL-Lightning"
  }
}
```

Notes:

- AI generation uses Hugging Face if `HF_TOKEN` is configured on the backend
- built-in stickers work without any external API key
- generated stickers are returned as normal sticker assets and can be placed through the existing sticker flow

## Socket.IO API

The server uses Socket.IO v4 with:

```json
["polling", "websocket"]
```

Connect to:

```text
http://localhost:3000
```

### 1. `join_poster`

Client emits:

```json
{
  "posterId": "POSTER_A",
  "coordinateMeta": {
    "coordinateSpace": "normalized",
    "origin": "top-left",
    "flipX": false,
    "flipY": false
  }
}
```

For browser clients with a valid session cookie, the backend uses the logged-in user/team automatically.

For non-browser clients without session cookies, explicit identity still works:

```json
{
  "posterId": "POSTER_A",
  "teamId": "my-team",
  "username": "Player1",
  "coordinateMeta": {
    "coordinateSpace": "normalized",
    "origin": "top-left"
  }
}
```

Server responds with `canvas_state`:

```json
{
  "posterId": "POSTER_A",
  "layout": {
    "width": 1000,
    "height": 1414,
    "aspectRatio": 0.7072135785007072,
    "origin": "top-left"
  },
  "audio": null,
  "strokes": [],
  "stickers": [],
  "territory": {
    "posterId": "POSTER_A",
    "owner": null,
    "teams": {},
    "rawArea": {}
  }
}
```

### 2. `draw_stroke`

Client emits:

```json
{
  "posterId": "POSTER_A",
  "teamId": "my-team",
  "userId": "Player1",
  "color": "#ff2d55",
  "width": 8,
  "coordinateMeta": {
    "coordinateSpace": "pixels",
    "origin": "bottom-left",
    "sourceWidth": 1080,
    "sourceHeight": 1920,
    "viewportX": 140,
    "viewportY": 260,
    "viewportWidth": 800,
    "viewportHeight": 1200
  },
  "points": [
    { "x": 0.1, "y": 0.2 },
    { "x": 0.15, "y": 0.25 }
  ]
}
```

Notes:

- normalized top-left poster coordinates are preferred
- `width` is clamped to `1..64`
- the backend can convert from pixel space or bottom-left origin into canonical poster space
- if the client is session-authenticated, spoofed `teamId` and `userId` are ignored

Ack response:

```json
{
  "ok": true,
  "strokeId": "s_123",
  "stroke": {},
  "territory": {}
}
```

Other clients receive `stroke_added`.
All clients in the room receive `territory_update`.

### 3. `place_sticker`

Client emits:

```json
{
  "posterId": "POSTER_A",
  "teamId": "my-team",
  "userId": "Player1",
  "url": "https://example.com/sticker.gif",
  "x": 0.4,
  "y": 0.5,
  "width": 0.1,
  "height": 0.1,
  "rotation": 15
}
```

Notes:

- `x` and `y` are clamped to `0..1`
- `width` and `height` are clamped to `0.01..1`
- `coordinateMeta` can be supplied here too
- stickers and GIFs affect territory ownership
- later stickers can overwrite earlier strokes
- later strokes can overwrite earlier stickers

Ack response:

```json
{
  "ok": true,
  "stickerId": "st_123",
  "sticker": {},
  "territory": {}
}
```

All clients in the room receive `sticker_added` and `territory_update`.

### 4. `remove_sticker`

Client emits:

```json
{
  "posterId": "POSTER_A",
  "stickerId": "st_123"
}
```

### 5. `get_territory`

Client emits:

```json
{
  "posterId": "POSTER_A"
}
```

The same client receives `territory_state`.

### 6. `get_leaderboard`

Client emits:

```json
{}
```

The same client receives `leaderboard_state`.

### 7. `clear_canvas`

Client emits:

```json
{
  "posterId": "POSTER_A",
  "adminKey": "itec2026"
}
```

On success, all clients in the room receive:

```json
{
  "posterId": "POSTER_A"
}
```

Important:

- clearing also removes stickers/GIFs
- clearing also removes attached poster audio

### 8. Poster audio socket events

The server can emit:

- `poster_audio_updated`
- `poster_audio_cleared`
- `poster_audio_trigger`

## Admin Dashboard

Open:

```text
http://localhost:3000
```

The dashboard shows:

- current connection status
- number of connected clients
- all active posters
- territory shares
- leaderboard
- recent event log

The Clear button emits `clear_canvas` and prompts for the admin key.

## Playground

Open:

```text
http://localhost:3000/playground.html
```

Use it to simulate a client:

- register or log in through REST and keep the browser session cookie
- create a team with optional anthem metadata or join an existing one
- join a poster using the session-bound identity
- load local stickers from the sticker library
- generate AI stickers when `HF_TOKEN` is configured
- click `Join Poster`
- draw on the canvas to emit `draw_stroke`
- switch to URL/GIF, library sticker, or generated sticker placement and click the poster to emit `place_sticker`
- remove stickers from the sticker list
- attach poster audio as the current team
- choose an automatic snapshot refresh interval for hackathon-grade recovery
- call `get_territory`, `get_leaderboard`, and `clear_canvas`
- inspect REST responses without leaving the page

The left control panel is grouped into:

- `Auth`
- `Teams`
- `Poster Session`
- `Sync`
- `Tools`
- `Coordinates`

Suggested browser flow:

1. Click `Register` or `Login`
2. Click `List Teams`
3. Create a team or choose one and click `Join Selected Team`
4. Click `Join Poster`
5. Draw, use a library sticker, generate a sticker, or attach audio
6. If you want periodic recovery, set `Auto Reload State` to `1` or `0.5`

Session notes:

- REST login uses an `HttpOnly` cookie named `override_session`
- the playground sends cookies on REST requests automatically
- after logging in once, `Get Session` should restore the current user until logout or cookie expiry
- browser drawing/sticker/audio actions use the logged-in session identity and no longer accept manual team spoofing

## Usage Notes

- State is persisted in `data/state.json`.
- The backend keeps up to `5000` strokes per poster. When that cap is hit, the oldest 10% are removed.
- Territory is recalculated from retained strokes and stickers so ownership stays consistent after pruning.
- `rawArea` is reported as percentage of the full poster covered by each team.
- Poster layout is fixed A4 portrait: `1000 x 1414`.
- Territory is based on final visible content, not additive overlap.
- Built-in stickers are served from `/public/stickers`.
- AI sticker generation uses Hugging Face when `HF_TOKEN` is configured.
- The admin dashboard is served locally and does not depend on third-party JS or font CDNs.
