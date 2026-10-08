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
# Legacy command-module script path: removed from the repo, deleted from disk
# by uninstall if a previous install left it behind. Never installed anymore
# (the bar icon is the plugin widget now).
BAR_SCRIPT_DST="$HOME_DIR/.config/omarchy/bar/scripts/ente-auth-status"
BIND_BEGIN="-- BEGIN $MARKER"
BIND_END="-- END $MARKER"
# Lua-escape the bind path: a quote/backslash in $HOME must not break the string.
_ESCAPED_BIN="${BIN_DST//\\/\\\\}"
_ESCAPED_BIN="${_ESCAPED_BIN//\"/\\\"}"
BIND_LINE="o.bind(\"SUPER + E\", \"Toggle Ente Auth\", \"${_ESCAPED_BIN} toggle\")"
# A newline in $HOME would break out of the generated Lua line: refuse it.
case "$BIN_DST" in
  *$'\n'*|*$'\r'*) die "HOME contains a newline: refusing to write the keybind" ;;
esac
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

# One-time migration from the pre-plugin era: strip legacy id=='ente-auth'
# command-module entries from shell.json (tolerant: a missing or unreadable
# file is not an error). Only touches type==command entries, never the plugin
# widget (different id anyway).
migrate_legacy_bar_module() {
  "$PYTHON3" - "$HOME_DIR/.config/omarchy/shell.json" <<'EOF'
import json, os, sys
p = sys.argv[1]
try:
    d = json.loads(open(p).read())
except (OSError, ValueError):
    print("legacy migration skipped: shell.json unreadable")
    raise SystemExit(0)
if not isinstance(d, dict):
    print("legacy migration skipped: unexpected shell.json shape")
    raise SystemExit(0)
bar = d.get("bar", {})
lay = bar.get("layout", {}) if isinstance(bar, dict) else {}
if not isinstance(lay, dict):
    print("legacy migration skipped: unexpected shell.json shape")
    raise SystemExit(0)
removed = False
for s in lay.values():
    if not isinstance(s, list):
        continue
    keep = [m for m in s if not (isinstance(m, dict) and m.get("id") == "ente-auth" and m.get("type") == "command")]
    if len(keep) != len(s):
        s[:] = keep
        removed = True
if removed:
    tmp = p + ".tmp"
    try:
        os.unlink(tmp)  # stale interrupt leftover; unlink never follows links
    except OSError:
        pass
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
    with os.fdopen(fd, "w") as h:
        json.dump(d, h, indent=2)
    os.replace(tmp, p)
print("legacy bar module removed:", removed)
EOF
}

do_install() {
  bash -n "$REPO_DIR/ente-auth-dropdown" || die "toggle script has syntax errors"
  # Pre-check everything first: a missing config must abort BEFORE partial writes.
  for f in "$HYPR_LUA" "$BIND_LUA"; do
    [ -f "$f" ] || die "missing config (nothing written): $f"
  done
  for f in "$BIN_DST" "$RULES_DST" "$HYPR_LUA" "$BIND_LUA"; do
    refuse_link "$f"
  done
  mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.config/hypr"
  install -m755 "$REPO_DIR/ente-auth-dropdown" "$BIN_DST"
  cmp -s "$REPO_DIR/ente-auth-dropdown" "$BIN_DST" || die "copy to $BIN_DST failed to verify"
  install -m644 "$REPO_DIR/hypr/ente-auth.lua" "$RULES_DST"
  cmp -s "$REPO_DIR/hypr/ente-auth.lua" "$RULES_DST" || die "copy to $RULES_DST failed to verify"
  # Backups before the first append (only if no .bak exists yet).
  [ -e "$HYPR_LUA.bak" ] || cp -p "$HYPR_LUA" "$HYPR_LUA.bak"
  [ -e "$BIND_LUA.bak" ] || cp -p "$BIND_LUA" "$BIND_LUA.bak"
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
  # Bar icon comes from the plugin widget (manifest bar-widget), never from a
  # shell.json command module. Strip any legacy entry left by older installs.
  migrate_legacy_bar_module
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
  for f in "$BIN_DST" "$RULES_DST" "$BAR_SCRIPT_DST"; do
    refuse_link "$f"
  done
  rm -f "$BIN_DST" "$RULES_DST" "$BAR_SCRIPT_DST"
  migrate_legacy_bar_module
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
    try:
        os.unlink(tmp)  # stale interrupt leftover; unlink never follows links
    except OSError:
        pass
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
    with os.fdopen(fd, "w") as h:
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
    try:
        os.unlink(tmp)  # stale interrupt leftover; unlink never follows links
    except OSError:
        pass
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
    with os.fdopen(fd, "w") as h:
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
  "$HYPRCTL" reload
  msg "Uninstalled."
}

case "${1:-install}" in
  install) do_install ;;
  uninstall) do_uninstall ;;
  *) die "usage: install.sh [install|uninstall]" ;;
esac
