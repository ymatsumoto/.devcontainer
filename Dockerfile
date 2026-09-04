FROM docker.io/almalinux/9-minimal:latest

RUN microdnf install -y --nodocs --setopt=install_weak_deps=0 \
        tmux \
        git \
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
