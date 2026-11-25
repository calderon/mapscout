#!/usr/bin/env bash
# Runs the unit tests (busted, spec/*_spec.lua) with Lua 5.1, the game's version
# (locally busted is installed for LuaJIT; in GitHub, for lua5.1).
# Usage: bash scripts/test-lua.sh   (or: npm test)
set -euo pipefail
cd "$(dirname "$0")/.."
BUSTED=$(command -v busted || echo "$HOME/.luarocks/bin/busted")
"$BUSTED" "$@"
