#!/bin/bash
# Check dock.emptyWorkspace in the hidden test desktop (hidden-desktop.sh): an
# app started from the dock's app grid while none of its windows is open opens
# on the lowest empty workspace of the grid's monitor, with the scratchpad
# hidden first, and an app with a window open starts where the user is.
#
#   tests/empty-workspace.sh
#
# Prints ok/FAIL for each check.
set -u
here=$(cd "$(dirname "$0")" && pwd)
desktop="$here/hidden-desktop.sh"
config=$XDG_RUNTIME_DIR/side-dock-test/config/omarchy/shell.json
failed=0

d() { "$desktop" run "$@"; }
check() { # check <what> <expected> <actual>
  if [[ $2 == "$3" ]]; then echo "ok    $1"
  else echo "FAIL  $1: expected '$2', got '$3'"; failed=1; fi
}
foot_windows() { d hyprctl clients -j | jq -r '[.[] | select(.class == "foot") | .workspace.name] | sort | join(" ")'; }
shown() { d hyprctl monitors -j | jq -r '.[] | select(.name == "TEST-A") | "\(.activeWorkspace.id) \(.specialWorkspace.name)"' | sed 's/ $//'; }
# Start foot from the app grid, and wait for its window count to reach <n>.
grid_launch() {
  "$desktop" dock apps >/dev/null
  sleep 1.5
  d wtype foot
  sleep 0.5
  d wtype -k Return
  for _ in $(seq 50); do
    [[ $(d hyprctl clients -j | jq '[.[] | select(.class == "foot")] | length') == "$1" ]] && return
    sleep 0.1
  done
}

"$desktop" start >/dev/null || exit 1
trap '"$desktop" stop >/dev/null' EXIT
echo '{ "dock": { "position": "right", "monitors": ["TEST-A"], "pinned": ["foot.desktop"], "emptyWorkspace": true } }' > "$config"
sleep 4

first=$(d hyprctl monitors -j | jq -r '.[] | select(.name == "TEST-A") | .activeWorkspace.id')
d hyprctl dispatch "hl.dsp.exec_cmd(\"foot --app-id busy -e sh -c 'sleep 600'\", { workspace = \"$first\" })" >/dev/null
sleep 1

grid_launch 1
check "An app with no window opens on the lowest empty workspace" "$((first + 1))" "$(foot_windows)"
check "  which the monitor shows" "$((first + 1))" "$(shown)"

d hyprctl dispatch "hl.dsp.focus({ workspace = \"$first\" })" >/dev/null
sleep 0.3
grid_launch 2
check "An app with a window open starts where the user is" "$first $((first + 1))" "$(foot_windows)"

for address in $(d hyprctl clients -j | jq -r '.[] | select(.class == "foot") | .address'); do
  d hyprctl dispatch "hl.dsp.window.close({ window = \"address:$address\" })" >/dev/null
done
d hyprctl dispatch 'hl.dsp.workspace.toggle_special("scratchpad")' >/dev/null
sleep 0.5
check "  (the scratchpad is open)" "$first special:scratchpad" "$(shown)"
grid_launch 1
check "From the scratchpad, an app with no window opens on an empty workspace" "$((first + 1))" "$(foot_windows)"
check "  with the scratchpad hidden" "$((first + 1))" "$(shown)"

exit $failed
