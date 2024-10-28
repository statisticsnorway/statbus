FROM node:20-alpine AS base
COPY .nvmrc ./
RUN if [ "$(head -n 1 .nvmrc | cut -d'.' -f1)" != "v20" ]; then \
      echo "Node.js version in .nvmrc is not v20. Please update the FROM image or .nvmrc to match."; \
      exit 1; \
    fi

FROM base AS build
RUN corepack enable
RUN corepack prepare pnpm@latest --activate
WORKDIR /app
COPY pnpm-lock.yaml ./
RUN --mount=type=cache,id=pnpm,target=/root/.local/share/pnpm/store pnpm fetch --frozen-lockfile
COPY package.json ./
RUN --mount=type=cache,id=pnpm,target=/root/.local/share/pnpm/store pnpm install -r --offline --frozen-lockfile --aggregate-output
COPY . .
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY
ARG NEXT_PUBLIC_BROWSER_SUPABASE_URL
ARG NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME
ARG NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE

ENV NEXT_PUBLIC_SUPABASE_ANON_KEY=${NEXT_PUBLIC_SUPABASE_ANON_KEY}
ENV NEXT_PUBLIC_BROWSER_SUPABASE_URL=${NEXT_PUBLIC_BROWSER_SUPABASE_URL}
ENV NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME=${NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME}
ENV NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE=${NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE}
RUN pnpm run build

FROM base AS runner
RUN apk add --no-cache dumb-init
RUN addgroup -S nodejs -g 1001
RUN adduser -S nextjs -u 1001
WORKDIR /app
# Automatically leverage output traces to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing
# The server will serve files in the .next/static directory
# relative to itself, so therefore put the server in
#   /app
# And the static files to serve from http://.../_next/static in:
#   /app/.next/static
COPY --from=build --chown=nextjs:nodejs /app/.next/standalone ./
# The static files can also be used by the next.js backend to resize, include, etc.
COPY --from=build --chown=nextjs:nodejs /app/.next/static ./.next/static
# The public files are served by next.js server,
# and can be copied out for Caddy to serve them directly.
#   /app/public
COPY --from=build --chown=nextjs:nodejs /app/public ./public
# Apply the same mapping that next.js server does exposing .next as _next
COPY --from=build --chown=nextjs:nodejs /app/.next/static ./public/_next/static

USER nextjs
EXPOSE 3000
ENV PORT 3000
ENV NODE_ENV production
CMD ["dumb-init","node", "server.js"]
