#!/bin/bash
# Check the dock in the hidden test desktop (hidden-desktop.sh), without
# touching the desktop in use: it shows only on the monitor dock.monitors names,
# and its app grid lists apps and searches them, with Omarchy's app library
# loaded by the dock itself, as a clone gets none from the shell.
#
#   tests/app-grid.sh [QUERY] [OUT_DIR]   default: "foot", a temp directory
#
# Prints ok/FAIL for each check, any QML warnings, and the paths of grid.png
# (no search) and search.png (after typing QUERY), to look at.
set -u
here=$(cd "$(dirname "$0")" && pwd)
desktop="$here/hidden-desktop.sh"
query=${1:-foot}
out=${2:-$(mktemp -d /tmp/side-dock-app-grid.XXXXXX)}
log=$XDG_RUNTIME_DIR/side-dock-test/quickshell.log
failed=0

d() { "$desktop" run "$@"; }
check() { # check <what> <expected> <actual>
  if [[ $2 == "$3" ]]; then echo "ok    $1"
  else echo "FAIL  $1: expected '$2', got '$3'"; failed=1; fi
}
# The monitors showing a layer with this namespace.
monitors_with() {
  d hyprctl layers -j | jq -r --arg n "$1" '[to_entries[] | select([.value.levels[][] | .namespace] | index($n)) | .key] | sort | join(" ")'
}

mkdir -p "$out"
"$desktop" start >/dev/null || exit 1
trap '"$desktop" stop >/dev/null' EXIT
sleep 4

check "The dock shows only on the monitor in dock.monitors" TEST-A "$(monitors_with omarchy-dock)"

"$desktop" dock apps >/dev/null
sleep 1.5
check "The app grid opens on that monitor" TEST-A "$(monitors_with omarchy-dock-apps)"
d grim -o TEST-A "$out/grid.png"
d wtype "$query"
sleep 1
d grim -o TEST-A "$out/search.png"
d wtype -k Escape
sleep 0.3

check "The dock loaded Omarchy's app library" "" "$(grep -o "could not load Omarchy's app library.*" "$log")"
grep -E "WARN|ERROR" "$log" | grep -viE "dbus|portal|StatusNotifier|Cannot open: file" | head -10
echo "screenshots: $out/grid.png $out/search.png"
exit $failed
