/**
 * canvasHandlers
 * Registers all canvas-related Socket.IO events on a single socket.
 *
 * Events FROM Unity client → server:
 *   draw_stroke   { posterId, teamId, userId, color, width, points }
 *   place_sticker { posterId, teamId, userId, url, x, y, width, height, rotation }
 *   remove_sticker{ posterId, stickerId }
 *   clear_canvas  { posterId, adminKey }
 *
 * Events FROM server → Unity clients (broadcast):
 *   stroke_added   { posterId, stroke }
 *   sticker_added  { posterId, sticker }
 *   sticker_removed{ posterId, stickerId }
 *   canvas_cleared { posterId }
 *   territory_update { posterId, territory }
 */

const ADMIN_KEY = process.env.ADMIN_KEY || "itec2026";

function registerCanvasHandlers(
  io,
  socket,
  posterManager,
  territoryEngine,
  notifyDashboard = () => {}
) {
  function resolveActor(data = {}) {
    if (socket.data.identityLocked) {
      return {
        teamId: socket.data.teamId || "unknown",
        userId: socket.data.userId || socket.id,
      };
    }

    return {
      teamId: data.teamId || socket.data.teamId || "unknown",
      userId: data.userId || socket.data.userId || socket.id,
    };
  }

  // ── draw_stroke ───────────────────────────────────────────────────────
  socket.on("draw_stroke", (data, ack) => {
    const {
      posterId,
      teamId,
      userId,
      color,
      width,
      points,
      coordinateMeta,
    } = data || {};

    if (!posterId || !Array.isArray(points) || points.length === 0) {
      if (typeof ack === "function") ack({ ok: false, error: "invalid payload" });
      return;
    }

    const actor = resolveActor(data);
    const stroke = posterManager.addStroke(posterId, {
      teamId: actor.teamId,
      userId: actor.userId,
      color,
      width,
      points,
      coordinateMeta: coordinateMeta || socket.data.coordinateMeta,
    });

    // Update territory ownership
    const poster = posterManager.getPoster(posterId);
    territoryEngine.syncPosterTerritory(
      posterId,
      poster?.strokes || [],
      poster?.stickers || [],
      poster?.layout
    );

    // Broadcast stroke to everyone else viewing the same poster
    socket.to(`poster:${posterId}`).emit("stroke_added", { posterId, stroke });

    // Broadcast updated territory to the whole room (incl. sender)
    const territory = territoryEngine.getTerritoryState(posterId);
    io.to(`poster:${posterId}`).emit("territory_update", { posterId, territory });

    notifyDashboard();

    if (typeof ack === "function") {
      ack({ ok: true, strokeId: stroke.id, stroke, territory });
    }
  });

  // ── place_sticker ─────────────────────────────────────────────────────
  socket.on("place_sticker", (data, ack) => {
    const {
      posterId,
      teamId,
      userId,
      url,
      x,
      y,
      width,
      height,
      rotation,
      coordinateMeta,
    } = data || {};

    if (!posterId || !url) {
      if (typeof ack === "function") ack({ ok: false, error: "invalid payload" });
      return;
    }

    const actor = resolveActor(data);
    const sticker = posterManager.addSticker(posterId, {
      teamId: actor.teamId,
      userId: actor.userId,
      url,
      x,
      y,
      width,
      height,
      rotation,
      coordinateMeta: coordinateMeta || socket.data.coordinateMeta,
    });

    const poster = posterManager.getPoster(posterId);
    territoryEngine.syncPosterTerritory(
      posterId,
      poster?.strokes || [],
      poster?.stickers || [],
      poster?.layout
    );

    io.to(`poster:${posterId}`).emit("sticker_added", { posterId, sticker });
    const territory = territoryEngine.getTerritoryState(posterId, poster?.layout);
    io.to(`poster:${posterId}`).emit("territory_update", { posterId, territory });
    notifyDashboard();

    if (typeof ack === "function") ack({ ok: true, stickerId: sticker.id, sticker, territory });
  });

  // ── remove_sticker ────────────────────────────────────────────────────
  socket.on("remove_sticker", (data, ack) => {
    const { posterId, stickerId } = data || {};

    if (!posterId || !stickerId) {
      if (typeof ack === "function") ack({ ok: false, error: "invalid payload" });
      return;
    }

    const removed = posterManager.removeSticker(posterId, stickerId);
    if (removed) {
      const poster = posterManager.getPoster(posterId);
      territoryEngine.syncPosterTerritory(
        posterId,
        poster?.strokes || [],
        poster?.stickers || [],
        poster?.layout
      );
      io.to(`poster:${posterId}`).emit("sticker_removed", { posterId, stickerId });
      const territory = territoryEngine.getTerritoryState(posterId, poster?.layout);
      io.to(`poster:${posterId}`).emit("territory_update", { posterId, territory });
      notifyDashboard();
    }

    if (typeof ack === "function") ack({ ok: removed, stickerId });
  });

  // ── clear_canvas (admin) ──────────────────────────────────────────────
  socket.on("clear_canvas", (data, ack) => {
    const { posterId, adminKey } = data || {};

    if (adminKey !== ADMIN_KEY) {
      if (typeof ack === "function") ack({ ok: false, error: "unauthorized" });
      return;
    }

    if (!posterId) {
      if (typeof ack === "function") ack({ ok: false, error: "invalid payload" });
      return;
    }

    const cleared = posterManager.clearPoster(posterId);
    if (!cleared) {
      if (typeof ack === "function") ack({ ok: false, error: "poster not found" });
      return;
    }

    territoryEngine.resetTerritory(posterId);

    io.to(`poster:${posterId}`).emit("canvas_cleared", { posterId });
    notifyDashboard();

    if (typeof ack === "function") ack({ ok: true, posterId });
  });
}

module.exports = { registerCanvasHandlers };
