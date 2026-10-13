#!/usr/bin/env bash
# Builds the GDExtension for the Web export (wasm32-unknown-emscripten, single-threaded).
# Extra arguments go to cargo, e.g. `./build-web.sh --release`.
#
# Needs nightly Rust with rust-src and the wasm32-unknown-emscripten target, plus Emscripten 3.1.74.
# EMSDK must point at your emsdk checkout; this sources its emsdk_env.sh.
#
# Environment files next to this script are loaded in this order, later files overriding earlier ones:
#   .env                  shared defaults (committed)
#   .env.local            your machine, e.g. EMSDK=$HOME/emsdk (gitignored)
#   .env.<mode>           mode defaults (committed)
#   .env.<mode>.local     your machine, for that mode only (gitignored)
# <mode> is "production" with --release and "development" otherwise. Variables already set in your
# shell win over all of these. The files are sourced as bash, so use KEY=value and quote spaces.
set -euo pipefail
cd "$(dirname "$0")"

mode=development
for arg in "$@"; do
    case "$arg" in
        --release | -r) mode=production ;;
    esac
done

inherited=$(export -p)
set -a
for file in .env .env.local ".env.$mode" ".env.$mode.local"; do
    if [[ -f "$file" ]]; then
        # shellcheck disable=SC1090
        source "$file"
    fi
done
set +a
eval "$inherited"

if [[ -z "${EMSDK:-}" ]]; then
    echo "EMSDK is not set. Point it at your emsdk checkout, for example in rust/.env.local:" >&2
    echo "    EMSDK=\$HOME/emsdk" >&2
    exit 1
fi
if [[ ! -f "$EMSDK/emsdk_env.sh" ]]; then
    echo "EMSDK=$EMSDK has no emsdk_env.sh; is it an emsdk checkout?" >&2
    exit 1
fi
# shellcheck disable=SC1091
EMSDK_QUIET=1 source "$EMSDK/emsdk_env.sh"

exec cargo +nightly build -Zbuild-std --target wasm32-unknown-emscripten -p webgame-godot-rust "$@"
