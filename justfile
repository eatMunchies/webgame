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

# Build the native extension, then open the Godot editor
editor: build
    {{ godot }} -e --path front

# Build the native extension, then run the game
run: build
    {{ godot }} --path front
