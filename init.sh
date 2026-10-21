#!/usr/bin/env bash
# Run on the host by initializeCommand every time the container is opened.
#   usage: init.sh <workspace> <root>
#   <root> = ${localEnv:HOME}/.devcontainer-state
# Must be idempotent. When the state layout changes, add the migration here.
set -euo pipefail

WS=$1
ROOT=$2
ITEMS=(claude claude.json ssh gh gemini gitconfig bash_history)

if [ "$ROOT" = /.devcontainer-state ]; then
    echo "ERROR: HOME is empty." >&2; exit 1
fi

# --- Workspace ID --------------------------------------------------------------
# The state directory is chosen by an ID stored in the workspace. devcontainer.json
# cannot read files, so mounts go through a symlink keyed by the workspace path
# (<root>/.by-path<ws>). The ID travels with the workspace, so a moved workspace or
# a different mount point on another node still reaches the same state.
IDF="$WS/.devcontainer/.workspace-id"
new_id() {
    local t
    t=$(mktemp "$IDF.XXXXXX") && cat /proc/sys/kernel/random/uuid > "$t" && chmod 644 "$t" && mv -f "$t" "$IDF"
}
if [ ! -s "$IDF" ]; then
    new_id 2>/dev/null || true
fi
if [ ! -s "$IDF" ]; then
    echo "ERROR: cannot create $IDF. Someone who can write to .devcontainer/ must open it first." >&2
    exit 1
fi

mkdir -p "$ROOT"
chmod 700 "$ROOT"

find_state() {
    local d
    for d in "$ROOT"/*/; do
        [ "$(cat "$d.workspace-id" 2>/dev/null)" = "$1" ] && { echo "${d%/}"; return; }
    done
    return 0
}

ID=$(cat "$IDF")
S=$(find_state "$ID")

# Copying a workspace with its .workspace-id duplicates the ID. If the recorded
# original path still holds the same ID in a different file, treat this as a copy
# and give it a new ID.
if [ -n "$S" ]; then
    P=$(cat "$S/.workspace-path" 2>/dev/null || true)
    if [ -n "$P" ] && [ "$P" != "$WS" ] && [ -s "$P/.devcontainer/.workspace-id" ] && \
       [ "$(cat "$P/.devcontainer/.workspace-id")" = "$ID" ] && \
       ! [ "$P/.devcontainer/.workspace-id" -ef "$IDF" ]; then
        if ! new_id; then
            echo "ERROR: $WS is a copy of $P, but $IDF cannot be replaced." >&2
            exit 1
        fi
        echo "$WS is a copy of $P; assigned a new workspace ID."
        ID=$(cat "$IDF")
        S=
    fi
fi

if [ -z "$S" ]; then
    S="$ROOT/$(basename "$WS")-${ID:0:8}"
    mkdir -p "$S"
    echo "$ID" > "$S/.workspace-id"
fi
chmod 700 "$S"
echo "$WS" > "$S/.workspace-path"

LINK="$ROOT/.by-path$WS"
if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
    echo "ERROR: $LINK is not a symlink." >&2; exit 1
fi
mkdir -p "$(dirname "$LINK")"
ln -sfn "$S" "$LINK"

# --- Migration: <ws>/.container-home/ (single user) -> <state>/ ----------------
# Copy only what this user owns and leave the old paths in place, so containers
# built from the old definition keep working until rebuilt. Copy rather than mv:
# the workspace and the home may be different NFS exports.
# (State in <root>/<workspace name>/ from the previous version carries its ID,
# so find_state already picks it up.)
OLD="$WS/.container-home"
for i in "${ITEMS[@]}"; do
    [ -e "$OLD/$i" ] && [ -O "$OLD/$i" ] && [ ! -e "$S/$i" ] || continue
    cp -a "$OLD/$i" "$S/$i"
    echo "migrated: $OLD/$i -> $S/$i"
done

# --- Current layout ------------------------------------------------------------
mkdir -p "$S/claude" "$S/ssh" "$S/gh" "$S/gemini"
touch "$S/gitconfig" "$S/bash_history"
[ -s "$S/claude.json" ] || echo '{}' > "$S/claude.json"
# The container runs with umask 002; strip group bits so ssh accepts ~/.ssh
chmod -R go-rwx "$S/ssh"
