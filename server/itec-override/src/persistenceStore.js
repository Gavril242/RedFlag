const fs = require("fs");
const path = require("path");

const DATA_DIR = path.join(__dirname, "../data");
const STATE_FILE = path.join(DATA_DIR, "state.json");

const DEFAULT_STATE = Object.freeze({
  posters: [],
  teams: [],
  users: [],
  players: [],
  sessions: [],
});

function ensureDir() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

function normalizeState(state = {}) {
  return {
    posters: Array.isArray(state.posters) ? state.posters : [],
    teams: Array.isArray(state.teams) ? state.teams : [],
    users: Array.isArray(state.users) ? state.users : [],
    players: Array.isArray(state.players) ? state.players : [],
    sessions: Array.isArray(state.sessions) ? state.sessions : [],
  };
}

function loadState() {
  ensureDir();

  if (!fs.existsSync(STATE_FILE)) {
    return normalizeState(DEFAULT_STATE);
  }

  try {
    const raw = fs.readFileSync(STATE_FILE, "utf8");
    return normalizeState(JSON.parse(raw));
  } catch (_error) {
    return normalizeState(DEFAULT_STATE);
  }
}

function saveState(state) {
  ensureDir();
  const normalized = normalizeState(state);
  const tmpFile = `${STATE_FILE}.tmp`;
  fs.writeFileSync(tmpFile, JSON.stringify(normalized, null, 2), "utf8");
  fs.renameSync(tmpFile, STATE_FILE);
}

module.exports = { loadState, saveState, STATE_FILE };
