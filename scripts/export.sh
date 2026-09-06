#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
exec "$BLENDER" --background "$ROOT/art/beachball.blend" --python-exit-code 1 --python "$ROOT/scripts/render.py" -- "$@"
