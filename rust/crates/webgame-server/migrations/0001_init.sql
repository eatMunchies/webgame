-- Users, lobbies, and a log of every game. Live game state is kept in memory by each lobby's
-- task and isn't read back from here; this is a record, not a save file.
-- Times are unix milliseconds.

CREATE TABLE IF NOT EXISTS users (
    -- UserId: a hash of the lowercased username (no accounts yet).
    id INTEGER PRIMARY KEY,
    username TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    last_seen INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS lobbies (
    code TEXT NOT NULL,
    host_id INTEGER NOT NULL REFERENCES users (id),
    opened_at INTEGER NOT NULL,
    closed_at INTEGER,
    -- A code is reused once its lobby closes.
    PRIMARY KEY (code, opened_at)
);

CREATE TABLE IF NOT EXISTS games (
    id INTEGER PRIMARY KEY,
    lobby_code TEXT NOT NULL,
    -- The seed that dealt the roles and made every random choice.
    seed INTEGER NOT NULL,
    -- JSON: [{"slot", "user_id", "name"}]
    players TEXT NOT NULL,
    started_at INTEGER NOT NULL,
    ended_at INTEGER,
    -- JSON GameOverInfo, once the game ends.
    result TEXT
);

-- Every message the game sent, in order, with who could see it. Replaying these rebuilds
-- what each player saw.
CREATE TABLE IF NOT EXISTS game_events (
    game_id INTEGER NOT NULL REFERENCES games (id),
    seq INTEGER NOT NULL,
    at INTEGER NOT NULL,
    -- JSON Audience: "All", {"One": slot}, or {"Many": [slots]}
    audience TEXT NOT NULL,
    -- JSON ServerMessage
    message TEXT NOT NULL,
    PRIMARY KEY (game_id, seq)
);
