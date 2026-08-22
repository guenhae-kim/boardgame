#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

godot --headless --editor --path "$PROJECT_DIR/client" --quit
godot --headless --path "$PROJECT_DIR/client" \
  --export-release Web "$PROJECT_DIR/client/build/web/index.html"

echo "Web export ready: $PROJECT_DIR/client/build/web/index.html"
