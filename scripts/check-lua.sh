#!/usr/bin/env bash
# Checks every addon .lua file, the same way locally and in GitHub:
#  1. Compiles it with LuaJIT (the game's Lua 5.1): syntax errors and the
#     limit of 200 local variables per function.
#  2. luacheck with all its warnings (settings in .luacheckrc). A global that is
#     not listed there is a typo or a lost declaration ("attempt to call/index a
#     nil value" in the game); unused or shadowed variables are usually bugs too.
# Usage: bash scripts/check-lua.sh   (or: npm run check:lua)
set -euo pipefail
cd "$(dirname "$0")/.."

LUACHECK=$(command -v luacheck || echo "$HOME/.luarocks/bin/luacheck")

mapfile -t FILES < <(git ls-files --cached --others --exclude-standard '*.lua' | grep -v '^dev/')
if [ ${#FILES[@]} -eq 0 ]; then
	echo "No Lua files to check."
	exit 0
fi

status=0
for f in "${FILES[@]}"; do
	if ! out=$(luajit -e "assert(loadfile('$f'))" 2>&1); then
		echo "$out"
		status=1
	fi
done
[ $status -eq 0 ] && echo "LuaJIT: ${#FILES[@]} file(s) compile."

"$LUACHECK" -- "${FILES[@]}" || status=1
exit $status
