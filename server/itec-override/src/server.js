const express = require("express");
const http = require("http");
const path = require("path");
const { Server } = require("socket.io");

const { posterManager } = require("./posterManager");
const { territoryEngine } = require("./territoryEngine");
const { registerCanvasHandlers } = require("./canvasHandlers");
const { registerTerritoryHandlers } = require("./territoryHandlers");
const { loadState, saveState } = require("./persistenceStore");
const { teamSessionManager } = require("./teamSessionManager");
const { stickerService } = require("./stickerService");

const PORT = process.env.PORT || 3000;
const SESSION_COOKIE = "override_session";
const COOKIE_MAX_AGE_MS = 1000 * 60 * 60 * 24 * 30;

const app = express();
const httpServer = http.createServer(app);

const io = new Server(httpServer, {
  cors: { origin: "*", methods: ["GET", "POST"] },
  transports: ["polling", "websocket"],
});

hydrateState();
posterManager.setPersistenceHook(persistState);
teamSessionManager.setPersistenceHook(persistState);
rebuildTerritoryFromPosters();

app.use(express.static(path.join(__dirname, "../public")));
app.use(express.json());

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, service: "itec-override-backend" });
});

app.post("/api/auth/register", (req, res) => {
  const { username, password } = req.body || {};
  const result = teamSessionManager.register(username, password);
  if (!result.ok) {
    return res.status(400).json(result);
  }

  setSessionCookie(res, result.session.token);
  res.json({
    ok: true,
    user: result.user,
    player: result.player,
    team: result.team,
  });
});

app.post("/api/auth/login", (req, res) => {
  const { username, password } = req.body || {};
  const result = teamSessionManager.login(username, password);
  if (!result.ok) {
    return res.status(400).json(result);
  }

  setSessionCookie(res, result.session.token);
  res.json({
    ok: true,
    user: result.user,
    player: result.player,
    team: result.team,
  });
});

app.get("/api/auth/session", (req, res) => {
  const session = getSessionFromRequest(req);
  if (!session) {
    return res.status(401).json({ ok: false, error: "not logged in" });
  }

  res.json({
    ok: true,
    user: session.user,
    player: session.player,
    team: session.team,
  });
});

app.post("/api/auth/logout", (req, res) => {
  const token = getCookie(req, SESSION_COOKIE);
  if (token) {
    teamSessionManager.logout(token);
  }
  clearSessionCookie(res);
  res.json({ ok: true });
});

app.get("/api/teams", (req, res) => {
  const session = getSessionFromRequest(req);
  res.json({
    ok: true,
    teams: teamSessionManager.listTeams(),
    currentUser: session?.user || null,
    currentPlayer: session?.player || null,
    currentTeam: session?.team || null,
  });
});

app.post("/api/teams", (req, res) => {
  const session = getSessionFromRequest(req);
  if (!session) {
    return res.status(401).json({ ok: false, error: "not logged in" });
  }

  const result = teamSessionManager.createTeam(session.user.id, req.body || {});
  if (!result.ok) {
    return res.status(400).json(result);
  }

  res.json({
    ok: true,
    user: result.user,
    player: result.player,
    team: result.team,
    teams: result.teams,
  });
});

app.post("/api/teams/:teamId/join", (req, res) => {
  const session = getSessionFromRequest(req);
  if (!session) {
    return res.status(401).json({ ok: false, error: "not logged in" });
  }

  const result = teamSessionManager.joinTeam(session.user.id, req.params.teamId);
  if (!result.ok) {
    return res.status(400).json(result);
  }

  res.json({
    ok: true,
    user: result.user,
    player: result.player,
    team: result.team,
    teams: result.teams,
  });
});

app.get("/api/posters", (_req, res) => {
  res.json(posterManager.getAllPosters());
});

app.get("/api/posters/:posterId/canvas", (req, res) => {
  const poster = posterManager.getPoster(req.params.posterId);
  if (!poster) {
    return res.status(404).json({ error: "Poster not found" });
  }

  res.json({
    layout: poster.layout,
    location: poster.location,
    audio: poster.audio,
    strokes: poster.strokes,
    stickers: poster.stickers,
  });
});

app.get("/api/posters/:posterId/location", (req, res) => {
  const poster = posterManager.getPoster(req.params.posterId);
  if (!poster) {
    return res.status(404).json({ ok: false, error: "Poster not found" });
  }

  res.json({
    ok: true,
    posterId: poster.id,
    location: poster.location,
  });
});

app.post("/api/posters/:posterId/location", (req, res) => {
  const location = posterManager.setPosterLocation(req.params.posterId, req.body || {});
  if (!location) {
    return res.status(400).json({ ok: false, error: "invalid location payload" });
  }

  io.emit("dashboard_update", buildDashboardUpdate());

  res.json({
    ok: true,
    posterId: req.params.posterId,
    location,
  });
});

app.get("/api/posters/:posterId/audio", (req, res) => {
  const poster = posterManager.getPoster(req.params.posterId);
  if (!poster) {
    return res.status(404).json({ ok: false, error: "Poster not found" });
  }

  res.json({
    ok: true,
    posterId: poster.id,
    audio: poster.audio,
  });
});

app.post("/api/posters/:posterId/audio", (req, res) => {
  const session = getSessionFromRequest(req);
  if (!session?.team) {
    return res.status(401).json({ ok: false, error: "join a team first" });
  }

  const { title, url } = req.body || {};
  if (typeof url !== "string" || !url.trim()) {
    return res.status(400).json({ ok: false, error: "audio url is required" });
  }

  const audio = posterManager.setPosterAudio(req.params.posterId, {
    teamId: session.team.id,
    userId: session.user.id,
    title,
    url,
  });

  if (!audio) {
    return res.status(400).json({ ok: false, error: "invalid audio payload" });
  }

  io.to(`poster:${req.params.posterId}`).emit("poster_audio_updated", {
    posterId: req.params.posterId,
    audio,
  });
  io.emit("dashboard_update", buildDashboardUpdate());

  res.json({ ok: true, posterId: req.params.posterId, audio });
});

app.delete("/api/posters/:posterId/audio", (req, res) => {
  const session = getSessionFromRequest(req);
  if (!session?.team) {
    return res.status(401).json({ ok: false, error: "join a team first" });
  }

  const cleared = posterManager.clearPosterAudio(req.params.posterId);
  if (!cleared) {
    return res.status(404).json({ ok: false, error: "Poster not found" });
  }

  io.to(`poster:${req.params.posterId}`).emit("poster_audio_cleared", {
    posterId: req.params.posterId,
  });
  io.emit("dashboard_update", buildDashboardUpdate());

  res.json({ ok: true, posterId: req.params.posterId });
});

app.post("/api/posters/:posterId/audio/trigger", (req, res) => {
  const poster = posterManager.getPoster(req.params.posterId);
  if (!poster) {
    return res.status(404).json({ ok: false, error: "Poster not found" });
  }

  const session = getSessionFromRequest(req);
  if (!session?.team) {
    return res.status(401).json({ ok: false, error: "join a team first" });
  }
  const viewerTeamId = session?.team?.id || "";
  const audio = poster.audio;
  const shouldPlay = Boolean(audio && viewerTeamId && audio.teamId && audio.teamId !== viewerTeamId);

  res.json({
    ok: true,
    posterId: req.params.posterId,
    shouldPlay,
    audio: shouldPlay ? audio : null,
  });
});

app.get("/api/posters/:posterId/territory", (req, res) => {
  const poster = posterManager.getPoster(req.params.posterId);
  res.json(territoryEngine.getTerritoryState(req.params.posterId, poster?.layout));
});

app.get("/api/leaderboard", (_req, res) => {
  res.json(territoryEngine.getGlobalLeaderboard());
});

app.get("/api/stickers/library", (_req, res) => {
  res.json({
    ok: true,
    stickers: stickerService.getStickerLibrary(),
  });
});

app.post("/api/stickers/generate", async (req, res) => {
  const session = getSessionFromRequest(req);
  if (!session) {
    return res.status(401).json({ ok: false, error: "not logged in" });
  }

  try {
    const result = await stickerService.generateStickerFromPrompt(req.body?.prompt);
    if (!result.ok) {
      return res.status(400).json(result);
    }

    res.json(result);
  } catch (error) {
    res.status(500).json({
      ok: false,
      error: error?.message || "failed to generate sticker",
    });
  }
});

io.on("connection", (socket) => {
  console.log(`[+] Client connected: ${socket.id}`);

  registerCanvasHandlers(
    io,
    socket,
    posterManager,
    territoryEngine,
    () => io.emit("dashboard_update", buildDashboardUpdate())
  );
  registerTerritoryHandlers(io, socket, posterManager, territoryEngine);

  socket.emit("dashboard_update", buildDashboardUpdate());

  socket.on("join_poster", ({ posterId, teamId, username, coordinateMeta } = {}) => {
    if (!posterId) return;

    const session = getSessionFromCookieHeader(socket.handshake.headers.cookie || "");

    socket.join(`poster:${posterId}`);
    socket.data.posterId = posterId;
    socket.data.identityLocked = Boolean(session?.user);
    socket.data.teamId = session?.user ? (session?.team?.id || "unknown") : (teamId || "unknown");
    socket.data.userId = session?.user?.id || socket.id;
    socket.data.username = session?.user?.username || username || socket.id.slice(0, 6);
    socket.data.coordinateMeta = coordinateMeta || null;

    const poster = posterManager.getOrCreatePoster(posterId);

    socket.emit("canvas_state", {
      posterId,
      layout: poster.layout,
      audio: poster.audio,
      strokes: poster.strokes,
      stickers: poster.stickers,
      territory: territoryEngine.getTerritoryState(posterId, poster.layout),
    });

    if (poster.audio && socket.data.teamId && poster.audio.teamId !== socket.data.teamId) {
      socket.emit("poster_audio_trigger", {
        posterId,
        audio: poster.audio,
      });
    }

    socket.to(`poster:${posterId}`).emit("user_joined", {
      userId: socket.id,
      teamId: socket.data.teamId,
      username: socket.data.username,
    });

    io.emit("dashboard_update", buildDashboardUpdate());

    console.log(
      `  -> ${socket.data.username} (${socket.data.teamId}) joined poster ${posterId}`
    );
  });

  socket.on("leave_poster", ({ posterId } = {}) => {
    if (!posterId) return;

    socket.leave(`poster:${posterId}`);
    if (socket.data.posterId === posterId) {
      delete socket.data.posterId;
    }
  });

  socket.on("disconnect", () => {
    console.log(`[-] Client disconnected: ${socket.id}`);
    io.emit("dashboard_update", buildDashboardUpdate());
  });
});

function hydrateState() {
  const savedState = loadState();
  posterManager.hydrate(savedState.posters);
  teamSessionManager.hydrate(savedState);
}

function persistState() {
  saveState({
    posters: posterManager.serialize(),
    ...teamSessionManager.serialize(),
  });
}

function rebuildTerritoryFromPosters() {
  for (const posterId of posterManager.getPosterIds()) {
    const poster = posterManager.getPoster(posterId);
    territoryEngine.syncPosterTerritory(
      posterId,
      poster?.strokes || [],
      poster?.stickers || [],
      poster?.layout
    );
  }
}

function parseCookies(cookieHeader = "") {
  return cookieHeader
    .split(";")
    .map((entry) => entry.trim())
    .filter(Boolean)
    .reduce((acc, entry) => {
      const separatorIndex = entry.indexOf("=");
      if (separatorIndex === -1) return acc;
      const key = entry.slice(0, separatorIndex).trim();
      const value = entry.slice(separatorIndex + 1).trim();
      acc[key] = decodeURIComponent(value);
      return acc;
    }, {});
}

function getCookie(req, name) {
  return parseCookies(req.headers.cookie || "")[name] || null;
}

function getSessionFromRequest(req) {
  const token = getCookie(req, SESSION_COOKIE);
  return teamSessionManager.getSessionBundle(token);
}

function getSessionFromCookieHeader(cookieHeader) {
  const token = parseCookies(cookieHeader || "")[SESSION_COOKIE] || null;
  return teamSessionManager.getSessionBundle(token);
}

function setSessionCookie(res, token) {
  const parts = [
    `${SESSION_COOKIE}=${encodeURIComponent(token)}`,
    "Path=/",
    `Max-Age=${Math.floor(COOKIE_MAX_AGE_MS / 1000)}`,
    "HttpOnly",
    "SameSite=Lax",
  ];
  res.setHeader("Set-Cookie", parts.join("; "));
}

function clearSessionCookie(res) {
  res.setHeader(
    "Set-Cookie",
    `${SESSION_COOKIE}=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax`
  );
}

function buildDashboardUpdate() {
  return {
    posters: posterManager.getAllPosters().map((poster) => ({
      ...poster,
      territory: territoryEngine.getTerritoryState(poster.id, poster.layout),
    })),
    leaderboard: territoryEngine.getGlobalLeaderboard(),
    connectedClients: io.engine.clientsCount,
  };
}

module.exports = { io, buildDashboardUpdate, app };

httpServer.listen(PORT, "0.0.0.0", () => {
  console.log("\niTEC OVERRIDE backend running");
  console.log(`Local:   http://localhost:${PORT}`);
  console.log(`Network: http://<your-LAN-ip>:${PORT}`);
  console.log(`Admin:   http://localhost:${PORT}/\n`);
});
