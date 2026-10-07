#!/usr/bin/env bash
# install.sh — install/uninstall the Ente Auth dropdown (host-side).
# Idempotent: marker-keyed blocks, never duplicated. Usage: ./install.sh [uninstall]
#
# Write discipline (review findings): refuse symlinked targets, pre-check every
# file before the first write (no partial installs), backups + atomic renames
# for JSON, exact-line removal on uninstall (no sed regex ranges).
set -euo pipefail

MARKER="meviusisback.ente-auth-dropdown"
REPO_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)"
HOME_DIR="${HOME:?HOME unset}"
BIN_DST="$HOME_DIR/.local/bin/ente-auth-dropdown"
RULES_DST="$HOME_DIR/.config/hypr/ente-auth.lua"
HYPR_LUA="$HOME_DIR/.config/hypr/hyprland.lua"
BIND_LUA="$HOME_DIR/.config/hypr/bindings.lua"
EXEC_ABS="$HOME_DIR/.config/omarchy/bar/scripts/ente-auth-status"
BAR_SCRIPT_SRC="$REPO_DIR/bar/ente-auth-status"
BAR_SCRIPT_DST="$EXEC_ABS"
SHELL_JSON="$HOME_DIR/.config/omarchy/shell.json"
BIND_BEGIN="-- BEGIN $MARKER"
BIND_END="-- END $MARKER"
# Lua-escape the bind path: a quote/backslash in $HOME must not break the string.
_ESCAPED_BIN="${BIN_DST//\\/\\\\}"
_ESCAPED_BIN="${_ESCAPED_BIN//\"/\\\"}"
BIND_LINE="o.bind(\"SUPER + E\", \"Toggle Ente Auth\", \"${_ESCAPED_BIN} toggle\")"
HOOK_LINE="-- Added by the $MARKER script: installs the Ente Auth dropdown window rules."
HOOK_DO="do local path = (os.getenv(\"XDG_CONFIG_HOME\") or os.getenv(\"HOME\") .. \"/.config\") .. \"/hypr/ente-auth.lua\"; local file = io.open(path, \"r\"); if file then file:close(); dofile(path) end end"

msg() { printf '%s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

HYPRCTL="$(command -v hyprctl)" || die "hyprctl not found"
SLEEP="$(command -v sleep)" || die "sleep not found"
PYTHON3="$(command -v python3)" || die "python3 not found"

# Refuse symlinked write targets (an append/copy through a planted link lands
# elsewhere). Checks the file and its parent dir; call BEFORE any write.
refuse_link() {
  local p="$1" d
  [ ! -L "$p" ] || die "refusing to write $p: it is a symlink"
  d="$(dirname "$p")"
  [ ! -L "$d" ] || die "refusing to write into $d: it is a symlink"
}

do_install() {
  bash -n "$REPO_DIR/ente-auth-dropdown" || die "toggle script has syntax errors"
  bash -n "$BAR_SCRIPT_SRC" || die "bar status script has syntax errors"
  # Pre-check everything first: a missing config must abort BEFORE partial writes.
  for f in "$HYPR_LUA" "$BIND_LUA" "$SHELL_JSON"; do
    [ -f "$f" ] || die "missing config (nothing written): $f"
  done
  for f in "$BIN_DST" "$RULES_DST" "$HYPR_LUA" "$BIND_LUA" "$BAR_SCRIPT_DST" "$SHELL_JSON"; do
    refuse_link "$f"
  done
  mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.config/hypr" "$HOME_DIR/.config/omarchy/bar/scripts"
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
  install -m755 "$BAR_SCRIPT_SRC" "$BAR_SCRIPT_DST"
  cmp -s "$BAR_SCRIPT_SRC" "$BAR_SCRIPT_DST" || die "copy to $BAR_SCRIPT_DST failed to verify"
  # Bar module: validate, backup, atomic write; upsert exec/onClick every run so
  # older installs converge to absolute paths instead of carrying stale values.
  "$PYTHON3" - "$SHELL_JSON" "$BIN_DST" "$EXEC_ABS" <<'EOF'
import json, os, sys
p, cli, exe = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.loads(open(p).read())
lay = d.get("bar", {}).get("layout", {})
right = lay.get("right")
if not isinstance(right, list):
    raise SystemExit("shell.json has no bar.layout.right list; refusing to edit")
entry = {"id": "ente-auth", "type": "command", "exec": exe,
         "interval": 2, "tooltip": "Ente Auth", "onClick": cli + " toggle"}
for i, m in enumerate(right):
    if isinstance(m, dict) and m.get("id") == "ente-auth":
        right[i] = entry
        break
else:
    right.append(entry)
bak = p + ".bak"
if not os.path.exists(bak):
    with open(bak, "w") as h:
        h.write(json.dumps(json.loads(open(p).read()), indent=2))
tmp = p + ".tmp"
with open(tmp, "w") as h:
    json.dump(d, h, indent=2)
os.replace(tmp, p)
print("bar module installed in shell.json (backup: shell.json.bak)")
EOF
  "$HYPRCTL" reload
  "$SLEEP" 1
  errs="$("$HYPRCTL" configerrors 2>&1)" || true
  [ -z "$errs" ] || msg "warning: hyprctl configerrors reports: $errs"
  # Harmless dispatcher probe: wrong form must error NOW (exit code checked),
  # right form is a no-op toggled straight back. Warning only: on hosts without
  # a live Hyprland (SSH, TTY) the probe cannot run, and that must not abort an
  # otherwise good install.
  "$HYPRCTL" dispatch 'hl.dsp.workspace.toggle_special("zzz-no-such")' >/dev/null \
    || msg "warning: dispatcher probe failed (Hyprland unreachable or non-Lua build?)"
  "$HYPRCTL" dispatch 'hl.dsp.workspace.toggle_special("zzz-no-such")' >/dev/null \
    || msg "warning: dispatcher probe failed on toggle-back"
  msg "Installed. Press SUPER + E for Ente Auth."
}

do_uninstall() {
  rm -f "$BIN_DST" "$RULES_DST" "$BAR_SCRIPT_DST"
  # Exact-line removal only (no sed regex ranges): drop exactly the lines we
  # added, via temp file + rename so a planted symlink is replaced, not followed.
  "$PYTHON3" - "$BIND_LUA" "$HYPR_LUA" <<'EOF'
import os, sys
bind_path, hook_path = sys.argv[1], sys.argv[2]
def rewrite(path, keep):
    try:
        with open(path) as h:
            lines = h.readlines()
    except FileNotFoundError:
        return False
    kept = [ln for ln in lines if keep(ln)]
    if len(kept) == len(lines):
        return False
    tmp = path + ".tmp"
    with open(tmp, "w") as h:
        h.writelines(kept)
    os.replace(tmp, path)
    return True
BEGIN = "-- BEGIN meviusisback.ente-auth-dropdown"
END = "-- END meviusisback.ente-auth-dropdown"
def drop_block(path):
    try:
        with open(path) as h:
            lines = h.readlines()
    except FileNotFoundError:
        return False
    out, skip, changed = [], False, False
    for ln in lines:
        s = ln.rstrip("\n")
        if not skip and s == BEGIN:
            skip, changed = True, True
            continue
        if skip and s == END:
            skip = False
            continue
        if not skip:
            out.append(ln)
    if skip:
        raise SystemExit(f"unterminated marker block in {path}; leaving it alone")
    if not changed:
        return False
    tmp = path + ".tmp"
    with open(tmp, "w") as h:
        h.writelines(out)
    os.replace(tmp, path)
    return True
hook_exact = {
    "-- Added by the meviusisback.ente-auth-dropdown script: installs the Ente Auth dropdown window rules.",
    "do local path = (os.getenv(\"XDG_CONFIG_HOME\") or os.getenv(\"HOME\") .. \"/.config\") .. \"/hypr/ente-auth.lua\"; local file = io.open(path, \"r\"); if file then file:close(); dofile(path) end end",
}
print("keybind block removed:", drop_block(bind_path))
print("hook lines removed:", rewrite(hook_path, lambda ln: ln.rstrip("\n") not in hook_exact))
EOF
  "$PYTHON3" - "$SHELL_JSON" <<'EOF'
import json, os, sys
p = sys.argv[1]
try:
    d = json.loads(open(p).read())
except (OSError, ValueError) as exc:
    print(f"shell.json unreadable, skipping: {exc}")
    raise SystemExit
lay = d.get("bar", {}).get("layout", {})
changed = False
for s in lay.values():
    before = len(s)
    s[:] = [m for m in s if not (isinstance(m, dict) and m.get("id") == "ente-auth")]
    changed = changed or len(s) != before
if changed:
    tmp = p + ".tmp"
    with open(tmp, "w") as h:
        json.dump(d, h, indent=2)
    os.replace(tmp, p)
print("bar module removed:", changed)
EOF
  "$HYPRCTL" reload
  msg "Uninstalled."
}

case "${1:-install}" in
  install) do_install ;;
  uninstall) do_uninstall ;;
  *) die "usage: install.sh [install|uninstall]" ;;
esac
