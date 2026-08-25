#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$PROJECT_DIR/server"
npm test

cd "$PROJECT_DIR"
godot --headless --path client --script res://tests/RuleTests.gd
godot --headless --path client --script res://tests/FlowTests.gd
godot --headless --path client --script res://tests/DiceSafetyTests.gd
godot --headless --path client --script res://tests/OnlineFlowTests.gd
godot --headless --path client --script res://tests/KenneyAssetTests.gd
"$PROJECT_DIR/scripts/export_web.sh"

echo "Server tests and Godot Web export passed."
