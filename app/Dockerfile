FROM node:20-alpine AS base
COPY .nvmrc ./
RUN if [ "$(head -n 1 .nvmrc | cut -d'.' -f1)" != "v20" ]; then \
      echo "Node.js version in .nvmrc is not v20. Please update the FROM image or .nvmrc to match."; \
      exit 1; \
    fi

FROM base AS build
RUN corepack enable pnpm && corepack install -g pnpm
WORKDIR /app
COPY pnpm-lock.yaml ./
RUN --mount=type=cache,id=pnpm,target=/root/.local/share/pnpm/store pnpm fetch --frozen-lockfile
COPY package.json ./
RUN --mount=type=cache,id=pnpm,target=/root/.local/share/pnpm/store pnpm install -r --offline --frozen-lockfile --aggregate-output
COPY . .
RUN pnpm run build

FROM base AS runner
RUN apk add --no-cache dumb-init
RUN addgroup -S nodejs -g 1001
RUN adduser -S nextjs -u 1001
WORKDIR /app
# Automatically leverage output traces to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=build --chown=nextjs:nodejs /app/.next/standalone ./.next/standalone
COPY --from=build --chown=nextjs:nodejs /app/.next/static ./public/_next/static
COPY --from=build --chown=nextjs:nodejs /app/public ./public

USER nextjs
EXPOSE 3000
ENV PORT 3000
ENV NODE_ENV production
CMD ["dumb-init","node", "/app/.next/standalone/server.js"]
