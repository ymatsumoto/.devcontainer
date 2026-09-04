FROM docker.io/almalinux/9-minimal:latest

# GitHub CLI は AlmaLinux の標準リポジトリに無いので、公式 RPM リポジトリを追加する。
# 鍵を先に import しておかないと gpgcheck=1 のトランザクションが失敗する。
RUN curl -fsSL -o /etc/yum.repos.d/gh-cli.repo https://cli.github.com/packages/rpm/gh-cli.repo \
    && rpm --import https://cli.github.com/packages/githubcli-archive-keyring.asc

RUN microdnf install -y --nodocs --setopt=install_weak_deps=0 \
        tmux \
        git \
        gh \
        tar \
        gzip \
        podman \
        fuse-overlayfs \
        python3 \
        poppler-utils \
        jq \
    && ln -s /usr/bin/microdnf /usr/bin/dnf \
    && microdnf clean all \
    && rm -rf /var/cache/dnf /var/cache/yum

# postCreateCommand が入れる CLI (claude / antigravity / codex) の置き場所を PATH に通す。
# .bashrc ではなくイメージ側で設定する理由: .bashrc は非対話シェルで早期 return するうえ、
# postCreateCommand はそもそも .bashrc を読まないシェルで実行されるため、
# ライフサイクルスクリプトからは見えない。devcontainer.json の containerEnv も使えない
# (既存 PATH を参照する ${containerEnv:PATH} は remoteEnv でのみ有効)。
#
# これは codex の公式インストーラにも効く。BIN_DIR が既に PATH にあると
# add_to_path() が即 return し、~/.bashrc への PATH ブロック追記を行わない。
ENV PATH="/root/.local/bin:${PATH}"

# podman-in-podman: use fuse-overlayfs (falls back to vfs if unavailable)
COPY storage.conf /etc/containers/storage.conf
