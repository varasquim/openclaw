FROM node:22-bookworm@sha256:cd7bcd2e7a1e6f72052feb023c7f6b722205d3fcab7bbcbd2d1bfdab10b1e935

ARG UID=1159850719
ARG GID=1159800513

# -------------------------------------------------
# Base system dependencies
# -------------------------------------------------

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        file \
        git \
        procps \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# -------------------------------------------------
# Install Bun (build tooling)
# -------------------------------------------------

RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

# -------------------------------------------------
# Create application user
# -------------------------------------------------

RUN groupadd -g $GID appgroup && \
    useradd -m -u $UID -g $GID appuser

WORKDIR /app
RUN chown appuser:appgroup /app

# -------------------------------------------------
# Install Homebrew (Linux)
# -------------------------------------------------

# Create linuxbrew user
RUN useradd -m linuxbrew

USER linuxbrew

# HOME aqui é automaticamente /home/linuxbrew
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

RUN brew update

USER root

# Permitir que appuser use o brew
RUN chown -R appuser:appgroup /home/linuxbrew

# -------------------------------------------------
# Ajustar HOME final para runtime
# -------------------------------------------------

ENV HOME=/home/appuser
RUN mkdir -p /home/appuser/.cache && \
    chown -R appuser:appgroup /home/appuser

ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

# -------------------------------------------------
# Optional APT packages
# -------------------------------------------------

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

# -------------------------------------------------
# Install Node dependencies
# -------------------------------------------------

COPY --chown=appuser:appgroup package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY --chown=appuser:appgroup ui/package.json ./ui/package.json
COPY --chown=appuser:appgroup patches ./patches
COPY --chown=appuser:appgroup scripts ./scripts

USER appuser
RUN pnpm install --frozen-lockfile

# -------------------------------------------------
# Optional Playwright browser install
# -------------------------------------------------

USER root
ARG OPENCLAW_INSTALL_BROWSER=""
RUN if [ -n "$OPENCLAW_INSTALL_BROWSER" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends xvfb && \
      mkdir -p /home/appuser/.cache/ms-playwright && \
      chown -R appuser:appgroup /home/appuser/.cache && \
      su -s /bin/sh appuser -c "PLAYWRIGHT_BROWSERS_PATH=/home/appuser/.cache/ms-playwright node /app/node_modules/playwright-core/cli.js install --with-deps chromium" && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

USER appuser

# -------------------------------------------------
# Build project
# -------------------------------------------------

COPY --chown=appuser:appgroup . .

RUN pnpm build

ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

USER root
RUN chmod -R a+rX /app
USER appuser

ENV NODE_ENV=production

# -------------------------------------------------
# Start gateway
# -------------------------------------------------

CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured"]
