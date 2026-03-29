/**
 * territoryEngine
 *
 * Territory is based on final visible coverage, not additive contribution.
 * We rasterize strokes and stickers onto a logical poster grid and the last
 * writer wins each cell. This prevents overlap from being counted twice and
 * keeps percentages aligned with what users actually see.
 */

const DEFAULT_LAYOUT = {
  width: 1000,
  height: Math.round(1000 * Math.sqrt(2)),
};

const TARGET_CELL_SIZE_PX = 10;
const MIN_GRID_WIDTH = 60;
const MIN_GRID_HEIGHT = 90;

const posterTerritory = new Map();

function normalizeLayout(layout = {}) {
  return {
    width: Number.isFinite(layout.width) && layout.width > 0 ? layout.width : DEFAULT_LAYOUT.width,
    height: Number.isFinite(layout.height) && layout.height > 0 ? layout.height : DEFAULT_LAYOUT.height,
  };
}

function buildGrid(layout = DEFAULT_LAYOUT) {
  const normalized = normalizeLayout(layout);
  const cols = Math.max(MIN_GRID_WIDTH, Math.round(normalized.width / TARGET_CELL_SIZE_PX));
  const rows = Math.max(MIN_GRID_HEIGHT, Math.round(normalized.height / TARGET_CELL_SIZE_PX));
  const cellWidth = normalized.width / cols;
  const cellHeight = normalized.height / rows;

  return {
    width: normalized.width,
    height: normalized.height,
    cols,
    rows,
    cellWidth,
    cellHeight,
    totalCells: cols * rows,
  };
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function cellIndex(col, row, grid) {
  return row * grid.cols + col;
}

function pointToPosterPx(point, grid) {
  return {
    x: point.x * grid.width,
    y: point.y * grid.height,
  };
}

function cellCenterPx(col, row, grid) {
  return {
    x: (col + 0.5) * grid.cellWidth,
    y: (row + 0.5) * grid.cellHeight,
  };
}

function distToSegmentSquared(point, start, end) {
  const dx = end.x - start.x;
  const dy = end.y - start.y;

  if (dx === 0 && dy === 0) {
    const px = point.x - start.x;
    const py = point.y - start.y;
    return px * px + py * py;
  }

  const t = clamp(
    ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy),
    0,
    1
  );

  const nearestX = start.x + t * dx;
  const nearestY = start.y + t * dy;
  const px = point.x - nearestX;
  const py = point.y - nearestY;
  return px * px + py * py;
}

function paintStroke(ownerGrid, stroke, teamIndex, grid) {
  const points = Array.isArray(stroke?.points) ? stroke.points : [];
  if (!points.length) return;

  const radiusPx = Math.max(1, Number.isFinite(stroke?.width) ? stroke.width : 4) / 2;
  const radiusX = Math.ceil(radiusPx / grid.cellWidth);
  const radiusY = Math.ceil(radiusPx / grid.cellHeight);

  if (points.length === 1) {
    const center = pointToPosterPx(points[0], grid);
    const centerCol = clamp(Math.floor(center.x / grid.cellWidth), 0, grid.cols - 1);
    const centerRow = clamp(Math.floor(center.y / grid.cellHeight), 0, grid.rows - 1);

    for (let row = Math.max(0, centerRow - radiusY); row <= Math.min(grid.rows - 1, centerRow + radiusY); row++) {
      for (let col = Math.max(0, centerCol - radiusX); col <= Math.min(grid.cols - 1, centerCol + radiusX); col++) {
        const cellCenter = cellCenterPx(col, row, grid);
        const dx = cellCenter.x - center.x;
        const dy = cellCenter.y - center.y;
        if ((dx * dx + dy * dy) <= radiusPx * radiusPx) {
          ownerGrid[cellIndex(col, row, grid)] = teamIndex;
        }
      }
    }
    return;
  }

  for (let i = 1; i < points.length; i++) {
    const start = pointToPosterPx(points[i - 1], grid);
    const end = pointToPosterPx(points[i], grid);
    const minX = Math.min(start.x, end.x) - radiusPx;
    const maxX = Math.max(start.x, end.x) + radiusPx;
    const minY = Math.min(start.y, end.y) - radiusPx;
    const maxY = Math.max(start.y, end.y) + radiusPx;

    const colStart = clamp(Math.floor(minX / grid.cellWidth), 0, grid.cols - 1);
    const colEnd = clamp(Math.floor(maxX / grid.cellWidth), 0, grid.cols - 1);
    const rowStart = clamp(Math.floor(minY / grid.cellHeight), 0, grid.rows - 1);
    const rowEnd = clamp(Math.floor(maxY / grid.cellHeight), 0, grid.rows - 1);

    for (let row = rowStart; row <= rowEnd; row++) {
      for (let col = colStart; col <= colEnd; col++) {
        const cellCenter = cellCenterPx(col, row, grid);
        if (distToSegmentSquared(cellCenter, start, end) <= radiusPx * radiusPx) {
          ownerGrid[cellIndex(col, row, grid)] = teamIndex;
        }
      }
    }
  }
}

function paintSticker(ownerGrid, sticker, teamIndex, grid) {
  if (!sticker) return;

  const widthPx = Math.max(0, (Number.isFinite(sticker.width) ? sticker.width : 0) * grid.width);
  const heightPx = Math.max(0, (Number.isFinite(sticker.height) ? sticker.height : 0) * grid.height);
  if (widthPx <= 0 || heightPx <= 0) return;

  const centerX = (Number.isFinite(sticker.x) ? sticker.x : 0.5) * grid.width;
  const centerY = (Number.isFinite(sticker.y) ? sticker.y : 0.5) * grid.height;
  const left = centerX - widthPx / 2;
  const right = centerX + widthPx / 2;
  const top = centerY - heightPx / 2;
  const bottom = centerY + heightPx / 2;

  const colStart = clamp(Math.floor(left / grid.cellWidth), 0, grid.cols - 1);
  const colEnd = clamp(Math.floor(right / grid.cellWidth), 0, grid.cols - 1);
  const rowStart = clamp(Math.floor(top / grid.cellHeight), 0, grid.rows - 1);
  const rowEnd = clamp(Math.floor(bottom / grid.cellHeight), 0, grid.rows - 1);

  for (let row = rowStart; row <= rowEnd; row++) {
    for (let col = colStart; col <= colEnd; col++) {
      ownerGrid[cellIndex(col, row, grid)] = teamIndex;
    }
  }
}

function syncPosterTerritory(posterId, strokes = [], stickers = [], layout = DEFAULT_LAYOUT) {
  const grid = buildGrid(layout);
  const operations = [
    ...strokes.map((stroke) => ({ type: "stroke", item: stroke, ts: Number.isFinite(stroke?.ts) ? stroke.ts : 0 })),
    ...stickers.map((sticker) => ({ type: "sticker", item: sticker, ts: Number.isFinite(sticker?.ts) ? sticker.ts : 0 })),
  ].sort((a, b) => a.ts - b.ts);

  const ownerGrid = new Int32Array(grid.totalCells);
  ownerGrid.fill(-1);

  const teamIndexes = new Map();
  const teamIds = [];

  function ensureTeamIndex(teamId) {
    if (!teamIndexes.has(teamId)) {
      teamIndexes.set(teamId, teamIds.length);
      teamIds.push(teamId);
    }
    return teamIndexes.get(teamId);
  }

  for (const operation of operations) {
    const teamId = operation.item?.teamId || "unknown";
    const teamIndex = ensureTeamIndex(teamId);

    if (operation.type === "stroke") {
      paintStroke(ownerGrid, operation.item, teamIndex, grid);
    } else {
      paintSticker(ownerGrid, operation.item, teamIndex, grid);
    }
  }

  const counts = new Map();
  for (const teamIndex of ownerGrid) {
    if (teamIndex < 0) continue;
    const teamId = teamIds[teamIndex];
    counts.set(teamId, (counts.get(teamId) || 0) + 1);
  }

  if (counts.size === 0) {
    posterTerritory.delete(posterId);
    return;
  }

  posterTerritory.set(posterId, {
    counts,
    totalCells: grid.totalCells,
  });
}

function recordStroke(posterId, stroke, layout = DEFAULT_LAYOUT) {
  syncPosterTerritory(posterId, [stroke], [], layout);
}

function getTerritoryState(posterId) {
  const state = posterTerritory.get(posterId);
  const counts = state?.counts || new Map();
  const totalCells = state?.totalCells || 0;

  const rawArea = {};
  let totalCoveredCells = 0;

  for (const [teamId, count] of counts) {
    rawArea[teamId] = totalCells > 0 ? (count / totalCells) * 100 : 0;
    totalCoveredCells += count;
  }

  const shares = {};
  let owner = null;
  let maxCount = 0;

  for (const [teamId, count] of counts) {
    shares[teamId] = totalCoveredCells > 0 ? count / totalCoveredCells : 0;
    if (count > maxCount) {
      maxCount = count;
      owner = teamId;
    }
  }

  return { posterId, owner, teams: shares, rawArea };
}

function getGlobalLeaderboard() {
  const totalArea = {};
  const posterWins = {};

  for (const [, state] of posterTerritory) {
    let posterMax = 0;
    let posterOwner = null;

    for (const [teamId, count] of state.counts) {
      totalArea[teamId] = (totalArea[teamId] || 0) + count;
      if (count > posterMax) {
        posterMax = count;
        posterOwner = teamId;
      }
    }

    if (posterOwner) {
      posterWins[posterOwner] = (posterWins[posterOwner] || 0) + 1;
    }
  }

  const allTeams = new Set([
    ...Object.keys(totalArea),
    ...Object.keys(posterWins),
  ]);

  const leaderboard = Array.from(allTeams).map((teamId) => ({
    teamId,
    totalArea: totalArea[teamId] || 0,
    postersOwned: posterWins[teamId] || 0,
  }));

  leaderboard.sort((a, b) => b.postersOwned - a.postersOwned || b.totalArea - a.totalArea);

  return leaderboard;
}

function resetTerritory(posterId) {
  posterTerritory.delete(posterId);
}

module.exports = {
  territoryEngine: {
    recordStroke,
    syncPosterTerritory,
    getTerritoryState,
    getGlobalLeaderboard,
    resetTerritory,
  },
};
