FROM docker.io/almalinux/9-minimal:latest

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

ENV PATH="/root/.local/bin:${PATH}"

# storage.conf は devcontainer.json の mounts でバインドする。
# ビルド時には使わない（podman が実行時に読むだけ）ので COPY をやめ、
# 再ビルドせずに driver=vfs へ切り替えられるようにした。
