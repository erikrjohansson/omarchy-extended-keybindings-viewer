-- Extended Keybindings Viewer: load once from ~/.config/hypr/bindings.lua with dofile().
-- Replaces Omarchy's SUPER + K list with the Extended Keybindings Viewer overlay. The plain list
-- stays available as `omarchy menu keybindings`.
local viewer_id = "io.github.erikrjohansson.extended-keybindings-viewer"
local viewer_layer = "omarchy-extended-keybindings-viewer"
local viewer_submap = "io.github.erikrjohansson.extended-keybindings-viewer"

hl.unbind("SUPER + K")
o.bind("SUPER + K", "Keybindings", "omarchy-shell shell toggle " .. viewer_id)

-- While the key map is open no other binding fires (except ones marked
-- universal): pressed combinations only show what they do. The submap is
-- entered and left with the overlay's layer, so closing it (or the shell
-- exiting) restores the bindings.
--
-- The submap that was active before is kept in a runtime file as well, since
-- a config reload while the key map is open starts this file afresh.
-- Only in the owner-private runtime directory; without one, nothing is kept.
local runtime_dir = os.getenv("XDG_RUNTIME_DIR")
local state_file = runtime_dir and runtime_dir ~= "" and (runtime_dir .. "/io.github.erikrjohansson.extended-keybindings-viewer.previous-submap") or nil

local function remember(name)
  if not state_file then return end
  local file = io.open(state_file, "w")
  if file then file:write(name or "") file:close() end
end

local function recall()
  if not state_file then return "" end
  local file = io.open(state_file, "r")
  if not file then return "" end
  local name = file:read("l") or ""
  file:close()
  return name
end

local previous_submap = ""

local function leave()
  if hl.get_current_submap() == viewer_submap then
    if previous_submap == "" then previous_submap = recall() end
    local back = previous_submap ~= "" and previous_submap ~= viewer_submap and previous_submap or "reset"
    previous_submap = ""
    remember("")
    hl.dispatch(hl.dsp.submap(back))
    -- The previous submap may no longer exist (a reload dropped it): never
    -- stay in the key map's submap.
    if hl.get_current_submap() == viewer_submap then hl.dispatch(hl.dsp.submap("reset")) end
  end
end

-- SUPER + K inside the submap restores the bindings itself before asking the
-- shell to close the overlay, so it works even when the shell does not answer.
hl.define_submap(viewer_submap, function()
  hl.bind("SUPER + K", function()
    leave()
    hl.exec_cmd("omarchy-shell shell hide " .. viewer_id)
  end) -- no description: it stays out of keybinding lists
end)

local function enter()
  local current = hl.get_current_submap()
  if current == viewer_submap then
    previous_submap = recall()
    return
  end
  previous_submap = (current ~= "default" and current) or ""
  remember(previous_submap)
  hl.dispatch(hl.dsp.submap(viewer_submap))
end

hl.on("layer.opened", function(layer)
  if layer.namespace == viewer_layer then enter() end
end)
hl.on("layer.closed", function(layer)
  if layer.namespace == viewer_layer then leave() end
end)

-- A config reload drops event subscriptions and may happen while the key map
-- is open (including right after its one-click setup): match the open layer.
-- Only with the real API: tools that read this config (such as Omarchy's own
-- keybindings menu) load it with a stand-in `hl` whose calls return tables.
if type(hl.get_layers) == "function" and type(hl.get_current_submap) == "function" then
  local open = false
  for _, layer in ipairs(hl.get_layers() or {}) do
    if layer.namespace == viewer_layer then open = true end
  end
  if open then enter() else leave() end
end
