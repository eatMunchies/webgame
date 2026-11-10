# Table of Salem

A Town of Salem style social deduction game, played around one table with a phone or laptop each, in a top-down RPG town that runs in the browser. The repo and the code still call it `webgame`. The window and app are named Table of Salem, but saves stay in the `webgame` folder (`application/config/custom_user_dir_name` in `front/project.godot`), so renaming the game kept existing profiles.

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

The window opens at 1920x1080. The game starts on the Table of Salem screen, styled like the customizer: on the left, your house with your character in its yard (any house layer you haven't picked shows as a random style), a Customize button in the preview's corner and your name under it; on the right, Create lobby, a lobby code box with Join, and Minigames, which opens the minigame tester (`scenes/main/minigame_tester.tscn`). The tester lists every minigame in `skill_checks/` and plays the one you pick in the same panel, at the same size, as at night, with no server. Played for real it rolls with the chance the game reports, the way the server would, and a log on the right shows what it reported and how it rolled; tick Practice to play with nothing riding on it. Night, at the top of the list, plays a whole night the way a player lives it: Choose your action, then Roleblocks, Fights 1/3 to 3/3, Protection and Investigations at the server's fast timings (8 seconds a stage, 24 a fight round), with the real overlay picking games from its real pools. Each night you either attack in the first fight round, or do an action (its skill check falls in one action stage) and get attacked in a random round; every other stage is the practice game, which carries on between stages. The fights use the server's own fight rules: `PracticeFight` (`rust/crates/webgame-godot-rust/src/practice_fight.rs`) wraps the `Duel` from `webgame-game`, so strikes, grabs, guards and staggers time out exactly as online, against a bot (`scripts/minigame/practice_night.gd`) that reacts after a third to two thirds of a second, and now and then misses a move entirely, so it can be beaten. The morning's summary shows in the panel when the night ends. Fight, under Night, is practice for just that: three fights against the bot back to back, each going on until a knockout, attacking then defending then attacking, each named in the header, ending with how many you won. As on the town's clock, which past choosing shows only "Night N" with no stage name or timer, the header never says which stage is playing, so the night's cycle stays hidden and the panel is all you see. A skill check that counts, or a fight, opens with a 3 second countdown in the middle of the panel ("Skill Check" with the game's name, or "Fight starting"), with the game frozen and hidden until it ends, so it's clear when something rides on it; practice has no countdown. The server adds the countdown (`MINIGAME_INTRO_MS` in the protocol, `minigame_intro` in its timers) on top of every minigame stage, so it never takes from the time to play. The controls for the picked game show on the right, Again starts it (or the night) over, and Back or Escape returns to the start screen. Menus are laid out for 1280x720 and scale smoothly to the window, and the town's 320x180 pixel art scales by whole steps (6x at 1080p); `scripts/ui/screen_scale.gd` sets both. Lobbies live on the game server, so start it first (`just play`, see [Game server](#game-server-and-test-client-rust)). The customizer (`scripts/wardrobe.gd`, which `customizer.gd` extends with Save and Cancel) shows your character on a pedestal that the arrows turn around, and groups the choices into Body, Face, Outfit, Gear, Pet and House tabs, where each item is a picture tile of that item on your current body. On the House tab you pick your house's roof, facade and yard, and the preview switches to the house with your character in the yard. The house is saved with your profile and sent along with your look. Creating or joining takes you to the town, where you walk with WASD or the arrow keys. On a touch screen, put a thumb anywhere on the lower-left half of the screen and drag to walk. To try that on a desktop, turn on Project Settings > Input Devices > Pointing > Emulate Touch From Mouse.

The town is a cul-de-sac with 15 lots around it, one per player, since a lobby holds 15. Inside the road loop is a small park with a paved plaza and the podium in the middle. The ground is painted in code by `front/scripts/cul_de_sac.gd`, and every size (the map, the road, the park, the ring of houses) is a constant at the top of that file, sized to the 32px characters. The town scene places the houses, podium, spawn point and map edges from those constants, so changing one keeps everything lined up. Characters in the town are drawn at 1.5x (the `scale` on the Character node in `scenes/main/player.tscn` and `remote_player.tscn`) so people read clearly next to the houses; the lobby and customizer previews stay at their own size. Lots fill in join order, clockwise from the road in, and each player's house is the one they picked in the customizer. Any layer they never picked (yard, facade or roof) gets a random style, seeded from the lobby code and the player's id so every client draws the same house. Empty lots show a For Sale sign.

In the town, each house is labeled with its owner's number and name; a player's number is how commands name them. The HUD keeps to the edges so the town stays visible:

- **Top left: the players.** Each player's number and name, you in blue. The dead are greyed and struck through, with the role their death revealed (everyone's role shows once the game is over). While voting, each player's vote count sits beside them and the heading says how many votes put someone on trial. Your role is at the bottom.
- **Top middle: the clock.** "Day 2" or "Night 1", the stage under it (Discussion, Voting (2 trials left), Defense: Bram, Judgement: Bram, Last words: Bram, and the night's stages), and the time left, which turns red for the last few seconds.
- **Right: the chat.** The game is played in one room, so the town talks out loud and the chat is mostly for whispers and night chat. It opens and closes on the clock, the same for everyone, so nobody's screen gives away that they have a night chat: it's open at night, through the morning's discussion (where night results land) and once the game is over, and collapsed to a small tab from voting until nightfall and in the lobby. The tab counts unread whispers and private notices; Open (or Enter) opens it any time. The lobby code with Copy and Leave sits above it. Open, it's a log of chat, votes, night results and deaths, and a box to type in. Beside the box is the channel plain text goes to right now: town, jail, mafia, dead, whisper (while typing `/w N ...`), or muted when nobody can hear you. Press Enter to type and Enter again to send (Escape goes back to walking). The commands are the same as the terminal client's (`/vote 3`, `/target 2`, `/will ...`; `/help` lists them). The will editor opens in the chat's place from the Last will button at the bottom (see below).
- **Bottom middle: what you can do now.** Buttons for each player under a heading for the action: Vote while voting, Jail for the Jailer, and at night your role's ability (Heal, Investigate, Kill ...). Buttons that stand alone go in a row under them: Guilty / Innocent / Abstain during a trial, Alert, Ignite, Unvote, Cancel. Your current choice shows filled gold, and Cancel or Unvote takes it back. A button sends the same command as typing it, so the log shows the result either way. Before a game the host's Start game button is here, enabled once 4 players are in. During a game, while you're alive, the Last will button is here too; it opens the will editor in the chat panel (opening the chat if it was collapsed, and collapsing it again when you close the editor).

Dead players' houses go grey, and the town darkens at night.

After the night's actions lock in, a panel in the middle of the screen, between the players and the chat, shows your minigame for each stage (see [How a game runs](#how-a-game-runs)), and you don't walk while it's up. A skill check, the minigame your night action's chance rides on, is one of the kinds in `skill_checks/`, picked at random by weight:

- **Timing Wheel:** press Space or tap when the needle is in the gold zone, five times. The pips under it show your hits.
- **Typing Test:** type the words shown, Space after each.
- **Flappy Bird:** Space, Up or a tap flaps. Each of 5 pipes flown through is a fifth of the chance, and crashing ends it.
- **Flappy Golf:** flap a golf ball over the course into the cup. Every hole is new: a random mix of hills, dips, flat-topped mesas and bumps, sometimes played right to left, and on about half the holes a floating block or two that the ball bounces off and can roll along the top of. The ball bounces off the slope it lands on and loses the speed it hit with, so it can't ride up a hill; on the ground, gravity speeds it down slopes and slows it up them until friction stops it. Left/A and Right/D (or a tap on that side) flap that way, Up/Space flaps straight up. Holing out in par (3) or fewer is a sure pass, and each flap over par takes 20% off (never below 20%).
- **Fruit Ninja:** swipe across the fruit with the mouse or a finger. Each of 8 fruit sliced is an equal share of the chance, and slicing one of the 2 bombs ends it on the spot.
- **Blackjack:** one hand against the dealer from a 2-deck shoe. H, Left or Space hits; S, Right or Enter stands; or tap the buttons. While you decide, it shows the odds that hitting busts you, counted from every card you haven't seen. A win is a sure pass, a push is 50% and a loss fails (tunable in `blackjack.tres`).

The four arcade games (Flappy Bird, Flappy Golf, Fruit Ninja, Blackjack) share `ArcadeCheck`, which fits their 140x100 play field to the panel; each keeps its rules in a model class (`FlappyGame`, `GolfGame`, `FruitGame`, `BlackjackGame`) tested in `tests/arcade_games_test.gd`. Every minigame plays by touch as well as keys: a tap is a click (flap, flip a card, hit or stand on Blackjack's wide buttons, tap a side of the golf course to flap that way), Fruit Ninja slices with a finger swipe, and the typing test brings up the on-screen keyboard on phones. Godot also turns each touch into a made-up mouse click, so `SkillCheck.is_tap()` and Fruit Ninja skip events from `InputEvent.DEVICE_ID_EMULATION` and one tap counts once. Each kind is a `SkillCheckDef` resource (a `.tres` file) that names the scene that plays it (in `scenes/skill_checks/`, its root extending `SkillCheck`) and holds its tuning, like the dial's presses, zone width and speed. A harder variant is another `.tres` with different numbers. To add one, list its `.tres` in the minigame overlay's Skill Checks in the inspector. A fight shows you and your masked opponent: J (or Z) strikes, K (or X) grabs, and L, C or Space guards, or tap the buttons. A guard is a tap: it takes 0.7 seconds to come up (`GUARD_RAISE_MS`, half a strike's windup), so it blocks a strike seen coming but not one about to land, then stays up for 3.2 seconds (`GUARD_MS`) and drops on its own. After a guard ends (dropping, dropped, grabbed through, or lowered to attack) another can't be raised for 1.4 seconds (`GUARD_COOLDOWN_MS`), the Guard button greys out meanwhile, and a guard pressed just before then waits and goes up as soon as it can. So a guard can't be held all fight: a strike started as one drops always lands. A strike (1.4 second windup) hits an open fighter but bounces off a guard and leaves you dazed for 2.2 seconds; a grab (1.6 seconds) breaks a guard and misses an open fighter. A grab is only a little slower than a strike, so striking out of one takes a read, starting the strike almost as they start the grab; seeing it coming and then striking is too late, so holding a guard all fight gets grabbed. In short: guard a strike, strike a grab, grab a guard. A bar over each fighter fills as their move winds up so it can be answered in time, a press made while you're winding up or dazed is held for a moment and sent as soon as you're free, and HIT!, GRABBED!, BLOCKED! and MISSED pop up over the fighters. Each fighter takes 3 hits and a fight goes on until someone loses them all, so it shows no timer; the fight round itself lasts 24 seconds on `--fast` servers (30 normally), which is how long everyone else plays, and runs on while a fight does. Every minigame timer counts whole seconds.

Everyone else gets a practice game with nothing riding on it, picked at random from the overlay's Practice Checks: any of the games above except the dial, or Card Memory (`skill_checks/memory.tres`). In practice the arcade games keep going (a crash or a finished hole, wave or hand starts the next) and keep a score. In Card Memory 16 cards show face up for two seconds, then turn over, and you turn two at a time (tap them, or move with the arrow keys and press Space) to find the 8 pairs. Pairs stay up, and clearing the board deals a new one. The practice game you get carries on from stage to stage through the night, as it was, until a skill check or fight that counts interrupts it; the next practice after that is picked at random again, and so is the first one each night, never the game you were just playing. Once your skill check is decided it carries on as practice until the stage ends, and once your fight is decided you get a practice game.

The client connects to `ws://127.0.0.1:9090/ws`. To use another server, pass it after `--`: `godot --path front -- --server=ws://192.168.1.20:9090/ws`. In a browser it connects to port 9090 on the host that served the page (`wss://` when the page is on `https://`, which the server doesn't support yet). To play several Godot clients on one machine, run the game more than once with different names, or mix Godot and terminal clients in one lobby.

Everyone in the lobby walks around the same town. Each client sends its player's position about 15 times a second while it changes, and the server passes it on to the others, who glide each character toward its latest position. A player's look from the customizer is sent on joining, so others see them as they dressed. Dead players show faded. Movement is only relayed, never stored, and other players don't block you.

| Path | What it is |
|------|------------|
| `scenes/main/` | The game's scenes: `lobby`, `customizer`, `town`, plus what the town places: `player` (you), `remote_player` (everyone else), `house`, `hud` (players, clock, chat and actions) and `minigame_overlay`, and `minigame_tester` |
| `scenes/test/` | Standalone test scenes: `main` (walk around a field) and `wardrobe` (character preview with no save) |
| `scripts/hud/` | The town's HUD, one script per panel (`player_list`, `phase_clock`, `chat_panel`, `action_bar`), and `HudStyle`, its small translucent take on `RpgTheme`'s colors |
| `scripts/ui/` | `RpgTheme`, the dark-wood-and-gold theme the lobby screen and customizer use, built in code (`theme = RpgTheme.build()`), with their shared `backdrop()`. `ScreenScale` sets how each screen scales to the window |
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

Add `--fight-bot` to a terminal player to have it play its night fights for itself (striking, guarding and grabbing with a human-ish reaction time), so a Godot player can fight bots. Without it, a terminal player's fights are rolled.

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
| `/roll` | Have the server decide your minigame at random (a skill check passes 75% of the time, a fight is a coin flip). The terminal client does this by itself, since it can't show minigames; only `--fast` servers allow it. |
| `/will text` | Set your last will, shown to everyone when you die. Write `\n` for a new line. `/will` alone shows it. |
| `/role`, `/roles`, `/players` | Your role and team, the game's role list, and who is alive. |

The server takes `--fast` (short phases, and minigames may be rolled, which the terminal client does), `--seed N` (the same roles every game, given the same players), `--port` (default 9090), `--host` (default 127.0.0.1) and `--db` (default `webgame.db` in the directory it runs from, which is `rust/` under `just`; gitignored). `just server` runs it with normal phase lengths. To look at what a game recorded: `sqlite3 rust/webgame.db 'select * from games'`.

There is no authentication yet. A username is the whole identity: the same name always gets the same user id, which is how a player who drops reconnects to their seat (join the same code with the same name). The server only listens on localhost by default, and doesn't check the `Origin` of WebSocket connections, so don't expose it to the internet as it is.

### How a game runs

- **Cycle.** Day 0 is a short introduction, then Night 1, Day 1, Night 2, and so on.
- **Days.** Discussion, then voting. A player voted up by a majority of the living goes on trial: they make a defense (only they can talk), then everyone judges them guilty, innocent or abstains. More guilty than innocent votes means last words, a lynch, and the day ends. Otherwise voting resumes. After 3 trials, or when voting time runs out, night falls.
- **Nights.** Players pick their actions at nightfall (15 seconds), and then they lock. The rest of the night runs in stages that always take the same time: roleblocks, three rounds of fights, protection, investigations. In each stage every living player plays one minigame. Whoever acts in that stage plays a skill check, a short game on the client such as five presses on a timing dial. The client reports the chance the action should work (the dial reports hits out of five, so 3 hits is 60%), and the server rolls with it once the player is done, or with the last chance reported when the stage ends (none counts as 0). Only `rust/crates/webgame-game/src/check.rs` turns what the client sends into that chance, so the server can judge checks itself later by changing just that file. Failing means the action does nothing, though they still visit their target (a Lookout sees them, a Veteran on alert shoots them). An attack by the Mafia, a Serial Killer, a Vigilante or a lynched Jester is a fight between attacker and victim, who don't learn who the other is; the attack only goes ahead if the attacker knocks the victim out, and even then heals, guards and defense still apply. A fight isn't decided by the clock: if one is still going when its round runs out, the round quietly runs on a second at a time until someone is knocked out (the victim wins a double knockout). Only a fight still going two minutes past its round, where both players have stopped playing, goes to the victim. Jailer executions and Arsonist ignitions are skill checks. Everyone else plays a game with nothing riding on it. Once the stages are done the server works out what happened all at once: jailing, then roleblocks, then protection, then attacks, then investigations. Each player gets their own results, and the morning announces who died, with their role and last will.
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
