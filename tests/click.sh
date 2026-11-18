#!/bin/bash
# Click at global (x, y) and report how long until the active window's class
# matches <expected-class>.
#
# Usage: click.sh <x> <y> <expected-class> [timeout-seconds]
set -u

W=${WLRCTL:-wlrctl}
command -v "$W" >/dev/null || { echo "click.sh: wlrctl not found (set WLRCTL)" >&2; exit 1; }
(( $# >= 3 )) || { echo "Usage: click.sh <x> <y> <expected-class> [timeout-seconds]" >&2; exit 1; }

x=$1 y=$2 want=$3 timeout=${4:-8}

hyprctl dispatch "hl.dsp.cursor.move({ x = $x, y = $y })" >/dev/null
# Warping does not tell the surface under the cursor that the pointer arrived;
# a small virtual-pointer motion does.
"$W" pointer move 1 0
"$W" pointer move -1 0
sleep 0.3

ms() { local t=${EPOCHREALTIME/./}; echo $((t / 1000)); }
start=$(ms)
"$W" pointer click left

while :; do
  cls=$(hyprctl activewindow -j | jq -r .class)
  now=$(ms)
  if [[ $cls == "$want" ]]; then
    # The dock must leave the pointer where the click happened.
    sleep 0.2
    read -r cx cy < <(hyprctl cursorpos | tr -d ',')
    if [[ $cx != "$x" || $cy != "$y" ]]; then
      echo "CURSOR MOVED: focused $cls after $((now - start)) ms, cursor $x,$y -> $cx,$cy"
      exit 1
    fi
    echo "focused $cls after $((now - start)) ms, cursor stayed"
    exit 0
  fi
  if (( now - start > timeout * 1000 )); then
    echo "TIMEOUT: active is $cls"
    exit 1
  fi
  sleep 0.02
done
