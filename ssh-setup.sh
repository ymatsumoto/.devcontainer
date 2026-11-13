#!/usr/bin/env bash
# Lets you `ssh <alias>` into a workspace's container, for herdr --remote and
# herdr machine add. The ProxyCommand runs `sshd -i` in the container through
# `podman exec -i`, so nothing listens and no daemon runs.
#
#   ssh-setup.sh [alias]                  on the host whose podman runs this
#                                         workspace's container (WSL, a lab node)
#   ssh-setup.sh --via HOST WS [alias]    from your machine, for the container of
#                                         workspace WS on HOST (reached by `ssh HOST`);
#                                         WS needs this script in its .devcontainer/
#   ssh-setup.sh --proxy                  the ProxyCommand itself; not by hand
#
# alias defaults to dc-<workspace name>. Safe to run again: each step only adds
# what is missing, and a Host block this script wrote earlier is rewritten.
# gie containers do not need this; `gie start` prints their block.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
alias_for() { echo "dc-$(basename "$1" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9_.\n-' '-')"; }

# The state directory that init.sh keeps for the workspace whose .devcontainer is
# $1, found by its ID. Its .workspace-path is the path init.sh ran under (the
# host's own path, since initializeCommand runs on the host).
find_state() {
    local id d
    id=$(cat "$1/.workspace-id" 2>/dev/null) || return 1
    for d in "$HOME/.devcontainer-state"/*/; do
        [ "$(cat "$d.workspace-id" 2>/dev/null)" = "$id" ] && { echo "${d%/}"; return 0; }
    done
    return 1
}

# The workspace's container, by its devcontainer.local_folder label: looked up at
# every connection, because a rebuild changes its name and id. VS Code on Windows
# records a WSL folder as \\wsl.localhost\<distro>\home\... (or \\wsl$\...), not
# as the Linux path init.sh saw, so that form is turned back into a path.
container() {
    local id lf p distro
    while IFS=$'\t' read -r id lf; do
        p=$lf
        case $p in
            '\\wsl.localhost\'* | '\\wsl$\'*)
                p=${p#\\\\*\\}                 # drop \\wsl.localhost\ (or \\wsl$\)
                distro=${p%%\\*}
                [ -z "${WSL_DISTRO_NAME:-}" ] || [ "$distro" = "$WSL_DISTRO_NAME" ] || continue
                p=${p#*\\}
                p=/${p//\\//} ;;
        esac
        [ "$p" = "$WS" ] && { echo "$id"; return; }
    done < <("$ENGINE" ps --format '{{.ID}}'$'\t''{{index .Labels "devcontainer.local_folder"}}')
}

engine() { command -v podman || command -v docker || die "neither podman nor docker is on PATH"; }

# --- --proxy: the ProxyCommand ---------------------------------------------------
if [ "${1:-}" = --proxy ]; then
    # stdout is the SSH stream from here on: nothing else may be written to it.
    DC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    STATE=$(find_state "$DC") || die "no state for $DC; open the workspace in its container first"
    WS=$(cat "$STATE/.workspace-path")
    ENGINE=$(engine)
    c=$(container)
    [ -n "$c" ] || die "no running container for $WS on $(hostname) (start it, or check: $ENGINE ps)"
    exec "$ENGINE" exec -i "$c" /usr/sbin/sshd -i
fi

# --- Gather what the three steps below need --------------------------------------
#   ALIAS, MARK, PROXY       the Host block
#   HOSTKEY                  the container's host key (may be empty: not rebuilt yet)
#   add_key FILE             puts the public key FILE into the container's authorized_keys
PUB=
for k in ~/.ssh/id_ed25519.pub ~/.ssh/id_ecdsa.pub ~/.ssh/id_rsa.pub; do
    [ -s "$k" ] && { PUB=$k; break; }
done
[ -n "$PUB" ] || die "no public key in ~/.ssh; make one with: ssh-keygen -t ed25519"

if [ "${1:-}" = --via ]; then
    [ $# -ge 3 ] || die "usage: $0 --via HOST WS [alias]"
    HOST=$2 WS=${3%/}
    case $WS in /*) ;; *) die "WS must be an absolute path on $HOST: $WS" ;; esac
    ALIAS=${4:-$(alias_for "$WS")}
    # One round trip: the state directory and host key over there, and whether
    # the script is there to serve as the ProxyCommand.
    info=$(ssh -o BatchMode=yes "$HOST" bash -s -- "$WS" <<'EOS'
ws=$1 dc=$1/.devcontainer
[ -f "$dc/ssh-setup.sh" ] || { echo "error=no $dc/ssh-setup.sh; git pull in $dc"; exit 0; }
id=$(cat "$dc/.workspace-id" 2>/dev/null) || { echo "error=no $dc/.workspace-id; open the workspace in its container first"; exit 0; }
for d in "$HOME/.devcontainer-state"/*/; do
    if [ "$(cat "$d.workspace-id" 2>/dev/null)" = "$id" ]; then
        echo "state=${d%/}"
        [ -s "$d/sshd/ssh_host_ed25519_key.pub" ] && echo "hostkey=$(cut -d' ' -f1,2 "$d/sshd/ssh_host_ed25519_key.pub")"
        exit 0
    fi
done
echo "error=no state for $ws under $HOME/.devcontainer-state; open the workspace in its container first"
EOS
) || die "ssh $HOST failed"
    err=$(sed -n 's/^error=//p' <<<"$info")
    [ -z "$err" ] || die "$HOST: $err"
    STATE=$(sed -n 's/^state=//p' <<<"$info")
    HOSTKEY=$(sed -n 's/^hostkey=//p' <<<"$info")
    MARK="# $HOST:$WS (.devcontainer/ssh-setup.sh)"
    PROXY="ssh $HOST bash \"$WS/.devcontainer/ssh-setup.sh\" --proxy"
    WHERE="$HOST:$STATE/ssh/authorized_keys"
    add_key() {
        ssh -o BatchMode=yes "$HOST" bash -s -- "$STATE/ssh/authorized_keys" <<EOS
ak=\$1 key='$(cat "$1")'
if grep -qxF "\$key" "\$ak" 2>/dev/null; then
    echo there
else
    # End an unterminated last line first, or the key would join it
    [ ! -s "\$ak" ] || [ -z "\$(tail -c1 "\$ak")" ] || echo >> "\$ak"
    echo "\$key" >> "\$ak"
    echo added
fi
chmod 600 "\$ak"
EOS
    }
    ENGINE=
else
    DC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    STATE=$(find_state "$DC") || die "no state for $DC; open the workspace in its container first"
    WS=$(cat "$STATE/.workspace-path")
    ALIAS=${1:-$(alias_for "$WS")}
    HOSTKEY=
    [ -s "$STATE/sshd/ssh_host_ed25519_key.pub" ] && HOSTKEY=$(cut -d' ' -f1,2 "$STATE/sshd/ssh_host_ed25519_key.pub")
    MARK="# $WS (.devcontainer/ssh-setup.sh)"
    PROXY="bash \"$DC/ssh-setup.sh\" --proxy"
    WHERE="$STATE/ssh/authorized_keys"
    add_key() {
        local ak=$STATE/ssh/authorized_keys
        if grep -qxF "$(cat "$1")" "$ak" 2>/dev/null; then
            echo there
        else
            # End an unterminated last line first, or the key would join it
            [ ! -s "$ak" ] || [ -z "$(tail -c1 "$ak")" ] || echo >> "$ak"
            cat "$1" >> "$ak"
            echo added
        fi
        chmod 600 "$ak"
    }
    ENGINE=$(engine)
fi

# 1. Your public key in the container's authorized_keys (<state>/ssh)
case $(add_key "$PUB") in
    there) echo "authorized_keys: $PUB already in $WHERE" ;;
    added) echo "authorized_keys: added $PUB to $WHERE" ;;
    *) die "could not update $WHERE" ;;
esac

# 2. The container's host key under the alias, so the first connection needs no
#    prompt. postCreateCommand makes it; a container from before 24f9e96 has none.
mkdir -p ~/.ssh && chmod 700 ~/.ssh
if [ -z "$HOSTKEY" ]; then
    echo "known_hosts: the container has no host key yet; rebuild it, then run this again"
elif grep -q "^$ALIAS " ~/.ssh/known_hosts 2>/dev/null; then
    echo "known_hosts: $ALIAS already there"
else
    echo "$ALIAS $HOSTKEY" >> ~/.ssh/known_hosts
    echo "known_hosts: added $ALIAS"
fi

# 3. The Host block. One this script wrote (after its marker line) is replaced,
#    so a fix here reaches it; any other Host block of that name is left alone.
CONF=~/.ssh/config
touch "$CONF"
if grep -qxF "$MARK" "$CONF"; then
    cp -p "$CONF" "$CONF.bak.ssh-setup"
    awk -v m="$MARK" '
        $0 == m { skip = 1; host = 0; next }
        skip && !host && /^Host[ \t]/ { host = 1; next }
        skip && /^[ \t]+[^ \t]/ { next }
        skip && /^[ \t]*$/ { skip = 0; next }     # and the blank line after it
        { skip = 0; print }' "$CONF.bak.ssh-setup" > "$CONF"
    echo "ssh config: replacing the block this script wrote (old file: $CONF.bak.ssh-setup)"
fi
if grep -qiE "^[[:space:]]*Host[[:space:]=]+$ALIAS([[:space:]]|$)" "$CONF"; then
    echo "ssh config: Host $ALIAS already there and not ours (left as it is)"
else
    # In front of the first Host/Match block: ssh takes the first value it finds,
    # so a `Host *` with its own User further up would otherwise win. The global
    # lines above that point stay global.
    BLOCK="$MARK
Host $ALIAS
  User root
  HostKeyAlias $ALIAS
  ProxyCommand $PROXY"
    cp -p "$CONF" "$CONF.tmp.ssh-setup"
    BLOCK=$BLOCK awk '
        !done && tolower($0) ~ /^[ \t]*(host|match)[ \t=]/ { print ENVIRON["BLOCK"]; print ""; done = 1 }
        { print }
        END { if (!done) { if (NR) print ""; print ENVIRON["BLOCK"] } }' \
        "$CONF.tmp.ssh-setup" > "$CONF"
    rm -f "$CONF.tmp.ssh-setup"
    echo "ssh config: added Host $ALIAS"
fi
chmod 600 "$CONF"
# What ssh will actually use: a Match block, or an Include read earlier, can
# still override the User.
U=$(ssh -G "$ALIAS" 2>/dev/null | awk '$1 == "user" { print $2 }')
[ "$U" = root ] || echo "WARNING: ssh would log in to $ALIAS as '$U', not root; an earlier line in $CONF (or an Include) sets User"

# 4. Try it. Locally only when the container is up (a clearer message than the
#    proxy's); through --via, the proxy itself says so.
if [ -n "$ENGINE" ] && [ -z "$(container)" ]; then
    echo "the container for $WS is not running; start it, then: ssh $ALIAS true"
elif ssh -o BatchMode=yes "$ALIAS" true; then
    echo "ok: ssh $ALIAS works. Attach with: herdr machine add $ALIAS --label <name>"
else
    die "ssh $ALIAS failed (is the container running, and rebuilt with openssh-server?)"
fi
