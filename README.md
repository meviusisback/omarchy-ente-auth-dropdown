<div align="center">

# Ente Auth dropdown

**The real Ente Auth desktop app as an overlay dropdown: lock icon in the bar and `SUPER + E` toggle from anywhere.**

[![Release](https://img.shields.io/github/v/release/meviusisback/omarchy-ente-auth-dropdown)](https://github.com/meviusisback/omarchy-ente-auth-dropdown/releases)
[![License: MIT](https://img.shields.io/github/license/meviusisback/omarchy-ente-auth-dropdown)](LICENSE)
![Linux](https://img.shields.io/badge/linux-supported-1793d1)

![Ente Auth dropdown](preview.png)

</div>

## Why it exists

2FA codes are needed while you are logging in somewhere else: opening the
authenticator app breaks the flow and steals focus right when you have to
transcribe time-based digits. This plugin treats the official Ente Auth app as
a dropdown: one keypress and it appears over what you are doing; when you pick
a code it closes itself and focus returns where it was. Login, E2EE sync and
codes stay in the official app.

## What it does

- **Bar widget** (`BarWidget.qml`, plugin `meviusisback.ente-auth`): icon
  button, click = toggle, state probed every 2 s. It never touches secrets: it
  only reads `VISIBLE=0/1` and never logs raw output.
- **Dropdown on a special workspace**: the Ente Auth window lives hidden and
  appears as an overlay when you call it, from any workspace.
- **Global keybind `SUPER + E`** → `~/.local/bin/ente-auth-dropdown toggle`
  (installed by `install.sh`; no keybind default read by the code).
- **Auto-close on code pick**: when you pick a code with the Ente window
  active, the dropdown hides itself and focus returns to the previous window
  (best-effort). Requires `wl-clipboard` and having run `./install.sh` at
  least once.
- **No secrets stored**: login, E2EE sync and codes stay in the Ente app. The
  watcher reads only the byte size from the clipboard (to tell a copy apart
  from Ente's automatic clearing): the code travels through the watcher stdin
  as a count and is never saved, logged or forwarded.

## Install

```bash
omarchy plugin add https://github.com/meviusisback/omarchy-ente-auth-dropdown.git
omarchy plugin enable meviusisback.ente-auth
./install.sh
```

(Run `./install.sh` from the plugin directory,
`~/.config/omarchy/plugins/meviusisback.ente-auth`.)

`install.sh` is idempotent (marked blocks, never duplicated) and installs
copies + window rule + keybind + watcher + `shell.json` cleanup:

1. copies `ente-auth-dropdown` to `~/.local/bin/` (mode 755, verified with `cmp`)
2. copies `hypr/ente-auth.lua` to `~/.config/hypr/`
3. adds the load hook to `~/.config/hypr/hyprland.lua`
4. adds the `SUPER + E` keybind to `~/.config/hypr/bindings.lua` (the keybind
   only exists from this step on)
5. removes any legacy `id == 'ente-auth'` command-type entries from
   `shell.json` (never the plugin widget)
6. stops the previous watcher (otherwise the old code would keep running),
   `hyprctl reload` + `hyprctl configerrors` check, then starts the new
   auto-close watcher (it also starts on its own at every later reload/boot).
   A failing `hyprctl reload` (SSH/TTY, no live session) prints a warning and
   does not stop the install: in that case the window rule and keybind only
   become active at the first successful reload/login, while the watcher is
   started immediately by `install.sh` (and restarts on its own at every
   reload). A `BEGIN` marker block without `END` (or an already doubled one)
   refuses the install instead of stacking a second copy.

Then place the widget: `omarchy bar put meviusisback.ente-auth --section right`.

## Usage

- `SUPER + E` anywhere: if the app runs hidden it shows it, if visible it
  hides it, if not running it launches it.
- Click the lock in the bar: same thing.
- When you pick a code with the Ente window active, the dropdown closes
  itself and focus returns where it was. `SUPER + E` also works (or `Esc`
  with a visible list: the app itself closes it). If you have
  `special_fallthrough` enabled (set by the dropdown-terminal plugin, not this
  script), clicking outside is also enough.
- The script asks the compositor for the window list (and moves the window
  across workspaces); `status` only reports whether the special workspace is
  shown (`VISIBLE=1`), not whether the window exists.

## Requirements

- Omarchy with Hyprland 0.56+ (Lua dispatcher syntax)
- Ente Auth desktop app installed (`ente-auth` from AUR, command
  `/usr/bin/enteauth`)
- `wl-clipboard` (`wl-paste`) for auto-close: without that package the toggle
  and keybind still work, the watcher just does not start
- Nerd Font for the lock icon in the bar

## Configuration

- Keybind `SUPER + E`: lives in `~/.config/hypr/bindings.lua`, installed by
  `install.sh` (no keybind default read by the code).
- Launch command: `/usr/bin/enteauth` in the `ente-auth-dropdown` script.
- Window class: `hypr/ente-auth.lua` (default `io.ente.auth`).

## How it works

- Bar widget (`BarWidget.qml`, plugin `meviusisback.ente-auth`): icon button,
  click = toggle, state probed every 2 s. It never touches secrets: it only
  reads `VISIBLE=0/1` and never logs raw output.
- `hypr/ente-auth.lua` — window rule: the `io.ente.auth` class goes to
  `special:ente-auth`, floating, centered under the bar (70% width x 50%
  monitor height). The same file starts the auto-close watcher at Hyprland
  startup and after every `hyprctl reload`.
- `ente-auth-dropdown` — toggle script: before deciding whether the app
  already runs it verifies class `io.ente.auth` **and** executable
  (`enteauth`/`ente-auth` from a root-owned path: `/usr/`, `/opt/`,
  `/var/lib/flatpak/`, `/snap/`, not group/other-writable). That rule governs
  launch, auto-close and "bring the window to the workspace", not what the
  workspace shows: the window rule in `hypr/ente-auth.lua` moves there any
  window declaring that class (the class is self-declared by the client). If
  the app runs hidden it shows it, if visible it hides it, if not running it
  launches it (`/usr/bin/enteauth`, AUR). It uses the Hyprland 0.56 Lua
  dispatcher syntax (`hl.dsp.workspace.toggle_special`); the legacy
  `togglespecialworkspace` fails silently on this build.
- Auto-close (`ente-auth-dropdown watch`): Ente Auth copies the code to the
  Wayland clipboard when you click an entry, and that selection change is the
  only signal the app exposes. The watcher (`wl-paste --watch`) only reacts
  if the active window is really the Ente app (same rule: class + `enteauth`
  executable from a root-owned path): it hides the dropdown and focus returns
  to the previous window. Of the clipboard content it reads only the **size**
  (to tell a copy apart from Ente's automatic clearing): the code is never
  saved, logged or passed anywhere else. It is a singleton (`flock`), so
  reloads do not pile up copies.

## Removal

```bash
./install.sh uninstall
omarchy plugin disable meviusisback.ente-auth
omarchy plugin remove meviusisback.ente-auth
```

Removes script, rule, hook and keybind, stops the watcher, then
`hyprctl reload`. These remain: `hyprland.lua.bak` and `bindings.lua.bak`
backups (delete by hand if unneeded), `shell.json` edits (legacy entries stay
removed) and the watcher state directory
`$XDG_RUNTIME_DIR/ente-auth-dropdown` (lock, clipboard-event lock, pid and
previous-window: gone at session restart; if `XDG_RUNTIME_DIR` is unset the
fallback is `/tmp/ente-auth-dropdown.<uid>`, which does **not** disappear). An
install ≤ 1.1.0 may also leave the old lock
`$XDG_RUNTIME_DIR/ente-auth-dropdown.watch.lock`: no code removes it.

## License

MIT — see [LICENSE](LICENSE).
