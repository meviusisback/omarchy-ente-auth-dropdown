#!/usr/bin/env bash
# install.sh — install/uninstall the Ente Auth dropdown (host-side).
# Idempotent: marker-keyed blocks, never duplicated. Usage: ./install.sh [uninstall]
set -euo pipefail

MARKER="meviusisback.ente-auth-dropdown"
REPO_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)"
HOME_DIR="${HOME:?HOME unset}"
BIN_DST="$HOME_DIR/.local/bin/ente-auth-dropdown"
RULES_DST="$HOME_DIR/.config/hypr/ente-auth.lua"
HYPR_LUA="$HOME_DIR/.config/hypr/hyprland.lua"
BIND_LUA="$HOME_DIR/.config/hypr/bindings.lua"
BIND_BEGIN="-- BEGIN $MARKER"
BIND_END="-- END $MARKER"
BIND_LINE="o.bind(\"SUPER + E\", \"Toggle Ente Auth\", \"$BIN_DST toggle\")"
HOOK_LINE="-- Added by the $MARKER script: installs the Ente Auth dropdown window rules."
HOOK_DO="do local path = (os.getenv(\"XDG_CONFIG_HOME\") or os.getenv(\"HOME\") .. \"/.config\") .. \"/hypr/ente-auth.lua\"; local file = io.open(path, \"r\"); if file then file:close(); dofile(path) end end"
BAR_SCRIPT_SRC="$REPO_DIR/bar/ente-auth-status"
BAR_SCRIPT_DST="$HOME_DIR/.config/omarchy/bar/scripts/ente-auth-status"
SHELL_JSON="$HOME_DIR/.config/omarchy/shell.json"

msg() { printf '%s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

do_install() {
  bash -n "$REPO_DIR/ente-auth-dropdown" || die "toggle script has syntax errors"
  mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.config/hypr"
  install -m755 "$REPO_DIR/ente-auth-dropdown" "$BIN_DST"
  cmp -s "$REPO_DIR/ente-auth-dropdown" "$BIN_DST" || die "copy to $BIN_DST failed to verify"
  install -m644 "$REPO_DIR/hypr/ente-auth.lua" "$RULES_DST"
  cmp -s "$REPO_DIR/hypr/ente-auth.lua" "$RULES_DST" || die "copy to $RULES_DST failed to verify"
  if ! grep -qF -- "$HOOK_LINE" "$HYPR_LUA"; then
    printf '%s\n%s\n' "$HOOK_LINE" "$HOOK_DO" >> "$HYPR_LUA"
    msg "hook added to hyprland.lua"
  else
    msg "hook already present"
  fi
  if ! grep -qF -- "$BIND_BEGIN" "$BIND_LUA"; then
    printf '%s\n%s\n%s\n' "$BIND_BEGIN" "$BIND_LINE" "$BIND_END" >> "$BIND_LUA"
    msg "keybind added to bindings.lua"
  else
    msg "keybind already present"
  fi
  # 5. Bar icon module (absolute paths: the shell's run() must not depend on PATH).
  bash -n "$BAR_SCRIPT_SRC" || die "bar status script has syntax errors"
  mkdir -p "$HOME_DIR/.config/omarchy/bar/scripts"
  install -m755 "$BAR_SCRIPT_SRC" "$BAR_SCRIPT_DST"
  cmp -s "$BAR_SCRIPT_SRC" "$BAR_SCRIPT_DST" || die "copy to $BAR_SCRIPT_DST failed to verify"
  python3 - "$SHELL_JSON" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
lay = d["bar"]["layout"]
if not any(m.get("id") == "ente-auth" for s in lay.values() for m in s):
    lay["right"].append({"id": "ente-auth", "type": "command",
        "exec": "~/.config/omarchy/bar/scripts/ente-auth-status",
        "interval": 2, "tooltip": "Ente Auth",
        "onClick": "/home/alberto/.local/bin/ente-auth-dropdown toggle"})
    json.dump(d, open(p, "w"), indent=2)
    print("bar module added to shell.json")
else:
    print("bar module already present")
EOF
  hyprctl reload
  sleep 1
  errs="$(hyprctl configerrors 2>&1)" || true
  [ -z "$errs" ] || die "config errors after reload: $errs"
  # Harmless dispatcher probe (pitfall 27): wrong form errors now, right form is a no-op undone below.
  hyprctl dispatch 'hl.dsp.workspace.toggle_special("zzz-no-such")' >/dev/null
  hyprctl dispatch 'hl.dsp.workspace.toggle_special("zzz-no-such")' >/dev/null
  msg "Installed. Press SUPER + E for Ente Auth."
}

do_uninstall() {
  rm -f "$BIN_DST" "$RULES_DST" "$BAR_SCRIPT_DST"
  [ -f "$BIND_LUA" ] && sed -i "/$BIND_BEGIN/,/$BIND_END/d" "$BIND_LUA"
  [ -f "$HYPR_LUA" ] && sed -i "/$HOOK_LINE/d; /hypr\/ente-auth.lua/d" "$HYPR_LUA"
  python3 - "$SHELL_JSON" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
lay = d["bar"]["layout"]
for s in lay.values():
    s[:] = [m for m in s if m.get("id") != "ente-auth"]
json.dump(d, open(p, "w"), indent=2)
print("bar module removed from shell.json")
EOF
  hyprctl reload
  msg "Uninstalled."
}

case "${1:-install}" in
  install) do_install ;;
  uninstall) do_uninstall ;;
  *) die "usage: install.sh [install|uninstall]" ;;
esac
