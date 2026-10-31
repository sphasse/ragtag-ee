#!/usr/bin/env bash
# Build EmptyEpsilon (pinned), install this repo into it, run a scenario
# headless and drive it with tools/smoke_test.py. Used by CI; works locally too.
#
#   tools/ci_headless.sh                         # build EE into .ee-build/ (about 20 min the first time)
#   EE_DIR=~/src/EmptyEpsilon tools/ci_headless.sh   # use an existing build (needs _build/EmptyEpsilon)
#   SCENARIO=scenario_80_sandbox.lua tools/ci_headless.sh
#
# Linux only. Needs: git cmake ninja-build g++ libsdl2-dev python3.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EE_COMMIT="${EE_COMMIT:-310bebd12f14d82239070445ad190d13680f124b}"  # EE-2026.09.22PR
SP_COMMIT="${SP_COMMIT:-bbe714aac5a855108ccedb43a99d8334b18ce792}"
SCENARIO="${SCENARIO:-scenario_80_sandbox.lua}"
PLAYTHROUGH="${PLAYTHROUGH:-0}"
PORT="${PORT:-8080}"

if [ -z "${EE_DIR:-}" ]; then
  EE_DIR="$ROOT/.ee-build/EmptyEpsilon"
  SP_DIR="$ROOT/.ee-build/SeriousProton"
  if [ ! -x "$EE_DIR/_build/EmptyEpsilon" ]; then
    mkdir -p "$ROOT/.ee-build"
    [ -d "$EE_DIR" ] || git clone https://github.com/daid/EmptyEpsilon.git "$EE_DIR"
    [ -d "$SP_DIR" ] || git clone https://github.com/daid/SeriousProton.git "$SP_DIR"
    git -C "$EE_DIR" fetch -q origin "$EE_COMMIT" && git -C "$EE_DIR" checkout -q "$EE_COMMIT"
    git -C "$SP_DIR" fetch -q origin "$SP_COMMIT" && git -C "$SP_DIR" checkout -q "$SP_COMMIT"
    cmake -S "$EE_DIR" -B "$EE_DIR/_build" -G Ninja -DSERIOUS_PROTON_DIR="$SP_DIR" -DCMAKE_BUILD_TYPE=Release
    ninja -C "$EE_DIR/_build"
  fi
fi

python3 "$ROOT/tools/install.py" --ee "$EE_DIR"
export HOME="${CI_HOME:-$(mktemp -d)}"          # isolated scriptstorage.json
mkdir -p "$HOME/.emptyepsilon"

cd "$EE_DIR"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./_build/EmptyEpsilon headless="$SCENARIO" httpserver="$PORT" > "$HOME/ee.log" 2>&1 &
EE_PID=$!
trap 'kill $EE_PID 2>/dev/null || true' EXIT

for i in $(seq 1 60); do
  if curl -s -m 2 --data 'return "up"' "http://127.0.0.1:$PORT/exec.lua" | grep -q up; then break; fi
  sleep 1
done
sleep 3

ARGS=(--ee "http://127.0.0.1:$PORT")
[ "$PLAYTHROUGH" = "1" ] && ARGS+=(--playthrough)
status=0
python3 "$ROOT/tools/smoke_test.py" "${ARGS[@]}" || status=$?

if grep -q "LUA-Error" "$HOME/ee.log"; then
  echo "Lua errors in the EmptyEpsilon log:"; grep -A4 "LUA-Error" "$HOME/ee.log" | head -40
  status=1
fi
exit $status
