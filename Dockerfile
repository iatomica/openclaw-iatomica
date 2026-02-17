# ---------- Build stage ----------
FROM node:22-bookworm AS build

# (1) Limitar RAM para evitar OOM en VPS chicos
ENV NODE_OPTIONS="--max-old-space-size=1024"
ENV CI=1

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable
WORKDIR /app

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

# Copy manifests/lockfiles first (cache-friendly)
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

# (2) Instalar con menos presión de memoria
# - prefer-offline reduce descargas si hay cache
# - no audit, no fund reduce overhead
RUN pnpm install --frozen-lockfile --prefer-offline --no-fund --no-audit

# Copy repo and build
COPY . .

# (3) Build server + UI, pero manteniendo límite de RAM
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build


# ---------- Runtime stage ----------
FROM node:22-bookworm AS runtime

WORKDIR /app
ENV NODE_ENV=production

# Make local bins available (openclaw if it exists as bin)
ENV PATH="/app/node_modules/.bin:${PATH}"

# Persistent dir (mount volume here in Coolify)
RUN mkdir -p /home/node/.openclaw && chown -R node:node /home/node

# Copy runtime essentials only
COPY --from=build /app/package.json /app/
COPY --from=build /app/node_modules /app/node_modules
COPY --from=build /app/dist /app/dist
COPY --from=build /app/ui/dist /app/ui/dist

RUN chown -R node:node /app
USER node

EXPOSE 18789
EXPOSE 18790

CMD ["node", "dist/index.js", "gateway", "--allow-unconfigured", "--bind", "lan", "--port", "18789"]
