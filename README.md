# webgame

A top-down RPG for the browser.

## Layout

| Path | Purpose |
|------|---------|
| `front/` | Game client (Godot 4.7 project, exported to the web) |
| `rust/` | Rust workspace: the network protocol and the GDExtension the client loads |
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

The game starts in the lobby, where you can open the character customizer, create a lobby, or type a code to join one. Creating or joining takes you to the town, where you walk with WASD or the arrow keys. Lobbies are local placeholders for now: creating one makes up a code, and joining accepts any well-formed code, until the game server exists.

| Path | What it is |
|------|------------|
| `scenes/main/` | The game's scenes: `lobby`, `customizer`, `town`, plus `player` and `house`, which the town places |
| `scenes/test/` | Standalone test scenes: `main` (walk around a field) and `wardrobe` (character preview with no save) |
| `scripts/autoload/` | Globals available in every scene: `PlayerProfile` (the saved character, kept in Godot's `user://` folder) and `Session` (the current lobby) |

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
   - Install Emscripten 3.1.74 with [emsdk](https://github.com/emscripten-core/emsdk) (`./emsdk install 3.1.74`, then `./emsdk activate 3.1.74`), and set `EMSDK` in `.env` to the emsdk directory.
   - In the Godot editor, Editor > Manage Export Templates > Download and Install.
2. Run `just export-web`. It builds the extension in release mode, then exports the game to `front/build/web/index.html` (gitignored).

   Exporting from the editor (Project > Export) or testing with Remote Debug > Run in Browser also works, but neither rebuilds the extension; they copy whatever `.wasm` is already built. Run `just build-web release` before an editor export, or `just build-web` before Run in Browser, which uses the debug build.
3. Browsers won't run the export from a `file://` URL, so serve `front/build/web` with any static file server and open it over `http://`. The preset turns thread support off, so the server doesn't need special COOP/COEP headers. Any static host (itch.io, GitHub Pages, Netlify) works the same way. The Rust extension is built single-threaded to match; turning thread support on in the preset would also need a threaded build of the extension.

## Art assets

See [`assets/README.md`](assets/README.md) for the sprite format, how characters are layered, the costume sets, and the Pixelorama workflow.
