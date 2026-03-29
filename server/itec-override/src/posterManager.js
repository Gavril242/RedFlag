/**
 * posterManager
 * In-memory store for every "Anchor Poster" canvas.
 * Each poster holds its list of strokes and stickers.
 */

const MAX_STROKES_PER_POSTER = 5000;
const A4_WIDTH = 1000;
const A4_HEIGHT = Math.round(A4_WIDTH * Math.sqrt(2));
const DEFAULT_POSTER_LAYOUT = Object.freeze({
  width: A4_WIDTH,
  height: A4_HEIGHT,
  aspectRatio: A4_WIDTH / A4_HEIGHT,
  origin: "top-left",
});

const posters = new Map();
let persistenceHook = () => {};

function setPersistenceHook(callback) {
  persistenceHook = typeof callback === "function" ? callback : () => {};
}

function persist() {
  persistenceHook();
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function finiteNumber(value, fallback) {
  return Number.isFinite(value) ? value : fallback;
}

function parseCoordinateMeta(meta = {}) {
  const sourceWidth = finiteNumber(meta.sourceWidth, NaN);
  const sourceHeight = finiteNumber(meta.sourceHeight, NaN);
  const viewportX = finiteNumber(meta.viewportX, 0);
  const viewportY = finiteNumber(meta.viewportY, 0);
  const viewportWidth = finiteNumber(
    meta.viewportWidth,
    Number.isFinite(sourceWidth) ? sourceWidth : NaN
  );
  const viewportHeight = finiteNumber(
    meta.viewportHeight,
    Number.isFinite(sourceHeight) ? sourceHeight : NaN
  );

  return {
    coordinateSpace: meta.coordinateSpace === "pixels" ? "pixels" : "normalized",
    origin: meta.origin === "bottom-left" ? "bottom-left" : "top-left",
    flipX: Boolean(meta.flipX),
    flipY: Boolean(meta.flipY),
    sourceWidth,
    sourceHeight,
    viewportX,
    viewportY,
    viewportWidth,
    viewportHeight,
  };
}

function normalizeAxis(value, size, offset, span) {
  const safeSpan = Number.isFinite(span) && span > 0 ? span : size;
  if (!Number.isFinite(value) || !Number.isFinite(safeSpan) || safeSpan <= 0) {
    return null;
  }

  return (value - offset) / safeSpan;
}

function normalizePoint(point, coordinateMeta = {}) {
  if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y)) {
    return null;
  }

  const meta = parseCoordinateMeta(coordinateMeta);
  let x = point.x;
  let y = point.y;

  if (meta.coordinateSpace === "pixels") {
    x = normalizeAxis(x, meta.sourceWidth, meta.viewportX, meta.viewportWidth);
    y = normalizeAxis(y, meta.sourceHeight, meta.viewportY, meta.viewportHeight);
  }

  if (!Number.isFinite(x) || !Number.isFinite(y)) {
    return null;
  }

  if (meta.origin === "bottom-left") {
    y = 1 - y;
  }

  if (meta.flipX) x = 1 - x;
  if (meta.flipY) y = 1 - y;

  return {
    x: clamp(x, 0, 1),
    y: clamp(y, 0, 1),
  };
}

function sanitizeLayout(layout = {}) {
  const width = clamp(finiteNumber(layout.width, DEFAULT_POSTER_LAYOUT.width), 1, 10000);
  const height = clamp(finiteNumber(layout.height, DEFAULT_POSTER_LAYOUT.height), 1, 10000);

  return {
    width,
    height,
    aspectRatio: width / height,
    origin: layout.origin === "bottom-left" ? "bottom-left" : DEFAULT_POSTER_LAYOUT.origin,
  };
}

function sanitizeLocation(location = null) {
  if (!location || typeof location !== "object") return null;

  const lat = finiteNumber(location.lat, NaN);
  const lng = finiteNumber(location.lng, NaN);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return null;
  }

  return {
    lat: clamp(lat, -90, 90),
    lng: clamp(lng, -180, 180),
    label: typeof location.label === "string" && location.label.trim()
      ? location.label.trim()
      : "",
  };
}

function clonePoster(poster) {
  return {
    id: poster.id,
    createdAt: poster.createdAt,
    layout: sanitizeLayout(poster.layout),
    location: sanitizeLocation(poster.location),
    audio: sanitizeAudio(poster.audio),
    strokes: Array.isArray(poster.strokes) ? poster.strokes.map((stroke) => ({
      ...stroke,
      coordinateMeta: parseCoordinateMeta(stroke.coordinateMeta),
      points: Array.isArray(stroke.points)
        ? stroke.points.map((point) => normalizePoint(point)).filter(Boolean)
        : [],
    })) : [],
    stickers: Array.isArray(poster.stickers) ? poster.stickers.map((sticker) => ({
      ...sticker,
      coordinateMeta: parseCoordinateMeta(sticker.coordinateMeta),
      x: clamp(finiteNumber(sticker.x, 0.5), 0, 1),
      y: clamp(finiteNumber(sticker.y, 0.5), 0, 1),
      width: clamp(finiteNumber(sticker.width, 0.1), 0.01, 1),
      height: clamp(finiteNumber(sticker.height, 0.1), 0.01, 1),
      rotation: finiteNumber(sticker.rotation, 0),
    })) : [],
  };
}

function sanitizeAudio(audio = null) {
  if (!audio || typeof audio !== "object") return null;

  const url = typeof audio.url === "string" ? audio.url.trim() : "";
  if (!url) return null;

  return {
    teamId: typeof audio.teamId === "string" && audio.teamId.trim() ? audio.teamId.trim() : "unknown",
    userId: typeof audio.userId === "string" && audio.userId.trim() ? audio.userId.trim() : "unknown",
    title: typeof audio.title === "string" && audio.title.trim() ? audio.title.trim() : "Poster Audio",
    url,
    ts: finiteNumber(audio.ts, Date.now()),
  };
}

function hydrate(serializedPosters = []) {
  posters.clear();

  for (const rawPoster of serializedPosters) {
    if (!rawPoster?.id) continue;
    const poster = clonePoster({
      id: rawPoster.id,
      createdAt: finiteNumber(rawPoster.createdAt, Date.now()),
      layout: rawPoster.layout,
      location: rawPoster.location,
      audio: rawPoster.audio,
      strokes: rawPoster.strokes,
      stickers: rawPoster.stickers,
    });
    posters.set(poster.id, poster);
  }
}

function serialize() {
  return Array.from(posters.values()).map((poster) => clonePoster(poster));
}

function getOrCreatePoster(posterId) {
  if (!posters.has(posterId)) {
    posters.set(posterId, {
      id: posterId,
      createdAt: Date.now(),
      layout: { ...DEFAULT_POSTER_LAYOUT },
      location: null,
      audio: null,
      strokes: [],
      stickers: [],
    });
    persist();
  }
  return posters.get(posterId);
}

function getPoster(posterId) {
  return posters.get(posterId) || null;
}

function getAllPosters() {
  return Array.from(posters.values()).map((p) => ({
    id: p.id,
    createdAt: p.createdAt,
    layout: p.layout,
    location: p.location,
    audio: p.audio,
    strokeCount: p.strokes.length,
    stickerCount: p.stickers.length,
  }));
}

function getPosterIds() {
  return Array.from(posters.keys());
}

function addStroke(posterId, stroke) {
  const poster = getOrCreatePoster(posterId);

  if (poster.strokes.length >= MAX_STROKES_PER_POSTER) {
    poster.strokes.splice(0, Math.floor(MAX_STROKES_PER_POSTER * 0.1));
  }

  const coordinateMeta = parseCoordinateMeta(stroke.coordinateMeta);
  const stored = {
    id: stroke.id || `s_${Date.now()}_${Math.random().toString(36).slice(2)}`,
    teamId: stroke.teamId || "unknown",
    userId: stroke.userId || "unknown",
    color: stroke.color || "#ffffff",
    width: Math.min(Math.max(stroke.width || 4, 1), 64),
    points: Array.isArray(stroke.points)
      ? stroke.points.map((point) => normalizePoint(point, coordinateMeta)).filter(Boolean)
      : [],
    coordinateMeta,
    ts: Date.now(),
  };

  poster.strokes.push(stored);
  persist();
  return stored;
}

function addSticker(posterId, sticker) {
  const poster = getOrCreatePoster(posterId);
  const coordinateMeta = parseCoordinateMeta(sticker.coordinateMeta);
  const anchor =
    normalizePoint(
      { x: finiteNumber(sticker.x, 0.5), y: finiteNumber(sticker.y, 0.5) },
      coordinateMeta
    ) || { x: 0.5, y: 0.5 };

  const stored = {
    id: sticker.id || `st_${Date.now()}_${Math.random().toString(36).slice(2)}`,
    teamId: sticker.teamId || "unknown",
    userId: sticker.userId || "unknown",
    url: typeof sticker.url === "string" ? sticker.url : "",
    x: anchor.x,
    y: anchor.y,
    width: clamp(finiteNumber(sticker.width, 0.1), 0.01, 1),
    height: clamp(finiteNumber(sticker.height, 0.1), 0.01, 1),
    rotation: finiteNumber(sticker.rotation, 0),
    coordinateMeta,
    ts: Date.now(),
  };

  poster.stickers.push(stored);
  persist();
  return stored;
}

function setPosterAudio(posterId, audio) {
  const poster = getOrCreatePoster(posterId);
  const stored = sanitizeAudio({
    teamId: audio.teamId,
    userId: audio.userId,
    title: audio.title,
    url: audio.url,
    ts: Date.now(),
  });

  if (!stored) return null;

  poster.audio = stored;
  persist();
  return stored;
}

function setPosterLocation(posterId, location) {
  const poster = getOrCreatePoster(posterId);
  const stored = sanitizeLocation(location);
  if (!stored) return null;
  poster.location = stored;
  persist();
  return stored;
}

function clearPosterAudio(posterId) {
  const poster = getPoster(posterId);
  if (!poster) return false;
  poster.audio = null;
  persist();
  return true;
}

function removeSticker(posterId, stickerId) {
  const poster = getPoster(posterId);
  if (!poster) return false;
  const idx = poster.stickers.findIndex((s) => s.id === stickerId);
  if (idx === -1) return false;
  poster.stickers.splice(idx, 1);
  persist();
  return true;
}

function clearPoster(posterId) {
  const poster = getPoster(posterId);
  if (!poster) return false;
  poster.strokes = [];
  poster.stickers = [];
  poster.audio = null;
  persist();
  return true;
}

module.exports = {
  posterManager: {
    getOrCreatePoster,
    getPoster,
    getAllPosters,
    getPosterIds,
    addStroke,
    addSticker,
    setPosterLocation,
    setPosterAudio,
    clearPosterAudio,
    removeSticker,
    clearPoster,
    normalizePoint,
    DEFAULT_POSTER_LAYOUT,
    hydrate,
    serialize,
    setPersistenceHook,
  },
};
