#!/usr/bin/env bash
#
# install-prisma.sh — install Prisma into an app directory, correctly, every time.
#
# Replaces a hand-run `npm install prisma @prisma/client && npx prisma init`,
# which produces a broken setup in two ways this script closes:
#
#   1. Version drift. npm's `latest` dist-tag is periodically a pre-release, and
#      `prisma` and `@prisma/client` can resolve to DIFFERENT majors — an RC CLI
#      driving a stable client. That also moves the CLI surface: `prisma init
#      --datasource-provider` exists on 7.x and not on the 8.x RC. This script
#      resolves the highest STABLE version, pins both packages to it, and fails
#      if what landed on disk disagrees.
#
#   2. Config filename. Prisma 7 writes `prisma7.config.ts`, but
#      `web/Dockerfile.dev` does `COPY prisma.config.ts ./`, so the image build
#      fails on a missing file. The generated config also does
#      `import "dotenv/config"`, so dotenv must be present. This script renames
#      and installs dotenv, then proves it with `prisma validate`.
#
# Idempotent: re-running skips work already done and re-asserts every check.
#
# Usage:
#   ./install-prisma.sh [APP_DIR] [--provider postgresql] [--version x.y.z]
#
#   APP_DIR      Directory holding package.json. Default: ./web
#   --provider   Datasource provider. Default: postgresql
#   --version    Pin an exact version instead of resolving the latest stable
#
# Exits non-zero with a stated reason on any failed assertion.

set -euo pipefail

APP_DIR=""
PROVIDER="postgresql"
PIN=""

while [ $# -gt 0 ]; do
  case "$1" in
    --provider)   PROVIDER="${2:?--provider needs a value}"; shift 2 ;;
    --provider=*) PROVIDER="${1#*=}"; shift ;;
    --version)    PIN="${2:?--version needs a value}"; shift 2 ;;
    --version=*)  PIN="${1#*=}"; shift ;;
    -h|--help)    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "ERROR: unknown flag $1" >&2; exit 1 ;;
    *)  [ -z "$APP_DIR" ] && APP_DIR="$1" || { echo "ERROR: unexpected argument $1" >&2; exit 1; }; shift ;;
  esac
done

APP_DIR="${APP_DIR:-./web}"
[ -f "$APP_DIR/package.json" ] || { echo "ERROR: no package.json in $APP_DIR" >&2; exit 1; }
cd "$APP_DIR"

say() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

pkg_version() {
  node -e "try{console.log(require('./node_modules/$1/package.json').version)}catch(e){console.log('')}"
}

# Is $1 a DECLARED dependency in package.json? Deliberately not the same
# question as pkg_version: a package can sit in node_modules purely as a hoisted
# transitive dep (dotenv arrives that way under prisma), which resolves today
# and disappears the moment the parent drops it.
pkg_declared() {
  node -e '
    const p = require("./package.json");
    const name = process.argv[1];
    const has = ["dependencies", "devDependencies", "optionalDependencies"]
      .some(f => p[f] && Object.prototype.hasOwnProperty.call(p[f], name));
    console.log(has ? "yes" : "");
  ' "$1"
}

# --- 1. resolve the version to pin ------------------------------------------
# Deterministic: take the highest version with no pre-release suffix, compared
# numerically field by field. Deliberately does NOT trust the `latest`
# dist-tag, which is what puts an -rc on the machine in the first place.
if [ -n "$PIN" ]; then
  VERSION="$PIN"
  say "using pinned version $VERSION"
else
  say "resolving highest stable prisma version"
  VERSION="$(
    npm view prisma versions --json 2>/dev/null | node -e '
      let raw = "";
      process.stdin.on("data", d => raw += d);
      process.stdin.on("end", () => {
        const all = JSON.parse(raw);
        const stable = (Array.isArray(all) ? all : [all]).filter(v => !v.includes("-"));
        if (!stable.length) { process.exit(1); }
        const parse = v => v.split(".").map(Number);
        stable.sort((a, b) => {
          const [A, B] = [parse(a), parse(b)];
          for (let i = 0; i < 3; i++) if (A[i] !== B[i]) return A[i] - B[i];
          return 0;
        });
        console.log(stable[stable.length - 1]);
      });
    '
  )" || die "could not resolve a stable prisma version from the registry"
  [ -n "$VERSION" ] || die "could not resolve a stable prisma version from the registry"
  say "highest stable is $VERSION"
fi

# --- 2. install both packages at that exact version --------------------------
if [ "$(pkg_version prisma)" != "$VERSION" ] || [ "$(pkg_version @prisma/client)" != "$VERSION" ]; then
  say "installing prisma@$VERSION @prisma/client@$VERSION"
  npm install "prisma@$VERSION" "@prisma/client@$VERSION" >/dev/null
else
  say "prisma and @prisma/client already at $VERSION"
fi

CLI_V="$(pkg_version prisma)"
CLIENT_V="$(pkg_version @prisma/client)"
[ "$CLI_V" = "$VERSION" ] || die "prisma resolved to '$CLI_V', expected '$VERSION'"
[ "$CLIENT_V" = "$VERSION" ] || die "@prisma/client resolved to '$CLIENT_V', expected '$VERSION'"
say "verified prisma=$CLI_V @prisma/client=$CLIENT_V"

# --- 3. scaffold the schema (only if absent) ---------------------------------
if [ -f prisma/schema.prisma ]; then
  say "prisma/schema.prisma already exists — skipping init"
else
  # Flag support differs across majors; probe rather than assume.
  INIT_HELP="$(npx prisma init --help 2>&1 || true)"
  INIT_ARGS=()
  case "$INIT_HELP" in *--datasource-provider*) INIT_ARGS+=(--datasource-provider "$PROVIDER") ;; esac
  case "$INIT_HELP" in *--no-skills*) INIT_ARGS+=(--no-skills) ;; esac
  # bash 3.2 (macOS default) treats "${arr[@]}" on an empty array as unbound
  # under `set -u`, so both expansions need the +-guard.
  say "running prisma init ${INIT_ARGS[@]+${INIT_ARGS[*]}}"
  npx prisma init ${INIT_ARGS[@]+"${INIT_ARGS[@]}"} >/dev/null 2>&1 || true
  [ -f prisma/schema.prisma ] || die "prisma init did not produce prisma/schema.prisma"

  # If this major had no --datasource-provider flag, set the provider directly.
  if ! grep -q "provider *= *\"$PROVIDER\"" prisma/schema.prisma; then
    say "setting datasource provider to $PROVIDER in prisma/schema.prisma"
    node -e '
      const fs = require("fs");
      const p = "prisma/schema.prisma";
      const provider = process.argv[1];
      let s = fs.readFileSync(p, "utf8");
      s = s.replace(/(datasource\s+\w+\s*\{[^}]*?provider\s*=\s*)"[^"]*"/s, `$1"${provider}"`);
      fs.writeFileSync(p, s);
    ' "$PROVIDER"
  fi
fi

# --- 4. normalize the config filename ---------------------------------------
# Prisma 7 emits prisma7.config.ts (a transitional name). Dockerfile.dev copies
# prisma.config.ts. Prisma reads prisma.config.ts fine, so rename it.
if [ ! -f prisma.config.ts ]; then
  LEGACY="$(ls prisma[0-9]*.config.ts 2>/dev/null | head -1 || true)"
  if [ -n "$LEGACY" ]; then
    say "renaming $LEGACY -> prisma.config.ts (Dockerfile.dev copies that name)"
    mv "$LEGACY" prisma.config.ts
  fi
fi

# --- 5. dotenv, if the generated config imports it ---------------------------
if [ -f prisma.config.ts ] && grep -q 'dotenv' prisma.config.ts; then
  if [ -z "$(pkg_declared dotenv)" ]; then
    say "prisma.config.ts imports dotenv — adding it as a direct devDependency"
    npm install -D dotenv >/dev/null
  fi
  [ -n "$(pkg_declared dotenv)" ] || die "prisma.config.ts imports dotenv but package.json does not declare it"
fi

# --- 6. prove it ------------------------------------------------------------
# A syntactically valid URL is enough; `validate` does not connect.
say "validating"
OUT="$(DATABASE_URL='postgresql://dummy:dummy@localhost:5432/dummy' npx prisma validate 2>&1)" \
  || { echo "$OUT" >&2; die "prisma validate failed"; }
echo "$OUT" | grep -q 'schema.*is valid' || { echo "$OUT" >&2; die "prisma validate did not report a valid schema"; }
if [ -f prisma.config.ts ]; then
  echo "$OUT" | grep -q 'prisma.config.ts' \
    || { echo "$OUT" >&2; die "prisma did not load prisma.config.ts — Dockerfile.dev's COPY will not match"; }
fi

say "OK: prisma $VERSION, schema valid, config at prisma.config.ts"
