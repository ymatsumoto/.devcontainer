FROM docker.io/almalinux/9-minimal:latest

RUN microdnf install -y --nodocs --setopt=install_weak_deps=0 epel-release \
    && sed -i '/^\[crb\]/,/^\[/ s/^enabled=0/enabled=1/' /etc/yum.repos.d/almalinux-crb.repo \
    && microdnf install -y --nodocs --setopt=install_weak_deps=0 \
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
