-- Hyprland's side of the dock's emptyWorkspace setting.
--
-- The dock loads this file into Hyprland's Lua when it first needs it, and
-- reports each app it starts while none of the app's windows is open: the
-- window classes the app's desktop entry claims, and the monitor it was started
-- from. When a window of one of those classes opens, the window.open hook below
-- moves it to the lowest empty workspace slot of that monitor (Omarchy's
-- o.workspaces) and shows that workspace, hiding the scratchpad if it is open.
-- The hook runs before the window is drawn, so it appears there directly. A
-- window that already has a workspace of its own on that monitor stays. A
-- launch whose window hasn't opened within a minute is dropped.

local MAX_AGE = 60

local M = { pending = {} }
side_dock_empty_workspace = M

-- Called by the dock: classes is a list of window classes, matched ignoring
-- case; monitor is a monitor name.
function M.launch(classes, monitor)
  local set = {}
  for _, class in ipairs(classes) do set[class:lower()] = true end
  table.insert(M.pending, { classes = set, monitor = monitor, at = os.time() })
end

-- The launch the window comes from, used up, or nil.
local function take(window)
  local now = os.time()
  local class = window.class:lower()
  local found = nil
  local kept = {}
  for _, launch in ipairs(M.pending) do
    if now - launch.at > MAX_AGE then
      -- dropped
    elseif not found and launch.classes[class] then
      found = launch
    else
      table.insert(kept, launch)
    end
  end
  M.pending = kept
  return found
end

local function first_of_app(window)
  for _, other in ipairs(hl.get_windows()) do
    if other.address ~= window.address and other.class == window.class then return false end
  end
  return true
end

local function empty(workspace)
  if not workspace then return true end
  for _, other in ipairs(workspace:get_windows()) do
    if other.mapped then return false end
  end
  return true
end

local function alone(window)
  for _, other in ipairs(window.workspace:get_windows()) do
    if other.address ~= window.address and other.mapped then return false end
  end
  return true
end

hl.on("window.open", function(window)
  if not window or window.floating or window.class == "" or not window.workspace then return end
  local launch = take(window)
  if not launch or not first_of_app(window) then return end

  local monitor = hl.get_monitor(launch.monitor)
  if not monitor then return end
  local workspace = window.workspace
  if not workspace.special and workspace.monitor and workspace.monitor.name == monitor.name and alone(window) then return end

  local slot = nil
  for candidate = 1, o.workspaces.slots do
    if empty(hl.get_workspace(o.workspaces.workspace_id(monitor, candidate))) then
      slot = candidate
      break
    end
  end
  if not slot then return end
  local target = o.workspaces.workspace_id(monitor, slot)

  -- Keep the pointer where it is: cursor warps off for the switch, restored
  -- after, even if a step fails.
  local saved = {
    no_warps = hl.get_config("cursor.no_warps"),
    warp_on_change_workspace = hl.get_config("cursor.warp_on_change_workspace"),
  }
  hl.config({ cursor = { no_warps = true, warp_on_change_workspace = 0 } })
  pcall(function()
    local special = monitor.active_special_workspace
    if special then hl.dispatch(hl.dsp.workspace.toggle_special(special.name:sub(#"special:" + 1))) end
    -- Show the slot on the monitor first, so a new workspace is created there
    -- rather than on whichever monitor has focus.
    hl.dispatch(o.workspaces.focus(slot, monitor.name))
    hl.dispatch(hl.dsp.window.move({
      workspace = tostring(target), window = "address:" .. window.address, follow = true,
    }))
  end)
  hl.config({ cursor = saved })
end)
