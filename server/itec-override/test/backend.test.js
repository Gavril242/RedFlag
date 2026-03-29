const test = require("node:test");
const assert = require("node:assert/strict");

const { posterManager } = require("../src/posterManager");
const { territoryEngine } = require("../src/territoryEngine");
const { teamSessionManager } = require("../src/teamSessionManager");
const { saveState, loadState } = require("../src/persistenceStore");

test("posterManager normalizes stroke points and sticker bounds", () => {
  const posterId = `poster-normalize-${Date.now()}`;

  const stroke = posterManager.addStroke(posterId, {
    width: 500,
    points: [
      { x: -1, y: 0.5 },
      { x: 1.4, y: 2 },
      { x: Number.NaN, y: 0.1 },
    ],
  });

  const sticker = posterManager.addSticker(posterId, {
    url: "https://example.com/sticker.gif",
    x: -3,
    y: 3,
    width: 0,
    height: 2,
    rotation: Number.POSITIVE_INFINITY,
  });

  assert.equal(stroke.width, 64);
  assert.deepEqual(stroke.points, [
    { x: 0, y: 0.5 },
    { x: 1, y: 1 },
  ]);

  assert.equal(sticker.x, 0);
  assert.equal(sticker.y, 1);
  assert.equal(sticker.width, 0.01);
  assert.equal(sticker.height, 1);
  assert.equal(sticker.rotation, 0);
});

test("posterManager converts bottom-left and viewport pixel coordinates into canonical poster space", () => {
  const posterId = `poster-transform-${Date.now()}`;

  const stroke = posterManager.addStroke(posterId, {
    width: 12,
    coordinateMeta: {
      coordinateSpace: "pixels",
      origin: "bottom-left",
      sourceWidth: 1080,
      sourceHeight: 1920,
      viewportX: 140,
      viewportY: 260,
      viewportWidth: 800,
      viewportHeight: 1200,
    },
    points: [
      { x: 140, y: 260 },
      { x: 940, y: 1460 },
    ],
  });

  const sticker = posterManager.addSticker(posterId, {
    x: 540,
    y: 860,
    coordinateMeta: {
      coordinateSpace: "pixels",
      origin: "bottom-left",
      sourceWidth: 1080,
      sourceHeight: 1920,
      viewportX: 140,
      viewportY: 260,
      viewportWidth: 800,
      viewportHeight: 1200,
    },
  });

  assert.deepEqual(stroke.points, [
    { x: 0, y: 1 },
    { x: 1, y: 0 },
  ]);
  assert.deepEqual(
    { x: Number(sticker.x.toFixed(2)), y: Number(sticker.y.toFixed(2)) },
    { x: 0.5, y: 0.5 }
  );
});

test("posterManager persists poster audio and clears it with the poster", () => {
  const posterId = `poster-audio-${Date.now()}`;
  const audio = posterManager.setPosterAudio(posterId, {
    teamId: "red",
    userId: "tester",
    title: "Anthem",
    url: "https://example.com/anthem.mp3",
  });

  assert.equal(audio?.teamId, "red");
  assert.equal(posterManager.getPoster(posterId)?.audio?.url, "https://example.com/anthem.mp3");

  posterManager.clearPoster(posterId);
  assert.equal(posterManager.getPoster(posterId)?.audio, null);
});

test("posterManager hydrate keeps poster audio", () => {
  const posterId = `poster-audio-hydrate-${Date.now()}`;
  const snapshot = [
    {
      id: posterId,
      createdAt: Date.now(),
      layout: { width: 1000, height: 1414, origin: "top-left" },
      audio: {
        teamId: "team-a",
        userId: "user-a",
        title: "Anthem",
        url: "https://example.com/anthem.mp3",
        ts: Date.now(),
      },
      strokes: [],
      stickers: [],
    },
  ];

  posterManager.hydrate(snapshot);

  assert.equal(posterManager.getPoster(posterId)?.audio?.teamId, "team-a");
  assert.equal(posterManager.getPoster(posterId)?.audio?.url, "https://example.com/anthem.mp3");
});

test("posterManager persists poster location", () => {
  const posterId = `poster-location-${Date.now()}`;
  const location = posterManager.setPosterLocation(posterId, {
    lat: 44.4268,
    lng: 26.1025,
    label: "University Entrance",
  });

  assert.equal(location?.label, "University Entrance");
  assert.equal(posterManager.getPoster(posterId)?.location?.lat, 44.4268);
});

test("territory sync reflects the currently retained strokes", () => {
  const posterId = `poster-territory-${Date.now()}`;

  const redStroke = posterManager.addStroke(posterId, {
    teamId: "red",
    width: 10,
    points: [
      { x: 0.1, y: 0.1 },
      { x: 0.9, y: 0.1 },
    ],
  });

  const blueStroke = posterManager.addStroke(posterId, {
    teamId: "blue",
    width: 20,
    points: [
      { x: 0.1, y: 0.1 },
      { x: 0.1, y: 0.9 },
    ],
  });

  territoryEngine.syncPosterTerritory(posterId, [redStroke, blueStroke], []);

  let territory = territoryEngine.getTerritoryState(posterId);
  assert.equal(territory.owner, "blue");
  assert.ok(territory.rawArea.blue > territory.rawArea.red);
  assert.ok(territory.rawArea.red > 0);

  territoryEngine.syncPosterTerritory(posterId, [redStroke], []);

  territory = territoryEngine.getTerritoryState(posterId);
  assert.equal(territory.owner, "red");
  assert.deepEqual(Object.keys(territory.rawArea), ["red"]);
});

test("territory includes stickers as percentage of full poster area", () => {
  const posterId = `poster-stickers-${Date.now()}`;
  const redStroke = posterManager.addStroke(posterId, {
    teamId: "red",
    width: 10,
    points: [
      { x: 0.1, y: 0.1 },
      { x: 0.9, y: 0.1 },
    ],
  });
  const blueSticker = posterManager.addSticker(posterId, {
    teamId: "blue",
    url: "https://example.com/x.gif",
    x: 0.5,
    y: 0.5,
    width: 0.2,
    height: 0.25,
  });

  territoryEngine.syncPosterTerritory(posterId, [redStroke], [blueSticker]);

  const territory = territoryEngine.getTerritoryState(posterId);
  assert.equal(territory.owner, "blue");
  assert.ok(territory.rawArea.red > 0);
  assert.ok(territory.rawArea.blue > territory.rawArea.red);
});

test("later stickers overwrite earlier visible territory instead of adding on top", () => {
  const posterId = `poster-overlap-${Date.now()}`;
  const redStroke = posterManager.addStroke(posterId, {
    teamId: "red",
    width: 120,
    points: [
      { x: 0.1, y: 0.5 },
      { x: 0.9, y: 0.5 },
    ],
  });
  const blueSticker = posterManager.addSticker(posterId, {
    teamId: "blue",
    url: "https://example.com/blue.gif",
    x: 0.5,
    y: 0.5,
    width: 0.5,
    height: 0.3,
  });

  territoryEngine.syncPosterTerritory(posterId, [redStroke], []);
  const before = territoryEngine.getTerritoryState(posterId);

  territoryEngine.syncPosterTerritory(posterId, [redStroke], [blueSticker]);
  const after = territoryEngine.getTerritoryState(posterId);

  assert.ok(after.rawArea.blue > 0);
  assert.ok(after.rawArea.red < before.rawArea.red);
  assert.ok(after.rawArea.red + after.rawArea.blue < 100);
});

test("leaderboard counts poster wins across synced posters", () => {
  const firstPosterId = `poster-a-${Date.now()}`;
  const secondPosterId = `poster-b-${Date.now()}`;

  const alphaStroke = posterManager.addStroke(firstPosterId, {
    teamId: "alpha",
    width: 12,
    points: [
      { x: 0.1, y: 0.2 },
      { x: 0.9, y: 0.2 },
    ],
  });

  const betaStroke = posterManager.addStroke(secondPosterId, {
    teamId: "beta",
    width: 12,
    points: [
      { x: 0.1, y: 0.2 },
      { x: 0.9, y: 0.2 },
    ],
  });

  territoryEngine.syncPosterTerritory(firstPosterId, [alphaStroke], []);
  territoryEngine.syncPosterTerritory(secondPosterId, [betaStroke], []);

  const leaderboard = territoryEngine.getGlobalLeaderboard();
  const alpha = leaderboard.find((entry) => entry.teamId === "alpha");
  const beta = leaderboard.find((entry) => entry.teamId === "beta");

  assert.equal(alpha?.postersOwned, 1);
  assert.equal(beta?.postersOwned, 1);
});

test("team sessions require password auth and support custom team creation", () => {
  const username = `player-${Date.now()}`;
  const register = teamSessionManager.register(username, "test1234");
  assert.equal(register.ok, true);
  assert.ok(register.session.token);
  assert.equal(register.player.teamId, null);

  const createTeam = teamSessionManager.createTeam(register.user.id, {
    name: `Team ${Date.now()}`,
    anthemTitle: "March",
    anthemUrl: "https://example.com/march.mp3",
  });
  assert.equal(createTeam.ok, true);
  assert.equal(createTeam.team.ownerUserId, register.user.id);
  assert.equal(createTeam.user.teamId, createTeam.team.id);

  const sessionBundle = teamSessionManager.getSessionBundle(register.session.token);
  assert.equal(sessionBundle?.player.id, register.player.id);
  assert.equal(sessionBundle?.team?.id, createTeam.team.id);

  const login = teamSessionManager.login(username, "test1234");
  assert.equal(login.ok, true);
  assert.equal(login.user.id, register.user.id);
});

test("persistence store preserves users for auth reloads", () => {
  const state = {
    posters: [],
    teams: [],
    users: [
      {
        id: "user_test",
        username: "rafael",
        passwordHash: "abc123",
        teamId: null,
        createdAt: Date.now(),
      },
    ],
    sessions: [],
  };

  saveState(state);
  const loaded = loadState();

  assert.equal(Array.isArray(loaded.users), true);
  assert.equal(loaded.users[0]?.username, "rafael");
});
