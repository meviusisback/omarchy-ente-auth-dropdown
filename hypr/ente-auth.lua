-- BEGIN meviusisback.ente-auth-dropdown (generated; do not edit)
-- Ente Auth as a dropdown overlay on its own special workspace.
-- The rule only applies at the window's first map; the toggle script below
-- just shows/hides special:ente-auth, so geometry stays as placed here.
o.window("io.ente.auth", {
  workspace = "special:ente-auth",
  float = true,
  size = { "(monitor_w*70/100)", "(monitor_h*50/100)" },
  move = { "center", "36" },
  animation = "slide top",
  border_size = 3,
  rounding = 8,
})
-- Auto-close: picking a code in Ente copies it to the Wayland clipboard, and
-- that selection change is the only signal the app exposes. The watcher below
-- turns it into "hide the dropdown, focus the previous window". It is a
-- singleton (flock in $XDG_RUNTIME_DIR/ente-auth-dropdown), so reloads cannot
-- stack duplicates,
-- and it exits by itself when wl-clipboard or the toggle script is missing.
local function ente_auth_start_watcher()
  local home = os.getenv("HOME")
  if not home or home == "" then return end
  if home:find("[\n\r]") then return end
  local bin = home .. "/.local/bin/ente-auth-dropdown"
  local file = io.open(bin, "r")
  if not file then return end
  file:close()
  -- Shell-quote: the path is concatenated into a shell command, so quote it
  -- instead of trusting it (a space in $HOME would otherwise split the
  -- command, and $/backticks in it would expand at keypress time).
  local qbin = "'" .. bin:gsub("'", "'\\''") .. "'"
  hl.exec_cmd(qbin .. " watch")
end
hl.on("hyprland.start", ente_auth_start_watcher)
hl.on("config.reloaded", ente_auth_start_watcher)
-- END meviusisback.ente-auth-dropdown
