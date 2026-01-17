ARG BASE_IMAGE=mcr.microsoft.com/devcontainers/javascript-node:20-bookworm
FROM ${BASE_IMAGE}

USER root

ARG CODEX_VERSION=latest
ARG NPM_VERSION=latest
ARG AIRLOCK_IMAGE_INPUT_SHA=unknown
ENV DEBIAN_FRONTEND=noninteractive

LABEL io.airlock.image_input_sha=$AIRLOCK_IMAGE_INPUT_SHA

# Minimal extras for Airlock portability
RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-venv \
    zsh \
    git \
    curl \
    iproute2 \
    shellcheck \
    stow \
    docker.io \
    podman \
    gosu \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Keep npm current (two-way door via NPM_VERSION)
RUN npm install -g npm@${NPM_VERSION}

# Install Codex CLI
RUN npm install -g @openai/codex@${CODEX_VERSION}

# Ensure the default HOME exists for bind mounts (yolo uses /home/airlock)
RUN mkdir -p /home/airlock
RUN chmod 1777 /home/airlock

# Airlock entrypoint (UID/GID mapping + stable HOME)
COPY entrypoint.sh /usr/local/bin/airlock-entrypoint
RUN chmod +x /usr/local/bin/airlock-entrypoint

# Container engine wrappers (prefer host socket when mounted)
COPY podman-wrapper.sh /usr/local/bin/podman
COPY docker-wrapper.sh /usr/local/bin/docker
RUN chmod +x /usr/local/bin/podman /usr/local/bin/docker

ENTRYPOINT ["/usr/local/bin/airlock-entrypoint"]
CMD ["/bin/zsh"]
