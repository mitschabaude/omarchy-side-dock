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

# A window's app id is up to the app, and a minimized window shows in the dock
# even without a desktop entry. An id naming a file that blocks when opened
# (here a FIFO nobody writes to) must not be read as the window's icon. A thread
# blocked opening a FIFO waits in the kernel's wait_for_partner.
fifo=$(mktemp -u /tmp/side-dock-fifo.XXXXXX)
mkfifo "$fifo"
trap '"$desktop" stop >/dev/null; timeout 1 sh -c "echo > $fifo"; rm -f "$fifo"' EXIT
d hyprctl dispatch "hl.dsp.exec_cmd(\"foot --app-id $fifo -e sh -c 'sleep 600'\", { workspace = \"special:minimized silent\" })" >/dev/null
sleep 2
shell_pid=$(pgrep -f "^quickshell -p $XDG_RUNTIME_DIR/side-dock-test/shell/shell.qml" | head -1)
check "A minimized window whose app id names a blocking file doesn't block the dock" 0 \
  "$(cat /proc/"$shell_pid"/task/*/wchan 2>/dev/null | tr '\0' '\n' | grep -c wait_for_partner)"

# The dock looks items up by key, the app id for a window without an entry. An
# id that every JavaScript object already has as a property (constructor,
# toString) must still make an item of its own, not break building the dock.
d hyprctl dispatch "hl.dsp.exec_cmd(\"foot --app-id constructor -e sh -c 'sleep 600'\", { workspace = \"special:minimized silent\" })" >/dev/null
sleep 2
check "A minimized window whose app id is an object property doesn't break the dock" "" \
  "$(grep -m1 -oE '(TypeError|ReferenceError)[^"]*' "$log")"

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
