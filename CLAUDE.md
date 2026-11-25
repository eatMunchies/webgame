# Notes for agents working on webgame (Table of Salem)

README.md is the full description of how the game, client, server and tools work, and it is kept current: read the parts you're touching first, and update it in the same commit as any change to behavior, layout or commands. It's written as plain, detailed prose; match that.

## What the game is for

- It's played **in person, around one table**, each player with a phone as their assistant. People talk out loud. The chat is mostly a record of what happened and the way terminal bots (`just cli`) talk; don't design features that need people to type.
- **Phones first.** Every UI change has to work on a portrait phone (try 405x720) as well as a wide window (960x540). Typing on a phone goes through `TextPrompt` (`front/scripts/ui/text_prompt.gd`), a box in the upper middle of the screen, clear of the on-screen keyboard; the typing test instead moves itself to the top half and takes the keyboard (`Session.keyboard_minigame`).
- **Nothing on screen should give your role away** to someone looking over your shoulder. The roster doesn't print your role; the role card (ID card button) does. Known leak still open: night ability buttons are named after the ability ("Interrogate").
- **Night timing must not leak information.** Every night stage always runs its full time, whether anyone acts in it or not. Night is Choosing, Roleblocks, then two Actions rounds (`ACTION_ROUNDS`); see the README's Nights section and `Game::schedule_actions`.

## Building and testing

- `just build` builds the GDExtension the Godot client loads; Godot won't, and the editor or a test run needs it after any Rust change.
- `just test` runs both suites: `cargo test` and the GdUnit4 suites in `front/tests` (`just test unit`, `just test godot`). CI (`.github/workflows/tests.yml`) runs the Godot suite on every PR.
- Godot isn't installed by default in a fresh container. CI downloads Godot 4.7.2 (`https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`); unzip it and set `GODOT` to the binary (in `.env`, or on the command line).
- A fresh checkout needs `godot --headless --path front --import` once before scripts can find each other's `class_name`s; `just test godot` does this for you.
- `cargo fmt` reformats `rust/crates/webgame-godot-rust/src/state_machine.rs`, which isn't formatted upstream. Leave it out of unrelated commits (`git checkout` it after formatting).
- `cargo clippy --all-targets` should stay clean.

## Checking the UI without a screen

`just shots 405x720 --name=Ada --create` plays the game in a virtual display (`xvfb-run`) and saves a frame every few seconds to `front/reports/shots` (see `front/tools/shoot.gd` for its settings). For a whole game, start a server on a free port (`cargo run -p webgame-server -- --port 9393 --fast`; 9090 may be taken on shared machines), host or join with terminal bots fed through FIFOs, and run two clients at once: one 405x720 and one 960x540. Then look at the frames.

Things that bite when scripting Godot this way:
- A `--script` SceneTree script compiles before autoloads exist: reach Session as `root.get_node("Session")`, and don't name classes whose scripts use autoloads (duck-type or `load()` by path).
- `Input.parse_input_event` takes window pixels, not HUD units: map a point with `root.get_final_transform()`.
- Skill checks and fights open with a 3 second countdown during which the game is hidden; wait it out.
- On a phone one tap arrives as a touch and a made-up mouse click. Anything that opens on press can be closed again by the second event (that's why `TextPrompt` ignores its backdrop briefly after opening).
- Don't `pkill -f` a pattern that also appears in your own shell command; it kills the command.

## Server, client and deploys

- The server and the web client share the postcard protocol in `webgame-protocol` and are deployed together (Tests, then Deploy, build both images from the same commit on `main`). A protocol change is fine as long as both sides ship together; say so in the PR.
- Rolling minigames (what terminal bots do) needs the server's `--rolls` flag (`--fast` implies it). The deployed server doesn't have it yet.
- A dropped connection (phones drop it when the browser is backgrounded) isn't a kick: the client reconnects for 90 s (`RECONNECT_SECONDS`) and the server holds the seat (`RECONNECT_GRACE`).

## How the owner likes to work

- Show UI changes with screenshots from a real run (both screen shapes), not descriptions. Before/after helps when a layout is up for a decision.
- Ask about real layout or design choices before building them; take the obvious defaults otherwise.
- Branch per change, open a PR, wait for CI, and merge only when asked (often "if CI is good, merge").
- Commit messages: `type: Capitalized summary` (feat, fix, docs, build...), then a body saying what changed and why. **No Claude attribution** anywhere: no `Co-Authored-By` trailer, no "Generated with Claude Code" line in PRs.
