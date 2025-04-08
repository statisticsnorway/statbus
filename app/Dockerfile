FROM node:22-alpine AS base
COPY .nvmrc ./
RUN if [ "$(head -n 1 .nvmrc | cut -d'.' -f1)" != "v22" ]; then \
  echo "Node.js version in .nvmrc is not v22. Please update the FROM image or .nvmrc to match."; \
  exit 1; \
  fi

FROM base AS install
# Enables corepack
RUN corepack enable
RUN corepack prepare pnpm@latest-10
# Check if pnpm major version in package.json matches the one we're using
COPY package.json ./
RUN PNPM_VERSION_IN_PACKAGE=$(grep -o '"packageManager": "pnpm@[0-9]*' package.json | grep -o '[0-9]*') && \
    if [ "$PNPM_VERSION_IN_PACKAGE" != "10" ]; then \
      echo "pnpm version in package.json is not 10.x. Please update the Dockerfile or package.json to match."; \
      exit 1; \
    fi
WORKDIR /app
COPY pnpm-lock.yaml ./
RUN --mount=type=cache,id=pnpm,target=/root/.local/share/pnpm/store pnpm fetch --frozen-lockfile
COPY package.json ./
RUN --mount=type=cache,id=pnpm,target=/root/.local/share/pnpm/store pnpm install -r --offline --frozen-lockfile --aggregate-output
COPY . .
ARG NEXT_PUBLIC_BROWSER_API_URL
ARG NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME
ARG NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE

ENV NEXT_PUBLIC_BROWSER_API_URL=${NEXT_PUBLIC_BROWSER_API_URL}
ENV NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME=${NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME}
ENV NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE=${NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE}

FROM install AS build
RUN pnpm run build

# Run the tests with
#   docker build --target test -t statbus-app-test .
#   docker run --rm statbus-app-test
#
FROM install AS test
COPY --from=install /app /app
WORKDIR /app
CMD pnpm run tsc && \
  pnpm run lint --quiet && \
  pnpm test -- --ci --silent && \
  pnpm run build

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
ENV PORT=3000
ENV NODE_ENV=production
CMD ["dumb-init","node", "server.js"]
