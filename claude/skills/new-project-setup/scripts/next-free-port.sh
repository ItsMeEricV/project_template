#!/usr/bin/env bash
#
# next-free-port.sh — print the next actually-free host port(s), deterministically.
#
# "Free" means ALL THREE of:
#   1. not published by any Docker container that still exists (`docker ps -a`,
#      running OR merely stopped), and
#   2. not currently bound by any process on the host (covers non-Docker servers), and
#   3. not RESERVED on disk by another project — a port written into a
#      `.env.docker` (WEB_PORT / STUDIO_PORT) or hardcoded as a published port
#      in a compose file under the scan roots.
#
# Check 3 exists because checks 1 and 2 both go blind the moment a project is
# torn down: `docker compose down` DELETES its containers, so `docker ps -a`
# no longer lists them and nothing holds the socket. A port that a spun-down
# project will reclaim the next time it comes up is NOT free — handing it to a
# new project just moves the `bind: address already in use` failure into the
# future, onto whichever project starts second.
#
# Always returns the LOWEST qualifying port >= START. No randomness, no guessing.
#
# Usage:
#   ./next-free-port.sh [START] [COUNT] [--roots DIR[,DIR...]] [--no-scan] [-v]
#
#   --roots   Directories to scan for on-disk reservations.
#             Default: $HOME/code  (override for a different workspace layout)
#   --no-scan Skip check 3 entirely (docker + host-socket checks only)
#   -v        Explain on stderr why each candidate port was rejected
#
# Examples:
#   ./next-free-port.sh 5432             # next free port for the shared db
#   ./next-free-port.sh 3000             # next free WEB_PORT
#   ./next-free-port.sh 5555 2           # two free ports >= 5555
#   ./next-free-port.sh 3000 1 -v        # show what's holding the ports it skips
#   ./next-free-port.sh 3000 1 --roots ~/work,~/src
#
# Output: one port per line (COUNT lines) on stdout. Notes go to stderr.

set -euo pipefail

START=""
COUNT=""
ROOTS="$HOME/code"
DO_SCAN=1
VERBOSE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --roots)   ROOTS="${2:?--roots needs a value}"; shift 2 ;;
    --roots=*) ROOTS="${1#*=}"; shift ;;
    --no-scan) DO_SCAN=0; shift ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "ERROR: unknown flag $1" >&2; exit 1 ;;
    *)
      if [ -z "$START" ]; then START="$1"
      elif [ -z "$COUNT" ]; then COUNT="$1"
      else echo "ERROR: unexpected argument $1" >&2; exit 1
      fi
      shift ;;
  esac
done

START="${START:-3000}"
COUNT="${COUNT:-1}"

case "$START" in '' | *[!0-9]*) echo "ERROR: START must be a port number" >&2; exit 1 ;; esac
case "$COUNT" in '' | *[!0-9]*) echo "ERROR: COUNT must be a number" >&2; exit 1 ;; esac

note() { [ "$VERBOSE" -eq 1 ] && echo "$1" >&2 || true; }

# --- check 1: host-side ports published by containers that still exist --------
# `docker ps -a` Ports column looks like "0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp";
# we want the host port (left of "->"), never the container port. An exposed-only
# port like "3000/tcp" (no "->") isn't bound on the host, so it's correctly ignored.
#
# `grep` exits 1 when it matches nothing — the normal case on a machine with no
# containers, or none publishing ports. Under `set -o pipefail` that failure
# propagates out of the command substitution and kills the script before it
# prints anything, so the `|| true` guard is load-bearing, not defensive noise.
docker_used="$(
  { docker ps -a --format '{{.Ports}}' 2>/dev/null || true; } \
    | { grep -oE ':[0-9]+->' || true; } \
    | tr -dc '0-9\n' \
    | sort -un
)"

# --- check 3: ports reserved on disk by projects that are currently down ------
# Two sources, both authoritative for "this project intends to bind that port":
#   • .env.docker           — WEB_PORT=3000 / STUDIO_PORT=5555 (per-worktree, live values)
#   • docker-compose*.yml   — a hardcoded published port, e.g. - '5432:5432'
#
# .env.docker.example is deliberately NOT scanned: it ships template defaults
# (3000/5555) in every fork, so honoring it would reserve those ports on behalf
# of projects that never actually used them.
#
# Interpolated port mappings ('${WEB_PORT}:3000') are skipped here — their real
# value lives in that project's .env.docker, which this scan already reads.
scan_reserved() {
  [ "$DO_SCAN" -eq 0 ] && return 0
  local root files
  local IFS=,
  for root in $ROOTS; do
    root="${root/#\~/$HOME}"
    [ -d "$root" ] || continue
    files="$(
      find "$root" -maxdepth 4 \
        \( -name node_modules -o -name .git -o -name .next -o -name dist -o -name vendor \) -prune -o \
        \( -name '.env.docker' -o -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' \) -print 2>/dev/null || true
    )"
    [ -n "$files" ] || continue
    printf '%s\n' "$files" | while IFS= read -r f; do
      case "$(basename "$f")" in
        .env.docker)
          { grep -hoE '^[[:space:]]*(WEB_PORT|STUDIO_PORT)[[:space:]]*=[[:space:]]*[0-9]+' "$f" || true; } \
            | grep -oE '[0-9]+$' || true
          ;;
        *)
          # Published-port shorthand: - '8080:80' / - "8080:80" / - 8080:80
          { grep -hoE "^[[:space:]]*-[[:space:]]*['\"]?[0-9]{2,5}:[0-9]{2,5}" "$f" || true; } \
            | grep -oE '[0-9]{2,5}:' | tr -d ':' || true
          ;;
      esac
    done
  done
}

reserved=""
if [ "$DO_SCAN" -eq 1 ]; then
  reserved="$(scan_reserved | sort -un || true)"
fi

# Is $1 bound by any listening process on the host right now?
port_bound() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  elif command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$1" >/dev/null 2>&1
  else
    return 1  # can't probe; assume free (other checks still apply)
  fi
}

in_list() { printf '%s\n' "$2" | grep -qx "$1"; }

found=0
port="$START"
while [ "$found" -lt "$COUNT" ]; do
  if [ "$port" -gt 65535 ]; then
    echo "ERROR: ran past port 65535 without finding $COUNT free port(s)" >&2
    exit 1
  fi
  if in_list "$port" "$docker_used"; then
    note "skip $port: published by an existing container (docker ps -a)"
  elif port_bound "$port"; then
    note "skip $port: a process on this host is listening on it"
  elif [ -n "$reserved" ] && in_list "$port" "$reserved"; then
    note "skip $port: reserved on disk by another project (.env.docker / compose file)"
  else
    echo "$port"
    found=$((found + 1))
  fi
  port=$((port + 1))
done
