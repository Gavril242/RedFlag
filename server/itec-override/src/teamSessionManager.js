const crypto = require("crypto");

const state = {
  teams: [],
  users: [],
  sessions: [],
};

const LEGACY_TEAM_IDS = new Set(["red", "blue", "green", "yellow"]);
const LEGACY_TEAM_NAMES = new Set(["red team", "blue team", "green team", "yellow team"]);

let persistenceHook = () => {};

function setPersistenceHook(callback) {
  persistenceHook = typeof callback === "function" ? callback : () => {};
}

function persist() {
  persistenceHook();
}

function sanitizeText(value, fallback = "") {
  if (typeof value !== "string") return fallback;
  const trimmed = value.trim();
  return trimmed || fallback;
}

function slugifyTeamName(name) {
  return sanitizeText(name, "team")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "") || "team";
}

function hashPassword(password) {
  return crypto.createHash("sha256").update(password).digest("hex");
}

function sanitizeTeam(team = {}) {
  const name = sanitizeText(team.name, "Team");
  return {
    id: sanitizeText(team.id, `team-${crypto.randomUUID()}`),
    name,
    anthemTitle: sanitizeText(team.anthemTitle, ""),
    anthemUrl: sanitizeText(team.anthemUrl, ""),
    ownerUserId: sanitizeText(team.ownerUserId, ""),
    createdAt: Number.isFinite(team.createdAt) ? team.createdAt : Date.now(),
  };
}

function sanitizeUser(user = {}) {
  return {
    id: sanitizeText(user.id, `user_${crypto.randomUUID()}`),
    username: sanitizeText(user.username, "guest"),
    passwordHash: sanitizeText(user.passwordHash, ""),
    teamId: sanitizeText(user.teamId, "") || null,
    createdAt: Number.isFinite(user.createdAt) ? user.createdAt : Date.now(),
  };
}

function sanitizeSession(session = {}) {
  return {
    token: sanitizeText(session.token, crypto.randomBytes(24).toString("hex")),
    userId: sanitizeText(session.userId || session.playerId, ""),
    createdAt: Number.isFinite(session.createdAt) ? session.createdAt : Date.now(),
    lastSeenAt: Number.isFinite(session.lastSeenAt) ? session.lastSeenAt : Date.now(),
  };
}

function hydrate(data = {}) {
  state.teams = Array.isArray(data.teams)
    ? data.teams
        .filter(Boolean)
        .map(sanitizeTeam)
        .filter((team) => {
          const isLegacyDefault =
            !team.ownerUserId &&
            (LEGACY_TEAM_IDS.has(team.id.toLowerCase()) || LEGACY_TEAM_NAMES.has(team.name.toLowerCase()));
          return !isLegacyDefault;
        })
    : [];

  const rawUsers = Array.isArray(data.users)
    ? data.users
    : Array.isArray(data.players)
      ? data.players.map((player) => ({
          id: player.id,
          username: player.username,
          passwordHash: player.passwordHash || "",
          teamId: player.teamId,
          createdAt: player.createdAt,
        }))
      : [];

  state.users = rawUsers
    .filter((user) => user?.id && user?.username)
    .map(sanitizeUser);

  state.sessions = Array.isArray(data.sessions)
    ? data.sessions
        .filter((session) => session?.token && (session?.userId || session?.playerId))
        .map(sanitizeSession)
    : [];
}

function serialize() {
  return {
    teams: state.teams.map((team) => ({ ...team })),
    users: state.users.map((user) => ({ ...user })),
    sessions: state.sessions.map((session) => ({ ...session })),
  };
}

function getUserById(userId) {
  return state.users.find((user) => user.id === userId) || null;
}

function getUserByUsername(username) {
  const normalized = sanitizeText(username, "").toLowerCase();
  return state.users.find((user) => user.username.toLowerCase() === normalized) || null;
}

function getTeamById(teamId) {
  return state.teams.find((team) => team.id === teamId) || null;
}

function createSession(userId) {
  const session = {
    token: crypto.randomBytes(24).toString("hex"),
    userId,
    createdAt: Date.now(),
    lastSeenAt: Date.now(),
  };
  state.sessions.push(session);
  return session;
}

function teamView(team) {
  if (!team) return null;
  const memberCount = state.users.filter((user) => user.teamId === team.id).length;
  return {
    id: team.id,
    name: team.name,
    anthemTitle: team.anthemTitle || "",
    anthemUrl: team.anthemUrl || "",
    ownerUserId: team.ownerUserId || "",
    memberCount,
    joinable: true,
  };
}

function sessionBundleForUser(user, session) {
  const team = user?.teamId ? getTeamById(user.teamId) : null;
  return {
    session,
    user,
    player: user,
    team: teamView(team),
  };
}

function register(username, password) {
  const normalizedUsername = sanitizeText(username, "");
  const normalizedPassword = sanitizeText(password, "");

  if (!normalizedUsername) {
    return { ok: false, error: "username is required" };
  }

  if (normalizedPassword.length < 4) {
    return { ok: false, error: "password must be at least 4 characters" };
  }

  const existing = getUserByUsername(normalizedUsername);
  if (existing && existing.passwordHash) {
    return { ok: false, error: "username already exists" };
  }

  let user = existing;
  if (!user) {
    user = sanitizeUser({
      id: `user_${crypto.randomUUID()}`,
      username: normalizedUsername,
      passwordHash: hashPassword(normalizedPassword),
      teamId: null,
      createdAt: Date.now(),
    });
    state.users.push(user);
  } else {
    user.passwordHash = hashPassword(normalizedPassword);
  }

  const session = createSession(user.id);
  persist();
  return { ok: true, ...sessionBundleForUser(user, session) };
}

function login(username, password) {
  const normalizedUsername = sanitizeText(username, "");
  const normalizedPassword = sanitizeText(password, "");

  const user = getUserByUsername(normalizedUsername);
  if (!user) {
    return { ok: false, error: "invalid username or password" };
  }

  const passwordHash = hashPassword(normalizedPassword);
  if (user.passwordHash) {
    if (user.passwordHash !== passwordHash) {
      return { ok: false, error: "invalid username or password" };
    }
  } else {
    user.passwordHash = passwordHash;
  }

  const session = createSession(user.id);
  persist();
  return { ok: true, ...sessionBundleForUser(user, session) };
}

function getSessionBundle(token) {
  if (!token) return null;

  const session = state.sessions.find((entry) => entry.token === token);
  if (!session) return null;

  const user = getUserById(session.userId);
  if (!user) return null;

  session.lastSeenAt = Date.now();
  persist();
  return sessionBundleForUser(user, session);
}

function listTeams() {
  return state.teams
    .map(teamView)
    .sort((a, b) => a.name.localeCompare(b.name));
}

function createTeam(userId, payload = {}) {
  const user = getUserById(userId);
  if (!user) {
    return { ok: false, error: "user not found" };
  }

  const name = sanitizeText(payload.name, "");
  if (!name) {
    return { ok: false, error: "team name is required" };
  }

  const normalizedName = name.toLowerCase();
  const existingByName = state.teams.find((team) => team.name.toLowerCase() === normalizedName);
  if (existingByName) {
    return { ok: false, error: "team name already exists" };
  }

  let id = slugifyTeamName(name);
  let suffix = 2;
  while (getTeamById(id)) {
    id = `${slugifyTeamName(name)}-${suffix}`;
    suffix += 1;
  }

  const team = sanitizeTeam({
    id,
    name,
    anthemTitle: payload.anthemTitle,
    anthemUrl: payload.anthemUrl,
    ownerUserId: user.id,
    createdAt: Date.now(),
  });

  state.teams.push(team);
  user.teamId = team.id;
  persist();

  return {
    ok: true,
    team: teamView(team),
    user,
    player: user,
    teams: listTeams(),
  };
}

function joinTeam(userId, teamId) {
  const user = getUserById(userId);
  if (!user) {
    return { ok: false, error: "user not found" };
  }

  const team = getTeamById(teamId);
  if (!team) {
    return { ok: false, error: "team not found" };
  }

  user.teamId = team.id;
  persist();
  return {
    ok: true,
    user,
    player: user,
    team: teamView(team),
    teams: listTeams(),
  };
}

function logout(token) {
  const index = state.sessions.findIndex((session) => session.token === token);
  if (index === -1) return false;
  state.sessions.splice(index, 1);
  persist();
  return true;
}

module.exports = {
  teamSessionManager: {
    hydrate,
    serialize,
    setPersistenceHook,
    register,
    login,
    logout,
    listTeams,
    createTeam,
    joinTeam,
    getSessionBundle,
    getTeamById,
  },
};
