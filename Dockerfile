# ---------- Build stage ----------
FROM node:22-bookworm AS build

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

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile
COPY . .

RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

# ---------- Runtime stage ----------
FROM node:22-bookworm AS runtime

WORKDIR /app
ENV NODE_ENV=production

# para que el bin "openclaw" sea invocable si existe en node_modules/.bin
ENV PATH="/app/node_modules/.bin:${PATH}"

# Directorio persistente esperado (montá volumen acá)
RUN mkdir -p /home/node/.openclaw && chown -R node:node /home/node

COPY --from=build /app/package.json /app/
COPY --from=build /app/node_modules /app/node_modules
COPY --from=build /app/dist /app/dist
COPY --from=build /app/ui/dist /app/ui/dist

RUN chown -R node:node /app
USER node

EXPOSE 18789
EXPOSE 18790

CMD ["node", "dist/index.js", "gateway", "--allow-unconfigured", "--bind", "lan", "--port", "18789"]
