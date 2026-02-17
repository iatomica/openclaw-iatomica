# ---------- Build stage ----------
FROM node:22-bookworm AS build

# Install Bun (required for some build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Enable corepack so we get pnpm (as defined by your repo)
RUN corepack enable

WORKDIR /app

# Optional extra APT packages (keep your original behavior)
ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

# Copy only lockfiles/manifests first for better layer caching
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

# Install deps (pnpm provided by corepack)
RUN pnpm install --frozen-lockfile

# Copy the rest of the repository and build
COPY . .

# Build server (allow missing a2ui at build time)
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build

# Force pnpm for UI build (Bun may fail on ARM/Synology)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build


# ---------- Runtime stage ----------
FROM node:22-bookworm AS runtime

WORKDIR /app

ENV NODE_ENV=production

# Put project binaries (node_modules/.bin) in PATH so "openclaw" works
ENV PATH="/app/node_modules/.bin:${PATH}"

# Create persistent home for OpenClaw (mount your Coolify volume here)
RUN mkdir -p /home/node/.openclaw && chown -R node:node /home/node

# Copy only what's needed to run
COPY --from=build /app/package.json /app/pnpm-workspace.yaml /app/.npmrc /app/
COPY --from=build /app/node_modules /app/node_modules
COPY --from=build /app/dist /app/dist
COPY --from=build /app/ui/dist /app/ui/dist

# Ensure non-root can write in app dir (optional, safe)
RUN chown -R node:node /app

USER node

# Gateway ports (match your repo/docker-compose)
EXPOSE 18789
EXPOSE 18790

# Default: container-friendly (reachable externally)
CMD ["node", "dist/index.js", "gateway", "--allow-unconfigured", "--bind", "lan", "--port", "18789"]
