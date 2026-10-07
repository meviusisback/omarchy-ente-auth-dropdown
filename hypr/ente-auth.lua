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
-- END meviusisback.ente-auth-dropdown
