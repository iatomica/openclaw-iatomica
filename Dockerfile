# ---------- Build stage ----------
FROM node:22-bookworm AS build

# Reduce memory pressure during install/build (helps on small VPS)
ENV NODE_OPTIONS="--max-old-space-size=1024"
ENV CI=1

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Enable corepack (pnpm comes from here)
RUN corepack enable

WORKDIR /app

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

# Copy lockfiles/manifests first for cache
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

# pnpm install (keep only safe, supported flags)
RUN pnpm install --frozen-lockfile --prefer-offline

# Copy source and build
COPY . .

RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build


# ---------- Runtime stage ----------
FROM node:22-bookworm AS runtime

WORKDIR /app
ENV NODE_ENV=production

# Make local bins available (so "openclaw" works if exposed by package.json bin)
ENV PATH="/app/node_modules/.bin:${PATH}"

# Persistent dir (mount volume here in Coolify)
RUN mkdir -p /home/node/.openclaw && chown -R node:node /home/node

# Copy only what's needed at runtime
COPY --from=build /app/package.json /app/
COPY --from=build /app/node_modules /app/node_modules
COPY --from=build /app/dist /app/dist
COPY --from=build /app/ui/dist /app/ui/dist

# Allow non-root user to write files at runtime
RUN chown -R node:node /app

USER node

EXPOSE 18789
EXPOSE 18790

# Container-friendly default (reachable from Coolify/Traefik)
CMD ["node", "dist/index.js", "gateway", "--allow-unconfigured", "--bind", "lan", "--port", "18789"]
