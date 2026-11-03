# Machine-specific settings (EMSDK, GODOT) come from a gitignored `.env`; copy `.env.example` to
# start one. Variables already set in your shell win over the file.
set dotenv-load

# Godot executable; override with GODOT in .env if `godot` isn't on PATH.
godot := env("GODOT", "godot")

# List recipes
default:
    @just --list

# Build the native GDExtension used by the editor
[arg("profile", pattern="debug|release")]
[working-directory("rust")]
build profile="debug":
    cargo build {{ if profile == "release" { "--release" } else { "" } }}

# Build the wasm GDExtension used by the web export (needs nightly Rust and EMSDK)
[arg("profile", pattern="debug|release")]
[working-directory("rust")]
build-web profile="debug":
    #!/usr/bin/env bash
    set -euo pipefail
    : "${EMSDK:?EMSDK is not set; point it at your emsdk checkout, e.g. in .env (see .env.example)}"
    EMSDK_QUIET=1 source "$EMSDK/emsdk_env.sh"
    cargo +nightly build -p webgame-godot-rust -Zbuild-std --target wasm32-unknown-emscripten \
        {{ if profile == "release" { "--release" } else { "" } }}

# Build the release wasm, then export the game to front/build/web
export-web: (build-web "release")
    {{ godot }} --headless --path front --export-release Web

# Run tests: `unit` (cargo test), `godot` (GdUnit4 suites in front/tests), or `all`. Extra
# arguments go to that runner: `just test unit -- --nocapture`, or GdUnit4 options such as
# `just test godot -a res://tests/state_machine_test.gd` (run one suite) or `-i <suite>` (skip one).
[arg("kind", pattern="all|unit|godot")]
[positional-arguments]
test kind="all" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    kind="$1"
    shift
    if [[ "$kind" == all && $# -gt 0 ]]; then
        echo "extra arguments need a test kind: just test unit ... or just test godot ..." >&2
        exit 1
    fi
    if [[ "$kind" == all || "$kind" == unit ]]; then
        (cd rust && cargo test "$@")
    fi
    if [[ "$kind" == all || "$kind" == godot ]]; then
        (cd rust && cargo build)
        # Import first so a fresh checkout knows about the extension and its assets.
        if ! out=$("{{ godot }}" --headless --path front --import 2>&1); then
            echo "$out" >&2
            exit 1
        fi
        if [[ $# -eq 0 ]]; then
            set -- -a res://tests
        fi
        # --fixed-fps steps every frame by exactly 1/60 s, regardless of how long it takes.
        # GdUnit4 refuses to run headless unless told to, and stops at the first failure unless
        # given -c. Reports go to front/reports.
        "{{ godot }}" --headless --path front --fixed-fps 60 \
            -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c "$@"
    fi

# Build the native extension, then open the Godot editor
editor: build
    {{ godot }} -e --path front

# Build the native extension, then run the game
run: build
    {{ godot }} --path front

# Open COUNT game windows in one lobby, tiled in a grid: Ada hosts, the rest join. Start a
# server first (`just play`). Ctrl-C closes every window.
[arg("count", pattern="[1-9]|1[0-5]")]
clients count="4": build
    #!/usr/bin/env bash
    set -euo pipefail
    names=(Ada Bram Cleo Dax Eve Finn Gus Hana Ivy Jon Kit Lea Moe Nia Otto)
    width=640 height=360
    cols=1
    while (( cols * cols < {{ count }} )); do cols=$((cols + 1)); done
    trap 'kill $(jobs -p) 2>/dev/null || true' EXIT
    launch() {
        # $1 is the window's place in the grid; the title bar takes about 40 pixels.
        local x=$(( $1 % cols * width )) y=$(( $1 / cols * (height + 40) ))
        "{{ godot }}" --resolution "${width}x${height}" --position "$x,$y" --path front -- "${@:2}"
    }
    host_log=$(mktemp)
    launch 0 --name=Ada --create > "$host_log" 2>&1 &
    code=""
    for _ in $(seq 100); do
        code=$(sed -n 's/^Joined lobby \([A-Z0-9]*\)$/\1/p' "$host_log" | head -1)
        [[ -n "$code" ]] && break
        sleep 0.2
    done
    if [[ -z "$code" ]]; then
        cat "$host_log" >&2
        echo "Ada never got a lobby. Is the server running (just play)?" >&2
        exit 1
    fi
    echo "Lobby $code. Press Start game in Ada's window."
    for ((i = 1; i < {{ count }}; i++)); do
        launch "$i" --name="${names[i]}" --join="$code" > /dev/null 2>&1 &
    done
    wait

# Run the game server. Options go to it: --fast (short phases), --seed N (repeatable roles),
# --port, --db. Its SQLite file defaults to rust/webgame.db.
[working-directory("rust")]
server *args:
    cargo run -p webgame-server -- {{ args }}

# Run the game server with short phases, for playing a test game from terminals. Terminal
# clients roll their night minigames, which only --fast allows.
play: (server "--fast")

# Play from a terminal: `just cli --name Ada --create`, then `just cli --name Bram --join CODE`
[working-directory("rust")]
cli *args:
    cargo run -p webgame-cli -- {{ args }}
