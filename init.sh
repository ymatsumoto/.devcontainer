#!/usr/bin/env bash
# devcontainer の initializeCommand から、ホスト側でコンテナを開くたびに実行される。
#   usage: init.sh <workspace> <state>
#   <state> = ${localEnv:HOME}/.devcontainer-state/${localWorkspaceFolderBasename}
# 冪等であること。状態のレイアウトを変えるときは、ここに旧レイアウトからの移行処理を足す。
set -euo pipefail

WS=$1
S=$2
ITEMS=(claude claude.json ssh gh gemini gitconfig bash_history)

case $S in
    /.devcontainer-state/*) echo "ERROR: HOME が空です。" >&2; exit 1 ;;
esac

# --- ワークスペース ID ---------------------------------------------------------
# 状態ディレクトリはワークスペースのディレクトリ名で決まるので、同名の別ワークスペースと
# 取り違えないよう、ワークスペース側の ID と状態側の ID を突き合わせる。
# ノードごとに NFS のマウント先が違っても、ID はワークスペースと一緒に見えるので一致する。
IDF="$WS/.devcontainer/.workspace-id"
if [ ! -s "$IDF" ]; then
    (set -C; cat /proc/sys/kernel/random/uuid > "$IDF") 2>/dev/null || true
    chmod 644 "$IDF" 2>/dev/null || true
fi
if [ ! -s "$IDF" ]; then
    echo "ERROR: $IDF を作れません。.devcontainer/ に書き込める人が一度開いてください。" >&2
    exit 1
fi
ID=$(cat "$IDF")

mkdir -p "$S"
chmod 700 "$(dirname "$S")" "$S"
if [ -s "$S/.workspace-id" ] && [ "$(cat "$S/.workspace-id")" != "$ID" ]; then
    echo "ERROR: $S は別のワークスペース（$(cat "$S/.workspace-path" 2>/dev/null || echo 不明)）の状態です。" >&2
    echo "  同名のワークスペースを別々に使っているなら、どちらかのディレクトリ名を変えてください。" >&2
    echo "  同じワークスペースの $IDF を作り直してしまったなら、$S/.workspace-id の内容に戻してください。" >&2
    exit 1
fi
echo "$ID" > "$S/.workspace-id"
echo "$WS" > "$S/.workspace-path"

# --- 移行: 旧レイアウト（<ws>/.container-home/ に 1 人分）→ <state>/ ------------------
# 自分が所有する分だけをコピーする。旧パスはそのまま残すので、旧版の定義で起動済みの
# コンテナも Rebuild するまで動く。ワークスペースとホームは別の NFS でありうるので mv しない。
OLD="$WS/.container-home"
for i in "${ITEMS[@]}"; do
    [ -e "$OLD/$i" ] && [ -O "$OLD/$i" ] && [ ! -e "$S/$i" ] || continue
    cp -a "$OLD/$i" "$S/$i"
    echo "migrated: $OLD/$i -> $S/$i"
done

# --- 現行レイアウト ----------------------------------------------------------
mkdir -p "$S/claude" "$S/ssh" "$S/gh" "$S/gemini"
touch "$S/gitconfig" "$S/bash_history"
[ -s "$S/claude.json" ] || echo '{}' > "$S/claude.json"
# コンテナは umask 002 で動くので、ssh が拒否しないよう ~/.ssh からグループの権限を落とす
chmod -R go-rwx "$S/ssh"
