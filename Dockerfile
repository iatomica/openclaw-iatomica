# syntax=docker/dockerfile:1.6

############################
# Build stage
############################
FROM node:22-bookworm AS build

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Enable Corepack so pnpm can be used
RUN corepack enable

WORKDIR /app

# Optional apt packages
ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

# Copy only the minimum first (better caching)
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

# Install dependencies (workspace)
RUN pnpm install --frozen-lockfile --prefer-offline

# Copy full repo
COPY . .

# Build main + ui
# (OPENCLAW_A2UI_SKIP_MISSING=1 to avoid failing when A2UI sources aren't present)
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
RUN pnpm ui:build

# IMPORTANT:
# Your logs show UI assets are output to /app/dist/control-ui (NOT /app/ui/dist).
# We'll copy from /app/dist/control-ui in the runtime stage.


############################
# Runtime stage
############################
FROM node:22-bookworm AS runtime

WORKDIR /app

# Allow runtime to write needed files for the non-root user
RUN mkdir -p /home/node/.openclaw && chown -R node:node /home/node

# Copy runtime artifacts
COPY --from=build /app/package.json /app/
COPY --from=build /app/node_modules /app/node_modules
COPY --from=build /app/dist /app/dist

# ✅ Fix: copy UI from the path that actually exists
# We keep the runtime path as /app/ui/dist (so your app can serve it consistently),
# but source it from /app/dist/control-ui (the vite output you logged).
COPY --from=build /app/dist/control-ui /app/ui/dist

USER node

# If your app listens on a port, expose it (optional)
# EXPOSE 3000

# Adjust if your entrypoint differs
CMD ["node", "/app/dist/entry.js"]
