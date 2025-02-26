FROM alpine:latest AS base

FROM base AS build

# Install Crystal and dependencies
RUN apk add --no-cache \
    crystal \
    shards \
    gcc \
    g++ \
    make \
    libc-dev \
    pcre-dev \
    libevent-dev \
    openssl-dev \
    yaml-dev \
    tzdata \
    git

WORKDIR /app
COPY shard.yml shard.lock* ./
RUN shards install --production

COPY src/ ./src/
RUN shards build statbus --release --no-debug

FROM base AS run

# Install runtime dependencies only
RUN apk add --no-cache \
    libgcc \
    libstdc++ \
    libevent \
    pcre \
    pcre2 \
    openssl \
    tzdata \
    dumb-init \
    gmp \
    yaml \
    gc-dev

# Set environment variable for Docker detection
ENV RUNNING_IN_DOCKER=true

WORKDIR /app
COPY --from=build /app/bin/statbus /app/bin/statbus

# Create a non-root user to run the application
RUN addgroup -S crystal && adduser -S crystal -G crystal
USER crystal

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/app/bin/statbus", "worker"]
