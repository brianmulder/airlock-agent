ARG BASE_IMAGE=mcr.microsoft.com/devcontainers/javascript-node:20-bookworm
FROM ${BASE_IMAGE}

ARG CODEX_VERSION=latest
ENV DEBIAN_FRONTEND=noninteractive

# Minimal extras for Airlock portability
RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-venv \
    zsh \
    git \
    curl \
    iproute2 \
    gosu \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Codex CLI
RUN npm install -g @openai/codex@${CODEX_VERSION}

# Airlock entrypoint (UID/GID mapping + stable HOME)
COPY entrypoint.sh /usr/local/bin/airlock-entrypoint
RUN chmod +x /usr/local/bin/airlock-entrypoint

USER root
ENTRYPOINT ["/usr/local/bin/airlock-entrypoint"]
CMD ["/bin/zsh"]
