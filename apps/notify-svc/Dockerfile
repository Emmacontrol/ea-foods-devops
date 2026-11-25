# syntax=docker/dockerfile:1.7

# ---- Stage 1: install production dependencies only (no eslint etc.) ----
FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
# mkdir: today there are zero runtime deps, so npm creates no node_modules.
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force && mkdir -p node_modules

# ---- Stage 2: distroless runtime — no shell, no package manager, non-root (uid 65532) ----
FROM gcr.io/distroless/nodejs24-debian13:nonroot AS runtime
ENV NODE_ENV=production \
    PORT=3000
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

USER 65532:65532
EXPOSE 3000

# Used by docker compose; ECS uses the health check in the task definition.
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/nodejs/bin/node", "src/healthcheck.js"]

# The distroless entrypoint is already `node`.
CMD ["src/server.js"]
