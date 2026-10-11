#!/bin/zsh
# Regenerates docs/img/teaser.png, the picture at the top of the README: builds the Debug app, points it at
# made-up demo servers (demo_server.py), takes snapshots through its debug aids (M2H_*, see
# Support/DebugAids.swift) and lays out crops of them with collage.swift.
#
#   Scripts/teaser/make-teaser.sh
#
# Each snapshot brings the app to the front for a moment. Snapshots come from ScreenCaptureKit when the Debug
# build may record the screen (System Settings > Privacy & Security > Screen & System Audio Recording);
# otherwise the app draws its views itself, which can miss materials such as the sidebar's, and this script
# says so. Crops are in points of the 960 x 620 window (its minimum width); a layout change can need new ones.
# Preferences go to a scratch store, never the installed app's.
set -euo pipefail

cd "$(dirname "$0")/../.."
root=$PWD
here=Scripts/teaser
project=mcprotocol2human-surface/mcprotocol2human-surface.xcodeproj
scheme=mcprotocol2human-surface
out=build/teaser
shots=$out/shots
suite=m2h-teaser
port=8765
window_width=960
window_height=620

server_pid=
work=$(mktemp -d)
cleanup() {
  [[ -n $server_pid ]] && kill $server_pid 2>/dev/null || true
  rm -rf "$work"
  defaults delete $suite >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$shots"
echo "Building $scheme (Debug)"
if ! xcodebuild -project "$project" -scheme "$scheme" -configuration Debug -derivedDataPath "$out/DerivedData" build \
    > "$out/xcodebuild.log" 2>&1; then
  echo "Build failed. Errors:"
  grep -E 'error:' "$out/xcodebuild.log" | sed 's/^ *//' | sort -u | head -20
  echo "Full log: $out/xcodebuild.log"
  exit 1
fi
app="$root/$out/DerivedData/Build/Products/Debug/$scheme.app/Contents/MacOS/$scheme"

# The stdio servers run as `python3 -m <name>`, which reads well in the pictures; these modules start them.
print 'from demo_server import SERVERS, serve_stdio\nserve_stdio(SERVERS["notes"], "modern")' > "$work/notes_server.py"
print 'from demo_server import SERVERS, serve_stdio\nserve_stdio(SERVERS["calendar"], "legacy")' > "$work/calendar_server.py"
env='{ "PYTHONPATH": "'"${work}:${root}/${here}"'", "PYTHONDONTWRITEBYTECODE": "1" }'
cat > "$work/servers.json" <<EOF
{
  "mcpServers": {
    "notes": { "type": "stdio", "command": "python3", "args": ["-m", "notes_server"], "env": $env },
    "calendar": { "type": "stdio", "command": "python3", "args": ["-m", "calendar_server"], "env": $env },
    "files": { "type": "http", "url": "http://127.0.0.1:$port/mcp" }
  }
}
EOF

probe() { curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":0,"method":"ping"}' "http://127.0.0.1:$port/mcp"; }
if probe; then
  echo "Port $port is taken; the files demo server needs it."
  exit 1
fi
python3 "$here/demo_server.py" files modern --http $port 2> "$out/http-server.log" &
server_pid=$!
for _ in {1..50}; do probe && break; sleep 0.1; done
probe || { echo "The files demo server did not start; see $out/http-server.log"; exit 1; }

# shoot <name> [VAR=value ...]: one snapshot of the main window into $shots/<name>.png
shoot() {
  local name=$1; shift
  rm -f "$shots/$name.png"
  env M2H_SERVERS_FILE="$work/servers.json" M2H_DEFAULTS_SUITE=$suite \
      M2H_WINDOW_SIZE=${window_width}x${window_height} \
      M2H_SNAPSHOT="$root/$shots/$name.png" M2H_SNAPSHOT_QUIT=1 M2H_SNAPSHOT_DELAY=20 \
      "$@" "$app" > "$shots/$name.log" 2>&1 || true
  [[ -f "$shots/$name.png" ]] || { echo "No snapshot for $name; see $shots/$name.log"; exit 1; }
  grep -q '^Image: ScreenCaptureKit' "$shots/$name.txt" \
    || echo "  $name: drawn by the app, not captured; the Debug build may lack Screen Recording permission"
}

echo "Taking snapshots; the app comes to the front each time"
shoot notes M2H_SELECT=notes M2H_SELECT_PAGE=delete_notebook
shoot calendar-traffic M2H_SELECT=calendar M2H_SELECT_PAGE=traffic

# Tiles: the window's left part (servers and tools), a tool's details padded with empty pane from further
# down, and the legacy server's traffic with the toolbar above it.
swift "$here/collage.swift" docs/img/teaser.png $window_width 2200 \
  "$shots/notes.png:0,0,464,424" \
  "$shots/notes.png:465,60,495,400,550" \
  "$shots/calendar-traffic.png:465,0,495,424"
