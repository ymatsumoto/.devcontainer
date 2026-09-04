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

# podman-in-podman: use fuse-overlayfs (falls back to vfs if unavailable)
COPY storage.conf /etc/containers/storage.conf
