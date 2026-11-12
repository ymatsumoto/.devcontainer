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
        openssh-server \
    && ln -s /usr/bin/microdnf /usr/bin/dnf \
    && microdnf clean all \
    && rm -rf /var/cache/dnf /var/cache/yum

# Files owned by other users show up as nobody; don't let git refuse them
RUN git config --system --add safe.directory '*'

# sshd never runs as a service. `sshd -i` serves a single connection over
# stdin/stdout, as the ProxyCommand that herdr --remote goes through. The host
# key lives in the per-workspace state (postCreateCommand makes it), so a
# rebuilt container keeps it. PAM is off: there is no login session to set up.
RUN printf '%s\n' 'HostKey /root/.state/sshd/ssh_host_ed25519_key' 'UsePAM no' \
        > /etc/ssh/sshd_config.d/10-devcontainer.conf

ENV PATH="/root/.local/bin:${PATH}"
