# webgame

A top-down RPG for the browser.

## Layout

| Path | Purpose |
|------|---------|
| `front/` | Game client (Godot 4.7 project, exported to the web) |
| `rust/` | Rust workspace: the shared protocol, the game engine, the game server, the client logic both clients share, a terminal test client, and the GDExtension the Godot client loads |
| `api/auth/` | Authentication service |
| `api/db/` | Database |
| `assets/` | Art assets (see below) |

## Game client (`front/`)

Requires [Godot 4.7](https://godotengine.org/download) (the standard build, not .NET), [Rust](https://rustup.rs), and [just](https://github.com/casey/just). The project uses the Compatibility renderer because the web export requires it, and renders at 320x180, scaled up by whole numbers with no texture filtering so pixel art stays sharp.

### Building the Rust extension

The client loads a GDExtension built from `rust/crates/webgame-godot-rust`. Godot doesn't compile it, so build it before opening the project for the first time and again after changing Rust code:

```sh
just build
```

The editor picks up the rebuilt library on its own. Run `just` with no arguments to list every recipe.

Machine-specific settings go in a `.env` file at the repo root, which is gitignored. Copy `.env.example` to `.env` and fill in what applies to you: `GODOT` if Godot isn't on your PATH, and `EMSDK` for web builds (see below).

### Running

To work in the editor, open Godot's Project Manager, choose Import, and select `front/project.godot`. Press F5 to run.

The game starts in the lobby screen, where you enter a name, can open the character customizer, and create a lobby or type a code to join one. Lobbies live on the game server, so start it first (`just play`, see [Game server](#game-server-and-test-client-rust)). The customizer (`scripts/wardrobe.gd`, which `customizer.gd` extends with Save and Cancel) shows your character on a pedestal that the arrows turn around, and groups the choices into Body, Face, Outfit, Gear, Pet and House tabs, where each item is a picture tile of that item on your current body. On the House tab you pick your house's roof, facade and yard, and the preview switches to the house with your character in the yard. The house is saved with your profile and sent along with your look. Creating or joining takes you to the town, where you walk with WASD or the arrow keys. On a touch screen, put a thumb anywhere on the lower-left half of the screen and drag to walk. To try that on a desktop, turn on Project Settings > Input Devices > Pointing > Emulate Touch From Mouse.

The town is a cul-de-sac with 15 lots around it, one per player, since a lobby holds 15. Inside the road loop is a small park with a paved plaza and the podium in the middle. The ground is painted in code by `front/scripts/cul_de_sac.gd`, and every size (the map, the road, the park, the ring of houses) is a constant at the top of that file, sized to the 32px characters. The town scene places the houses, podium, spawn point and map edges from those constants, so changing one keeps everything lined up. Characters in the town are drawn at 1.5x (the `scale` on the Character node in `scenes/main/player.tscn` and `remote_player.tscn`) so people read clearly next to the houses; the lobby and customizer previews stay at their own size. Lots fill in join order, clockwise from the road in, and each player's house is the one they picked in the customizer. Any layer they never picked (yard, facade or roof) gets a random style, seeded from the lobby code and the player's id so every client draws the same house. Empty lots show a For Sale sign.

In the town, each house is labeled with its owner's number and name; a player's number is how commands name them. The panel on the right is the game: the phase and time left, your role, and a log of chat, votes, night results and deaths. Press Enter to type and Enter again to send (Escape goes back to walking). Plain text is chat on whatever channel you can use now, and the commands are the same as the terminal client's (`/vote 3`, `/target 2`, `/will ...`; `/help` lists them). Below the log are buttons for whatever you can do right now: Vote next to each player while voting, Guilty / Innocent / Abstain during a trial, and at night your role's ability (Heal, Investigate, Kill ...) next to each player you can target, or a single button like Alert or Ignite. Your current choice shows pressed, and Cancel or Unvote takes it back. A button sends the same command as typing it, so the log shows the result either way. The Will button opens an editor for your last will. The host gets a Start game button once 4 players are in. Dead players' houses go grey, and the town darkens at night.

After the night's actions lock in, a panel over the town shows your minigame for each stage (see [How a game runs](#how-a-game-runs)), and you don't walk while it's up. A skill check is a dial: press Space or tap when the needle is in the gold zone, once. A fight shows you and your masked opponent: J (or Z) strikes, K (or X) grabs, and holding L, C or Space guards, or use the buttons. A strike hits an open fighter but bounces off a guard and leaves you dazed; a grab breaks a guard but is slow enough to be struck out of, and misses an open fighter. Each fighter takes 3 hits. Everyone else, and anyone whose minigame is decided, gets the dial as practice, with a streak.

The client connects to `ws://127.0.0.1:9090/ws`. To use another server, pass it after `--`: `godot --path front -- --server=ws://192.168.1.20:9090/ws`. In a browser it connects to port 9090 on the host that served the page (`wss://` when the page is on `https://`, which the server doesn't support yet). To play several Godot clients on one machine, run the game more than once with different names, or mix Godot and terminal clients in one lobby.

Everyone in the lobby walks around the same town. Each client sends its player's position about 15 times a second while it changes, and the server passes it on to the others, who glide each character toward its latest position. A player's look from the customizer is sent on joining, so others see them as they dressed. Dead players show faded. Movement is only relayed, never stored, and other players don't block you.

| Path | What it is |
|------|------------|
| `scenes/main/` | The game's scenes: `lobby`, `customizer`, `town`, plus what the town places: `player` (you), `remote_player` (everyone else), `house`, and `game_panel` |
| `scenes/test/` | Standalone test scenes: `main` (walk around a field) and `wardrobe` (character preview with no save) |
| `scripts/ui/` | `RpgTheme`, the dark-wood-and-gold theme the character customizer uses, built in code. Other screens can use it with `theme = RpgTheme.build()` |
| `scripts/house/` | House drawing: `HouseCatalog` finds house art on disk, `HouseAppearance` holds one house's styles |
| `scripts/autoload/` | Globals available in every scene: `PlayerProfile` (the saved character and name, kept in Godot's `user://` folder) and `Session` (the connection to the server and the current lobby, through the Rust `GameClient`) |

To run one scene by itself, open it and press F6.

From a terminal, the commands below use `godot` to mean the Godot executable. Either add it to your PATH or replace `godot` with its full path.

- Open in the editor: `godot -e --path front`
- Run the game: `godot --path front`
- Run the walking test scene: `godot --path front res://scenes/test/main.tscn`

`front/assets` is a symlink to the top-level `assets/` folder, so sprites appear in Godot as `res://assets/...`. On Windows, Git checks symlinks out as plain text files unless symlink support is on. Enable Developer Mode, then clone with `git clone -c core.symlinks=true ...`. Godot writes a `.import` file next to each image; commit those.

### Web export

The web build compiles the Rust extension to WebAssembly, which needs extra tools.

1. One-time setup:
   - Add the nightly Rust toolchain and the pieces the web build uses:
     ```sh
     rustup toolchain install nightly
     rustup component add rust-src --toolchain nightly
     rustup target add wasm32-unknown-emscripten --toolchain nightly
     ```
   - Install Emscripten 3.1.74 with [emsdk](https://github.com/emscripten-core/emsdk) (`./emsdk install 3.1.74`, then `./emsdk activate 3.1.74`), and set `EMSDK` in `.env` to the emsdk directory. The installer needs Python 3.10 or newer; if the system `python3` is older (macOS ships 3.9), point `EMSDK_PYTHON` at a newer one for the install, like `EMSDK_PYTHON=/opt/homebrew/bin/python3.13 ./emsdk install 3.1.74`. emsdk brings its own Python after that.
   - In the Godot editor, Editor > Manage Export Templates > Download and Install.
2. Run `just export-web`. It builds the extension in release mode, then exports the game to `front/build/web/index.html` (gitignored).

   Exporting from the editor (Project > Export) or testing with Remote Debug > Run in Browser also works, but neither rebuilds the extension; they copy whatever `.wasm` is already built. Run `just build-web release` before an editor export, or `just build-web` before Run in Browser, which uses the debug build.
3. Browsers won't run the export from a `file://` URL, so serve `front/build/web` with any static file server and open it over `http://`. The preset turns thread support off, so the server doesn't need special COOP/COEP headers. Any static host (itch.io, GitHub Pages, Netlify) works the same way. The Rust extension is built single-threaded to match; turning thread support on in the preset would also need a threaded build of the extension.

## Game server and test client (`rust/`)

The game itself (lobbies, roles, days and nights, chat, voting, last wills) runs on a Rust server. You play it from the Godot client, from a small terminal client, or both in the same lobby. They speak the same protocol and share the same client code.

| Crate | What it is |
|-------|-----------|
| `webgame-protocol` | Every type that crosses the network, defined once: ids, roles, phases, chat channels and their rules, and the `ClientMessage` / `ServerMessage` enums. Messages are encoded with [postcard](https://docs.rs/postcard) and sent as WebSocket binary frames. It has no OS dependencies, so the Godot extension can use it, including in the web build. |
| `webgame-game` | The rules engine: setting up a game, the day and night cycle, the night calculator, and win conditions. It does no networking and reads no clock (time is passed in), so whole games run in tests in milliseconds. |
| `webgame-server` | The server: a WebSocket endpoint at `/ws` (and `/health`), one task per lobby that owns its game, and a SQLite file that records users, lobbies, games and every message each game sent. |
| `webgame-client` | What a client knows about the game, kept up to date from server messages, how each message reads as text, and how a typed line like `/vote 3` becomes a message. Both clients use it, so they agree on the rules and describe the game the same way. |
| `webgame-cli` | The terminal client. |
| `webgame-godot-rust` | The GDExtension Godot loads: the `StateMachine`, and `GameClient`, the node that talks to the server over Godot's WebSocketPeer (which also works in the web export) and gives GDScript methods and signals. |

### Playing a test game

Start the server, then open one terminal per player (a game needs at least 4, at most 15):

```sh
just play                            # the server, with short phases
just cli --name Ada --create         # prints a lobby code, like ABC234
just cli --name Bram --join ABC234   # and the same for Cleo, Dev, ...
```

Players can also join from the Godot game (`just run`) by typing the lobby code, and Godot and terminal players can share a lobby. The player who created the lobby types `/start` (or presses Start game in Godot). `/help` lists every command. Players are named by their number from `/players`, so `/vote 3` votes for player 3. Plain text goes to whatever chat you can use right now: the lobby, the town square by day, or by night the jail, the Mafia, or the dead.

| Command | What it does |
|---------|-------------|
| `/create`, `/join CODE`, `/leave`, `/start` | Lobbies. Only the host can start. |
| `/w N text` | Whisper to player N during the day. Everyone sees that you whispered, only N sees what. |
| `/vote N`, `/unvote` | Vote player N up for trial. |
| `/guilty`, `/inno`, `/abstain` | Judge the player on trial. |
| `/jail N` | (Jailer) pick tonight's prisoner, during the day. |
| `/target N` | Use your night ability on player N. A lynched Jester haunts with it too. |
| `/target N M` | (Copycat) use player N's night ability on player M. Or pick in two steps, like the buttons do: `/copy N`, then `/target M`. |
| `/alert`, `/vest`, `/ignite`, `/execute` | Night abilities with no target: Veteran, Survivor, Arsonist, Jailer. |
| `/cancel` | Take back tonight's action, while actions are still being chosen. |
| `/roll` | Have the server decide your minigame at random. The terminal client does this by itself, since it can't show minigames; only `--fast` servers allow it. |
| `/will text` | Set your last will, shown to everyone when you die. Write `\n` for a new line. `/will` alone shows it. |
| `/role`, `/roles`, `/players` | Your role and team, the game's role list, and who is alive. |

The server takes `--fast` (short phases, and minigames may be rolled, which the terminal client does), `--seed N` (the same roles every game, given the same players), `--port` (default 9090), `--host` (default 127.0.0.1) and `--db` (default `webgame.db` in the directory it runs from, which is `rust/` under `just`; gitignored). `just server` runs it with normal phase lengths. To look at what a game recorded: `sqlite3 rust/webgame.db 'select * from games'`.

There is no authentication yet. A username is the whole identity: the same name always gets the same user id, which is how a player who drops reconnects to their seat (join the same code with the same name). The server only listens on localhost by default, and doesn't check the `Origin` of WebSocket connections, so don't expose it to the internet as it is.

### How a game runs

- **Cycle.** Day 0 is a short introduction, then Night 1, Day 1, Night 2, and so on.
- **Days.** Discussion, then voting. A player voted up by a majority of the living goes on trial: they make a defense (only they can talk), then everyone judges them guilty, innocent or abstains. More guilty than innocent votes means last words, a lynch, and the day ends. Otherwise voting resumes. After 3 trials, or when voting time runs out, night falls.
- **Nights.** Players pick their actions at nightfall (15 seconds), and then they lock. The rest of the night runs in stages that always take the same time: roleblocks, three rounds of fights, protection, investigations. In each stage every living player plays one minigame. Whoever acts in that stage plays a skill check, and failing it means the action does nothing, though they still visit their target (a Lookout sees them, a Veteran on alert shoots them). An attack by the Mafia, a Serial Killer, a Vigilante or a lynched Jester is a fight between attacker and victim, who don't learn who the other is; the attack only goes ahead if the attacker knocks the victim out before the round ends, and even then heals, guards and defense still apply. Jailer executions and Arsonist ignitions are skill checks. Everyone else plays a game with nothing riding on it. Once the stages are done the server works out what happened all at once: jailing, then roleblocks, then protection, then attacks, then investigations. Each player gets their own results, and the morning announces who died, with their role and last will.
- **Chat.** Lobby chat; the town square by day; whispers by day; jail chat (the Jailer and their prisoner, who doesn't learn who the Jailer is), Mafia chat and dead chat by night. A living Medium hears and speaks to the dead at night. Dead players can always read the town square and dead chat.
- **Winning.** Town wins when every Mafia member and neutral killer is dead. The Mafia wins when it is at least as big as everyone else and no neutral killer is left. A Serial Killer or Arsonist wins as the last one standing. A Jester wins by being lynched, an Executioner by getting their target lynched, and a Survivor by being alive at the end; they win alongside whoever else wins. Three day/night cycles in a row with no deaths end in a draw.
- **Role list.** Roles come from a list that grows with the player count (Town of Salem's ranked list, trimmed): with 4 players it is Mafioso, Town Investigative, Town Protective, Neutral Evil; with 15 it adds Town Support, another Town Investigative, Godfather, Jailer, Town Killing, a random Mafia role, a Neutral Killing role, three random Town roles and one of anything. When the Godfather dies the Mafioso takes over, and when there's no Mafioso another Mafia member becomes one.

### Roles

| Role | Faction | Category | Night ability |
|------|---------|----------|---------------|
| Jailer | Town | Power | By day, pick someone to jail. That night they can't act, talk only to you, and you may execute them (3 times, not night 1). |
| Sheriff | Town | Investigative | Learn whether someone is suspicious (Mafia other than the Godfather, or a Serial Killer). |
| Investigator | Town | Investigative | Learn a short list of roles someone could be. |
| Lookout | Town | Investigative | See who visits a house. |
| Tracker | Town | Investigative | See who someone visits. |
| Spy | Town | Investigative | Bug a house to hear what happens to its owner, and learn who the Mafia visited. |
| Barkeep | Town | Support | Roleblock someone. Can't be roleblocked. |
| Medium | Town | Support | Talk with the dead at night, anonymously. |
| Vigilante | Town | Killing | Shoot someone (3 bullets, not night 1). Shooting Town means dying of guilt the next night. |
| Veteran | Town | Killing | Go on alert (3 times), shooting everyone who visits. |
| Trapper | Town | Protective | Trap a house; the first attacker of its owner is attacked instead. |
| Doctor | Town | Protective | Heal someone, saving them from an attack (yourself once). |
| Bodyguard | Town | Protective | Guard someone; you kill their attacker and die. Vest yourself once. |
| Godfather | Mafia | Killing | Pick the Mafia's kill. Looks innocent to the Sheriff, and survives basic attacks. |
| Mafioso | Mafia | Killing | Carry out the Godfather's kill, or your own pick. |
| Ambusher | Mafia | Killing | Wait at a house and attack one visitor. Every visitor sees you. |
| Poisoner | Mafia | Killing | Poison someone; they die the next night unless a Doctor heals them. |
| Consigliere | Mafia | Support | Learn someone's exact role. |
| Escort | Mafia | Support | Roleblock someone. Can't be roleblocked. |
| Disguiser | Mafia | Deception | Swap appearances with someone, so investigators see each as the other. |
| Copycat | Mafia | Deception | Pick two players: use the first one's night ability on the second, and learn the first one's role. |
| Executioner | Neutral | Evil | Win by getting your target lynched. If they die another way, you become a Jester. |
| Jester | Neutral | Evil | Win by getting lynched, then haunt one guilty voter the next night. |
| Amnesiac | Neutral | Benign | Once, take the role of a dead player. Everyone is told which role was remembered. |
| Survivor | Neutral | Benign | Put on a vest (4 times). Win by being alive at the end. |
| Serial Killer | Neutral | Killing | Kill someone. Kills anyone who roleblocks you instead. |
| Arsonist | Neutral | Killing | Douse someone, or ignite everyone doused. Looks innocent to the Sheriff. |

Jailer, Veteran, Godfather and Mafioso are unique: at most one per game.

## Tests

`just test` runs everything. `just test unit` runs only the Rust unit tests (`cargo test`, so extra arguments go to cargo), and `just test godot` runs only the Godot integration tests. The Rust tests include every night interaction (`rust/crates/webgame-game/tests/night.rs`), scripted games, and a server test where four WebSocket clients play a whole game (`rust/crates/webgame-server/tests/server.rs`).

Integration tests live in `front/tests/` and use [GdUnit4](https://github.com/godot-gdunit-labs/gdUnit4), which is vendored in `front/addons/gdUnit4`. They run in headless Godot with `--fixed-fps 60`, so every frame advances by exactly 1/60 s no matter how long it takes. To run one suite, pass GdUnit4's options: `just test godot -a res://tests/state_machine_test.gd`. You can also run them from the GdUnit4 panel in the editor. Reports are written to `front/reports/` (gitignored).

`front/project.godot` sets `gdunit4/report/godot/push_error=true`. Rust panics are reported as engine errors, and without this setting GdUnit4 doesn't count them as failures, so keep it on.

## Art assets

See [`assets/README.md`](assets/README.md) for the sprite format, how characters are layered, the costume sets, and the Pixelorama workflow.
