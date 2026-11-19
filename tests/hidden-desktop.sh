#!/bin/bash
# A private Hyprland for testing the dock without touching the desktop in use:
# it draws to two virtual monitors nobody sees, runs with its own D-Bus session,
# and loads only a minimal config plus Omarchy's per-monitor workspaces. The dock runs in it in a Quickshell of its
# own, not the Omarchy shell, so it gets no shell API, much as a clone gets
# little of it. Its host window sits on a hidden special workspace and never
# takes focus.
#
#   hidden-desktop.sh start    start it (TEST-A and TEST-B, 1920x1080 each)
#   hidden-desktop.sh run ...  run a command inside it, e.g. foot, wtype, grim
#   hidden-desktop.sh dock ... call the dock's IPC, e.g. "apps" for the grid
#   hidden-desktop.sh reload   restart the dock after editing the plugin
#   hidden-desktop.sh stop     stop it, and everything opened inside it
set -euo pipefail

plugin=$(cd "$(dirname "$0")/.." && pwd)
omarchy=${OMARCHY_PATH:-/usr/share/omarchy}
state=$XDG_RUNTIME_DIR/side-dock-test

# Commands below talk to the test instance; the host stays on its own vars.
run() {
  # shellcheck disable=SC1091
  (source "$state/env" && "$@")
}

start_dock() {
  # XDG_CONFIG_HOME points the dock at the test's own shell.json.
  run hyprctl dispatch "hl.dsp.exec_cmd(\"env XDG_CONFIG_HOME=$state/config quickshell -p $state/shell/shell.qml > $state/quickshell.log 2>&1\")" >/dev/null
}

start() {
  if [[ -f $state/env ]]; then
    echo "already running (stop it first)" >&2
    exit 1
  fi
  mkdir -p "$state/shell" "$state/config/omarchy"
  # The dock on the right edge of TEST-A only, with one pin, set as a user
  # would.
  echo '{ "dock": { "position": "right", "monitors": ["TEST-A"], "pinned": ["foot.desktop"] } }' > "$state/config/omarchy/shell.json"

  # The dock's qs.Commons and qs.Ui imports, and those of Omarchy's app
  # library that it loads, resolve against this config root.
  ln -sfn "$omarchy/shell/Commons" "$state/shell/Commons"
  ln -sfn "$omarchy/shell/Ui" "$state/shell/Ui"
  ln -sfn "$plugin" "$state/shell/plugin"
  cat > "$state/shell/shell.qml" <<'EOF'
import Quickshell
import "plugin" as Plugin

ShellRoot {
  Plugin.Dock { }
}
EOF

  cat > "$state/hyprland.lua" <<EOF
hl.config({
  -- As in Omarchy, a window opens on the workspace in front, not on the one
  -- its launcher was started on.
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true, initial_workspace_tracking = 0 },
  ecosystem = { no_update_news = true, no_donation_nag = true },
})
-- Draw only on the virtual monitors, never into the host window.
hl.monitor({ output = "WAYLAND-1", disabled = true })
hl.monitor({ output = "TEST-A", mode = "1920x1080", position = "0x0", scale = 1 })
hl.monitor({ output = "TEST-B", mode = "1920x1080", position = "1920x0", scale = 1 })
-- Omarchy's per-monitor workspaces (o.workspaces), which the dock's
-- emptyWorkspace setting uses. Its state goes to XDG_STATE_HOME, which is the
-- test's own.
package.path = "$omarchy/?.lua;" .. package.path
require("default.hypr.helpers")
require("default.hypr.monitor-workspaces")
EOF

  local before
  before=$(hyprctl instances -j | jq -c '[.[].instance]')
  hyprctl dispatch "hl.dsp.exec_cmd(\"env XDG_STATE_HOME=$state/state dbus-run-session -- Hyprland --config $state/hyprland.lua > $state/hyprland.log 2>&1\", { workspace = \"special:side-dock-test silent\", no_initial_focus = true })" >/dev/null

  local instance=""
  for _ in $(seq 100); do
    instance=$(hyprctl instances -j | jq -r --argjson before "$before" \
      '[.[] | select(.instance as $i | $before | index($i) | not)][0] // empty | "\(.instance) \(.wl_socket) \(.pid)"')
    [[ -n $instance ]] && break
    sleep 0.1
  done
  if [[ -z $instance ]]; then
    echo "the test Hyprland did not start; see $state/hyprland.log" >&2
    exit 1
  fi

  local signature socket pid
  read -r signature socket pid <<< "$instance"
  cat > "$state/env" <<EOF
export HYPRLAND_INSTANCE_SIGNATURE=$signature WAYLAND_DISPLAY=$socket
TEST_PID=$pid
EOF

  for _ in $(seq 50); do
    run hyprctl monitors >/dev/null 2>&1 && break
    sleep 0.1
  done
  run hyprctl output create headless TEST-A >/dev/null
  run hyprctl output create headless TEST-B >/dev/null
  start_dock
  echo "started: $socket (Hyprland pid $pid)"
}

reload() {
  run pkill -f "quickshell -p $state/shell/shell.qml" || true
  sleep 0.3
  start_dock
}

stop() {
  [[ -f $state/env ]] || { echo "not running"; return; }
  # shellcheck disable=SC1091
  source "$state/env"
  # Exiting the test Hyprland closes what runs inside it, and ends its D-Bus.
  hyprctl dispatch 'hl.dsp.exit()' >/dev/null 2>&1 || true
  for _ in $(seq 50); do
    kill -0 "$TEST_PID" 2>/dev/null || break
    sleep 0.1
  done
  if kill -0 "$TEST_PID" 2>/dev/null; then kill "$TEST_PID"; fi
  rm -rf "$state"
  echo "stopped"
}

case ${1:-} in
  start) start ;;
  stop) stop ;;
  reload) reload ;;
  run) shift; run "$@" ;;
  dock) shift; run quickshell ipc -p "$state/shell/shell.qml" call omarchy.dock "$@" ;;
  *) sed -n '2,13p' "$0"; exit 2 ;;
esac
