#!/usr/bin/bash
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
msg() { printf '%s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

BIND_BEGIN="-- BEGIN $MARKER"
BIND_END="-- END $MARKER"
# Shell-quote the bind command the way hypr/ente-auth.lua quotes its spawn
# path (single quotes, a ' becomes '\''), so the third o.bind argument
# survives the shell at keypress as one argv element: a space or an apostrophe
# in $HOME round-trips literally, and a ';' can no longer start a new command.
# Lua-escape that shell command for the double-quoted Lua string. $/backtick/
# CR/LF stay refused below: quoting cannot save them from keypress expansion.
_SQ_BIN="'${BIN_DST//\'/\'\\\'\'}'"
_SHELL_CMD="${_SQ_BIN} toggle"
_ESCAPED_CMD="${_SHELL_CMD//\\/\\\\}"
_ESCAPED_CMD="${_ESCAPED_CMD//\"/\\\"}"
BIND_LINE="o.bind(\"SUPER + E\", \"Toggle Ente Auth\", \"${_ESCAPED_CMD}\")"
# A newline or carriage return in $HOME would break out of the generated Lua
# line, and $/backticks would expand at keypress: refuse those. Spaces,
# apostrophes and semicolons are fine (shell-quoted above).
case "$BIN_DST" in
  *'$'*|*'`'*|$'\n'*|*$'\r'*) die "HOME contains shell-active characters: refusing to write the keybind" ;;
esac
HOOK_LINE="-- Added by the $MARKER script: installs the Ente Auth dropdown window rules."
HOOK_DO="do local path = (os.getenv(\"XDG_CONFIG_HOME\") or os.getenv(\"HOME\") .. \"/.config\") .. \"/hypr/ente-auth.lua\"; local file = io.open(path, \"r\"); if file then file:close(); dofile(path) end end"

# Absolute /usr/bin paths throughout: ~/.local/bin is first in PATH (and holds
# the python3 that runs the heredocs below), so command -v could resolve a
# planted binary. Every external used below is pinned here.
HYPRCTL=/usr/bin/hyprctl
SLEEP=/usr/bin/sleep
PYTHON3=/usr/bin/python3
TR=/usr/bin/tr
ID_BIN=/usr/bin/id
TIMEOUT_BIN=/usr/bin/timeout
HEAD_BIN=/usr/bin/head
MKDIR_BIN=/usr/bin/mkdir
INSTALL_BIN=/usr/bin/install
CMP_BIN=/usr/bin/cmp
CP_BIN=/usr/bin/cp
MV_BIN=/usr/bin/mv
GREP_BIN=/usr/bin/grep
RM_BIN=/usr/bin/rm
MKTEMP_BIN=/usr/bin/mktemp
BASH_BIN=/usr/bin/bash
for _t in "$HYPRCTL" "$SLEEP" "$PYTHON3" "$TR" "$ID_BIN" "$TIMEOUT_BIN" \
         "$HEAD_BIN" "$MKDIR_BIN" "$INSTALL_BIN" "$CMP_BIN" \
         "$CP_BIN" "$MV_BIN" "$GREP_BIN" "$RM_BIN" "$MKTEMP_BIN" "$BASH_BIN"; do
  [ -x "$_t" ] || die "missing trusted tool: $_t"
done

# Runtime state shared with the toggle script: same subdir it computes (see
# STATE_DIR there). Holds the watcher pid file, nothing else.
STATE_BASE="${XDG_RUNTIME_DIR:-/tmp/ente-auth-dropdown.$("$ID_BIN" -u)}"
STATE_DIR="$STATE_BASE/ente-auth-dropdown"
WATCH_PID="$STATE_DIR/ente-auth-dropdown.watch.pid"
# Pre-subdir location (round-1 layout): still checked on stop so an upgrade
# finds a watcher started by the old code.
LEGACY_WATCH_PID="$STATE_BASE/ente-auth-dropdown.watch.pid"

# Exact-argv process matchers (same rule as the toggle script: no substring
# matching on the joined cmdline, so an `exec -a` decoy whose argv[0] merely
# contains our path never matches). Every element is compared literally
# against this install's $BIN_DST, for the watcher shell and its wl-paste
# child alike.
_argv() {
  local -n _arr="$2"
  _arr=()
  [ -r "/proc/$1/cmdline" ] || return 1
  mapfile -d '' _arr < "/proc/$1/cmdline" 2>/dev/null || true
  [ "${#_arr[@]}" -gt 0 ] || return 1
  if [ -z "${_arr[-1]}" ]; then unset '_arr[-1]'; fi
  [ "${#_arr[@]}" -gt 0 ]
}

# 0 iff pid is this install's watcher shell: argv [<shell>, $BIN_DST, watch].
# This is also how the shell is found when the pid file is missing.
is_watcher_argv() {
  local _a=()
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  _argv "$1" _a || return 1
  [ "${#_a[@]}" -eq 3 ] || return 1
  [ "${_a[1]}" = "$2" ] && [ "${_a[2]}" = "watch" ]
}

# 0 iff pid is this install's wl-paste child: argv [wl-paste, --watch, $BIN_DST].
is_wlpaste_argv() {
  local _a=()
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  _argv "$1" _a || return 1
  [ "${#_a[@]}" -ge 4 ] || return 1
  case "${_a[0]}" in
    */wl-paste|wl-paste) ;;
    *) return 1 ;;
  esac
  [ "${_a[1]}" = "--watch" ] && [ "${_a[2]}" = "$2" ]
}

# Stop the live auto-close watcher. A pid-file pid is killed only when its
# argv still belongs to this install (a recycled pid must never take out an
# unrelated process); the whole /proc sweep below uses the same exact-argv
# rule, so a missing pid file cannot leave a watcher respawning its child.
# On success the pid file is deleted. The pid read is bounded (timeout +
# head -c 32); the argv check is the real guard.
stop_watcher() {
  local _pidfile pid
  for _pidfile in "$WATCH_PID" "$LEGACY_WATCH_PID"; do
    pid=""
    if [ -r "$_pidfile" ]; then
      pid="$("$TIMEOUT_BIN" 2 "$HEAD_BIN" -c 32 -- "$_pidfile" 2>/dev/null | "$TR" -d '\0' 2>/dev/null)" || pid=""
    fi
    case "$pid" in
      ''|*[!0-9]*) continue ;;
    esac
    if is_watcher_argv "$pid" "$BIN_DST"; then
      kill "$pid" 2>/dev/null || true
      "$RM_BIN" -f -- "$_pidfile" 2>/dev/null || true
    elif [ ! -d "/proc/$pid" ]; then
      "$RM_BIN" -f -- "$_pidfile" 2>/dev/null || true
    fi
  done
  sweep_our_watchers
  return 0
}

# Kill this install's watcher shells and wl-paste children found by exact argv
# match (no pid file needed). An `exec -a` decoy or another tool's wl-paste
# never matches: every element is compared literally against $BIN_DST.
sweep_our_watchers() {
  local _p _pid
  for _p in /proc/[0-9]*; do
    _pid="${_p#/proc/}"
    case "$_pid" in ''|*[!0-9]*) continue ;; esac
    if is_watcher_argv "$_pid" "$BIN_DST"; then
      kill "$_pid" 2>/dev/null || true
    elif is_wlpaste_argv "$_pid" "$BIN_DST"; then
      kill "$_pid" 2>/dev/null || true
    fi
  done
  return 0
}

# Refuse symlinked write targets (an append/copy through a planted link lands
# elsewhere). Checks the file and its parent dir; call BEFORE any write.
# (Uninstall never calls this: removal via rm -f replaces a link, it never
# follows one, so a symlinked target must not abort uninstall.)
refuse_link() {
  local p="$1" d
  [ ! -L "$p" ] || die "refusing to write $p: it is a symlink"
  d="${p%/*}"
  [ -n "$d" ] && [ ! -L "$d" ] || die "refusing to write into $d: it is a symlink"
}

# Back up a config once (only if no .bak exists yet) via temp file + rename:
# a dangling .bak symlink is replaced by the rename, never followed. A .bak
# that already is a symlink is refused outright (pre-check catches this before
# any write, with a clear error instead of a halfway abort).
backup_once() {
  local src="$1" tmp
  [ -e "$src.bak" ] && return 0
  [ ! -L "$src.bak" ] || die "backup path is a symlink (nothing written): $src.bak"
  tmp="$("$MKTEMP_BIN" -- "${src}.tmp.XXXXXX")" || die "cannot create temp backup for $src"
  "$CP_BIN" -p -- "$src" "$tmp" || { "$RM_BIN" -f -- "$tmp"; die "backup of $src failed (nothing written)"; }
  "$MV_BIN" -f -- "$tmp" "$src.bak" || { "$RM_BIN" -f -- "$tmp"; die "backup of $src failed (nothing written)"; }
}

# Marker appends never touch the user's last line: when the file lacks a
# trailing newline the BEGIN/HOOK line simply glues onto it, and the
# uninstaller below detaches exactly the bytes it added (a glued prefix is
# kept, no newline is ever forced in). Install + uninstall is byte-exact.

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
    try:
        mode = os.stat(p).st_mode & 0o7777  # keep the original mode, not 0644
    except OSError:
        mode = 0o644
    tmp = p + ".tmp"
    try:
        os.unlink(tmp)  # stale interrupt leftover; unlink never follows links
    except OSError:
        pass
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
    with os.fdopen(fd, "w") as h:
        json.dump(d, h, indent=2)
    os.chmod(tmp, mode)
    os.replace(tmp, p)
print("legacy bar module removed:", removed)
EOF
}

do_install() {
  local f d d2 errs
  "$BASH_BIN" -n "$REPO_DIR/ente-auth-dropdown" || die "toggle script has syntax errors"
  # Pre-check everything first: configs, write permissions, backup siblings and
  # target dirs must all be good BEFORE the first write (no partial installs).
  for f in "$HYPR_LUA" "$BIND_LUA"; do
    [ -f "$f" ] || die "missing config (nothing written): $f"
    [ -w "$f" ] || die "config not writable (nothing written): $f"
    [ ! -L "$f.bak" ] || die "backup path is a symlink (nothing written): $f.bak"
  done
  for d in "${BIN_DST%/*}" "${RULES_DST%/*}"; do
    if [ -d "$d" ]; then
      [ -w "$d" ] || die "directory not writable (nothing written): $d"
    elif [ -e "$d" ] || [ -L "$d" ]; then
      die "cannot create directory (nothing written): $d"
    else
      # Missing target dir (a fresh HOME has no ~/.local yet): walk UP to the
      # nearest existing ancestor and test writability there, guarded against
      # / so the loop always terminates. Nothing is written before every
      # pre-check passes.
      d2="$d"
      while [ ! -e "$d2" ]; do
        case "$d2" in
          */*) d2="${d2%/*}" ;;
          *) d2="/" ;;
        esac
        [ -n "$d2" ] || d2="/"
        [ "$d2" != "/" ] || break
      done
      [ -w "$d2" ] || die "parent directory not writable (nothing written): $d"
    fi
  done
  for f in "$BIN_DST" "$RULES_DST" "$HYPR_LUA" "$BIND_LUA"; do
    refuse_link "$f"
  done
  "$MKDIR_BIN" -p "$HOME_DIR/.local/bin" "$HOME_DIR/.config/hypr"
  "$INSTALL_BIN" -m755 "$REPO_DIR/ente-auth-dropdown" "$BIN_DST"
  "$CMP_BIN" -s "$REPO_DIR/ente-auth-dropdown" "$BIN_DST" || die "copy to $BIN_DST failed to verify"
  "$INSTALL_BIN" -m644 "$REPO_DIR/hypr/ente-auth.lua" "$RULES_DST"
  "$CMP_BIN" -s "$REPO_DIR/hypr/ente-auth.lua" "$RULES_DST" || die "copy to $RULES_DST failed to verify"
  # Backups before the first append (only if no .bak exists yet).
  backup_once "$HYPR_LUA"
  backup_once "$BIND_LUA"
  if ! "$GREP_BIN" -qF -- "$HOOK_LINE" "$HYPR_LUA"; then
    printf '%s\n%s\n' "$HOOK_LINE" "$HOOK_DO" >> "$HYPR_LUA"
    msg "hook added to hyprland.lua"
  else
    msg "hook already present"
  fi
  if ! "$GREP_BIN" -qF -- "$BIND_BEGIN" "$BIND_LUA"; then
    printf '%s\n%s\n%s\n' "$BIND_BEGIN" "$BIND_LINE" "$BIND_END" >> "$BIND_LUA"
    msg "keybind added to bindings.lua"
  else
    msg "keybind already present"
  fi
  # Bar icon comes from the plugin widget (manifest bar-widget), never from a
  # shell.json command module. Strip any legacy entry left by older installs.
  migrate_legacy_bar_module
  # Stop the previous watcher BEFORE reload and before starting the new one:
  # otherwise the old process keeps running with the old code (its flock makes
  # the new start a no-op). Small bounded wait so the TERM has landed, then
  # reload (the lua hook starts the new watcher on config load) and start it
  # here too for the same reason as before.
  stop_watcher
  "$SLEEP" 2
  "$HYPRCTL" reload
  "$SLEEP" 1
  # Auto-close watcher: hypr/ente-auth.lua starts it on config load, and we
  # spawn it here too so the feature is live right after an upgrade instead of
  # at the next login. The script's flock makes the second start a no-op.
  if [ -x "$BIN_DST" ]; then
    "$BIN_DST" watch >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
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
  # Kill the watcher BEFORE the script disappears: it loops on its own path.
  # No refuse_link here: removal never follows links, so a symlinked target
  # (stow/chezmoi users) must not abort uninstall and remove nothing.
  stop_watcher
  "$RM_BIN" -f "$BIN_DST" "$RULES_DST" "$BAR_SCRIPT_DST"
  migrate_legacy_bar_module
  # Exact-line removal only (no sed regex ranges): drop exactly the lines we
  # added, via temp file + rename so a planted symlink is replaced, not followed.
  "$PYTHON3" - "$BIND_LUA" "$HYPR_LUA" <<'EOF'
import os, sys
bind_path, hook_path = sys.argv[1], sys.argv[2]
def mode_of(path):
    # Preserve the original mode (a rewrite must not force 0644).
    try:
        return os.stat(path).st_mode & 0o7777
    except OSError:
        return 0o644
def atomic_lines(path, kept):
    mode = mode_of(path)
    tmp = path + ".tmp"
    try:
        os.unlink(tmp)  # stale interrupt leftover; unlink never follows links
    except OSError:
        pass
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
    with os.fdopen(fd, "w") as h:
        h.writelines(kept)
    os.chmod(tmp, mode)
    os.replace(tmp, path)
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
        # A BEGIN glued onto the user's last line (file had no trailing
        # newline at install time): keep the glued prefix byte-for-byte, with
        # no newline forced in, and drop from the marker on. Install appends
        # without touching the last line, so uninstall detaches exactly the
        # bytes it added: install + uninstall is byte-exact (cmp clean).
        if not skip and s != BEGIN and BEGIN in s and s.endswith(BEGIN):
            prefix = s[:len(s) - len(BEGIN)]
            out.append(prefix)
            skip, changed = True, True
            continue
        if skip and s == END:
            skip = False
            continue
        # Tolerate an END glued onto following content the same way.
        if skip and s != END and s.startswith(END):
            rest = s[len(END):]
            if rest:
                out.append(rest + "\n")
            skip = False
            continue
        if not skip:
            out.append(ln)
    if skip:
        raise SystemExit(f"unterminated marker block in {path}; leaving it alone")
    if not changed:
        return False
    atomic_lines(path, out)
    return True
hook_exact = {
    "-- Added by the meviusisback.ente-auth-dropdown script: installs the Ente Auth dropdown window rules.",
    "do local path = (os.getenv(\"XDG_CONFIG_HOME\") or os.getenv(\"HOME\") .. \"/.config\") .. \"/hypr/ente-auth.lua\"; local file = io.open(path, \"r\"); if file then file:close(); dofile(path) end end",
}
def drop_hook_lines(path):
    # Drop exactly the hook lines install appended, tolerating a first hook
    # line glued onto the user's last line (kept byte-for-byte, no newline
    # forced in). Anything else is kept verbatim.
    try:
        with open(path) as h:
            lines = h.readlines()
    except FileNotFoundError:
        return False
    out, changed = [], False
    for ln in lines:
        s = ln.rstrip("\n")
        if s in hook_exact:
            changed = True
            continue
        glued = False
        for hx in hook_exact:
            if s != hx and s.endswith(hx):
                out.append(s[:len(s) - len(hx)])
                changed, glued = True, True
                break
        if not glued:
            out.append(ln)
    if not changed:
        return False
    atomic_lines(path, out)
    return True
print("keybind block removed:", drop_block(bind_path))
print("hook lines removed:", drop_hook_lines(hook_path))
EOF
  "$HYPRCTL" reload
  msg "Uninstalled."
}

case "${1:-install}" in
  install) do_install ;;
  uninstall) do_uninstall ;;
  *) die "usage: install.sh [install|uninstall]" ;;
esac
