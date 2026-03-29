/**
 * territoryHandlers
 * Registers territory-query Socket.IO events on a single socket.
 *
 * Events FROM Unity client → server:
 *   get_territory     { posterId }          → territory_state
 *   get_leaderboard   {}                    → leaderboard_state
 *
 * Events FROM server → client (response):
 *   territory_state   { posterId, territory }
 *   leaderboard_state { leaderboard }
 */

function registerTerritoryHandlers(io, socket, _posterManager, territoryEngine) {

  socket.on("get_territory", (data, ack) => {
    const posterId = data?.posterId || socket.data.posterId;
    if (!posterId) {
      if (typeof ack === "function") ack({ ok: false, error: "no posterId" });
      return;
    }

    const territory = territoryEngine.getTerritoryState(posterId);
    socket.emit("territory_state", { posterId, territory });

    if (typeof ack === "function") ack({ ok: true, territory });
  });

  socket.on("get_leaderboard", (_data, ack) => {
    const leaderboard = territoryEngine.getGlobalLeaderboard();
    socket.emit("leaderboard_state", { leaderboard });

    if (typeof ack === "function") ack({ ok: true, leaderboard });
  });
}

module.exports = { registerTerritoryHandlers };
