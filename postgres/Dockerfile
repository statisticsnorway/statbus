# syntax=docker/dockerfile:1.6
# Create image with
#   docker build -t statbus_postgres -f postgres/Dockerfile postgres
# To see all output use
#   docker build --progress=plain -t statbus_postgres -f postgres/Dockerfile postgres
# Using PostgreSQL 18 on Ubuntu lastest LTS

# Set PostgreSQL version
ARG postgresql_major=18

# Set extension versions
ARG pgtap_release=v1.3.3
ARG plpgsql_check_release=v2.8.1
ARG pg_safeupdate_release=0317a2d
ARG wal2json_release=wal2json_2_6
ARG pg_hashids_release=cd0e1b31d52b394a0df64079406a14a4f7387cd6
ARG pgsql_http_release=v1.6.3
ARG pg_trgm_release=1.6
ARG sql_saga_release=9e39fcc
ARG pg_stat_monitor_release=cd0feaf215e7236e3ffbe03458ce84c98b883a3f
ARG pg_repack_release=23aac05f059e37fcbb9e006ab35fb376d79f434a
ARG hypopg_release=1.4.1
ARG index_advisor_release=v0.2.0
ARG pgjwt_release=f3d82fd
ARG pg_graphql_release=9cf4882b3b73e5f15cdcad8f0535ccb7c41db86b
ARG jsonb_stats_release=c4a2595

####################
# Setup Postgres PPA
####################
FROM ubuntu:jammy as ppa
# Redeclare args for use in subsequent stages
ARG postgresql_major

# APT_USE_HTTPS_ONLY: Set to "true" for networks that block HTTP traffic
# When enabled, switches apt sources to HTTPS mirrors before any package installation
ARG APT_USE_HTTPS_ONLY=false

# Bootstrap apt sources - conditionally switch to HTTPS if APT_USE_HTTPS_ONLY=true
# For HTTPS-only networks: temporarily disable cert verification to install ca-certificates,
# then all subsequent operations use verified HTTPS
# Handle both x86_64 (archive.ubuntu.com) and ARM (ports.ubuntu.com) architectures
RUN if [ "$APT_USE_HTTPS_ONLY" = "true" ]; then \
      echo 'Acquire::https::Verify-Peer "false";' > /etc/apt/apt.conf.d/99insecure && \
      sed -i 's|http://archive.ubuntu.com/ubuntu|https://mirrors.edge.kernel.org/ubuntu|g' /etc/apt/sources.list && \
      sed -i 's|http://security.ubuntu.com/ubuntu|https://mirrors.edge.kernel.org/ubuntu|g' /etc/apt/sources.list && \
      sed -i 's|http://ports.ubuntu.com|https://ports.ubuntu.com|g' /etc/apt/sources.list && \
      apt-get update && \
      apt-get install -y --no-install-recommends ca-certificates && \
      rm /etc/apt/apt.conf.d/99insecure && \
      rm -rf /var/lib/apt/lists/*; \
    fi

RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*
# Add Postgres PPA
RUN curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-archive-keyring.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/postgresql-archive-keyring.gpg] https://apt.postgresql.org/pub/repos/apt/ jammy-pgdg main" > /etc/apt/sources.list.d/pgdg.list

####################
# Base image with PostgreSQL installed
####################
FROM ppa as base
# Redeclare args for use in subsequent stages
ARG postgresql_major

# Install PostgreSQL with non-interactive timezone setting
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Oslo
RUN apt-get update && apt-get install -y --no-install-recommends \
  postgresql-${postgresql_major} \
  postgresql-contrib-${postgresql_major} \
  postgresql-server-dev-${postgresql_major} \
  tzdata \
  locales \
  gosu \
  libcurl4-gnutls-dev \
  build-essential \
  git \
  && ln -fs /usr/share/zoneinfo/Europe/Oslo /etc/localtime \
  && dpkg-reconfigure --frontend noninteractive tzdata \
  && rm -rf /var/lib/apt/lists/*

# Set up locales
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
  sed -i -e 's/# nb_NO.UTF-8 UTF-8/nb_NO.UTF-8 UTF-8/' /etc/locale.gen && \
  sed -i -e 's/# ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen && \
  sed -i -e 's/# ky_KG.UTF-8 UTF-8/ky_KG.UTF-8 UTF-8/' /etc/locale.gen && \
  sed -i -e 's/# ar_SA.UTF-8 UTF-8/ar_SA.UTF-8 UTF-8/' /etc/locale.gen && \
  dpkg-reconfigure --frontend=noninteractive locales

ENV PATH=$PATH:/usr/lib/postgresql/${postgresql_major}/bin
ENV PGDATA=/var/lib/postgresql/data
ENV LANG=en_US.utf8

# Create initialization directory
RUN mkdir -p /docker-entrypoint-initdb.d

####################
# Builder image for extensions
####################
FROM base as builder
ARG postgresql_major

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  checkinstall \
  git \
  libcurl4-gnutls-dev \
  libicu-dev \
  libkrb5-dev \
  libssl-dev \
  postgresql-server-dev-${postgresql_major} \
  libzstd-dev \
  liblz4-dev \
  zlib1g-dev \
  libnuma-dev \
  libreadline-dev \
  && rm -rf /var/lib/apt/lists/*

####################
# Build pgtap
####################
FROM builder as pgtap-builder
ARG pgtap_release
WORKDIR /tmp
RUN git clone https://github.com/theory/pgtap.git && \
  cd pgtap && \
  git checkout ${pgtap_release} && \
  make && \
  make DESTDIR=/tmp/pgtap-dist install

####################
# Build plpgsql_check
####################
FROM builder as plpgsql_check-builder
ARG plpgsql_check_release
WORKDIR /tmp
RUN git clone https://github.com/okbob/plpgsql_check.git && \
  cd plpgsql_check && \
  git checkout ${plpgsql_check_release} && \
  make && \
  make DESTDIR=/tmp/plpgsql_check-dist install

####################
# Build pg_safeupdate
####################
FROM builder as pg_safeupdate-builder
ARG pg_safeupdate_release
WORKDIR /tmp
RUN git clone https://github.com/eradman/pg-safeupdate.git && \
  cd pg-safeupdate && \
  git checkout ${pg_safeupdate_release} && \
  make && \
  make DESTDIR=/tmp/pg_safeupdate-dist install && \
  find /tmp/pg_safeupdate-dist -type f | sort

####################
# Build wal2json
####################
FROM builder as wal2json-builder
ARG wal2json_release
WORKDIR /tmp
RUN git clone https://github.com/eulerto/wal2json.git && \
  cd wal2json && \
  git checkout ${wal2json_release} && \
  make && \
  make DESTDIR=/tmp/wal2json-dist install && \
  find /tmp/wal2json-dist -type f | sort

####################
# Build pg_hashids
####################
FROM builder as pg_hashids-builder
ARG pg_hashids_release
WORKDIR /tmp
RUN git clone https://github.com/iCyberon/pg_hashids.git && \
  cd pg_hashids && \
  git checkout ${pg_hashids_release} && \
  make && \
  make DESTDIR=/tmp/pg_hashids-dist install

####################
# Build pgsql_http
####################
FROM builder as pgsql_http-builder
ARG pgsql_http_release
WORKDIR /tmp
RUN git clone https://github.com/pramsey/pgsql-http.git && \
  cd pgsql-http && \
  git checkout ${pgsql_http_release} && \
  make && \
  make DESTDIR=/tmp/pgsql_http-dist install

####################
# Build sql_saga
####################
FROM builder as sql_saga-builder
ARG sql_saga_release
WORKDIR /tmp
RUN git clone https://github.com/veridit/sql_saga.git && \
  cd sql_saga && \
  git checkout ${sql_saga_release} && \
  make install && \
  make DESTDIR=/tmp/sql_saga-dist install

####################
# Build pg_stat_monitor
####################
FROM builder as pg_stat_monitor-builder
ARG pg_stat_monitor_release
WORKDIR /tmp
RUN git clone https://github.com/percona/pg_stat_monitor.git && \
  cd pg_stat_monitor && \
  git checkout ${pg_stat_monitor_release} && \
  make USE_PGXS=1 && \
  make USE_PGXS=1 DESTDIR=/tmp/pg_stat_monitor-dist install

####################
# Build pg_repack
####################
FROM builder as pg_repack-builder
ARG pg_repack_release
WORKDIR /tmp
RUN git clone https://github.com/reorg/pg_repack.git && \
  cd pg_repack && \
  git checkout ${pg_repack_release} && \
  make && \
  make DESTDIR=/tmp/pg_repack-dist install

####################
# Build hypopg
####################
FROM builder as hypopg-builder
ARG hypopg_release
WORKDIR /tmp
RUN git clone https://github.com/HypoPG/hypopg.git && \
  cd hypopg && \
  git checkout ${hypopg_release} && \
  make && \
  make DESTDIR=/tmp/hypopg-dist install

####################
# Build index_advisor
####################
FROM builder as index_advisor-builder
ARG index_advisor_release
WORKDIR /tmp
RUN git clone https://github.com/supabase/index_advisor.git && \
  cd index_advisor && \
  git checkout ${index_advisor_release} && \
  make && \
  make DESTDIR=/tmp/index_advisor-dist install

####################
# Build pgjwt
####################
FROM builder as pgjwt-builder
ARG pgjwt_release
WORKDIR /tmp
RUN git clone https://github.com/michelp/pgjwt.git && \
  cd pgjwt && \
  git checkout ${pgjwt_release} && \
  make && \
  make DESTDIR=/tmp/pgjwt-dist install

####################
# Shared Rust/pgrx builder (used by pg_graphql, jsonb_stats, and sql_saga_native)
####################
FROM builder as pgrx-builder
ARG postgresql_major
WORKDIR /tmp

RUN apt-get update && apt-get install -y --no-install-recommends \
  curl \
  pkg-config \
  libssl-dev \
  && rm -rf /var/lib/apt/lists/* \
  && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

ENV PATH="/root/.cargo/bin:${PATH}"

RUN cargo install --locked cargo-pgrx@0.16.1
RUN cargo pgrx init --pg18=$(which pg_config)

####################
# Build pg_graphql
####################
FROM pgrx-builder as pg_graphql-builder
ARG pg_graphql_release
ARG postgresql_major
WORKDIR /tmp

RUN git clone https://github.com/supabase/pg_graphql.git && \
  cd pg_graphql && \
  git checkout ${pg_graphql_release} && \
  cargo pgrx install --release --features pg18

# Prepare files for installation. Scoped find, NOT `find /`:
#   - bounds the search to pgrx's authoritative install dir, so the source-tree
#     .control under /tmp/pg_graphql/ can never clobber the substituted output
#   - handles "extension ships no SQL file" gracefully (find skips cp when no
#     match); a literal `cp <ext>--*.sql` would fail on shell glob pass-through
#
# Sanity: pgrx must have substituted default_version; fail the build loudly
# if it didn't (belt-and-braces against a future pgrx regression).
RUN grep -qE "default_version = '[0-9]" \
      /usr/share/postgresql/${postgresql_major}/extension/pg_graphql.control
RUN mkdir -p /tmp/pg_graphql-dist/usr/lib/postgresql/${postgresql_major}/lib \
             /tmp/pg_graphql-dist/usr/share/postgresql/${postgresql_major}/extension && \
  cp /usr/lib/postgresql/${postgresql_major}/lib/pg_graphql.so \
     /tmp/pg_graphql-dist/usr/lib/postgresql/${postgresql_major}/lib/ && \
  find /usr/share/postgresql/${postgresql_major}/extension -maxdepth 1 \
       \( -name "pg_graphql.control" -o -name "pg_graphql--*.sql" \) \
       -exec cp {} /tmp/pg_graphql-dist/usr/share/postgresql/${postgresql_major}/extension/ \;

####################
# Build jsonb_stats
####################
FROM pgrx-builder as jsonb_stats-builder
ARG jsonb_stats_release
ARG postgresql_major
WORKDIR /tmp

RUN git clone https://github.com/veridit/jsonb_stats.git && \
  cd jsonb_stats && \
  git checkout ${jsonb_stats_release} && \
  cargo pgrx install --release --features pg18

# See pg_graphql-builder above for the full rationale on scoped-find + sanity.
# jsonb_stats uses pgrx's @CARGO_VERSION@ template; the sanity check below
# fails image build if pgrx ever stops substituting (ref
# pgrx-sql-entity-graph-0.16.1/src/control_file.rs:72 `do_var_replacements`).
RUN grep -qE "default_version = '[0-9]" \
      /usr/share/postgresql/${postgresql_major}/extension/jsonb_stats.control
RUN mkdir -p /tmp/jsonb_stats-dist/usr/lib/postgresql/${postgresql_major}/lib \
             /tmp/jsonb_stats-dist/usr/share/postgresql/${postgresql_major}/extension && \
  cp /usr/lib/postgresql/${postgresql_major}/lib/jsonb_stats.so \
     /tmp/jsonb_stats-dist/usr/lib/postgresql/${postgresql_major}/lib/ && \
  find /usr/share/postgresql/${postgresql_major}/extension -maxdepth 1 \
       \( -name "jsonb_stats.control" -o -name "jsonb_stats--*.sql" \) \
       -exec cp {} /tmp/jsonb_stats-dist/usr/share/postgresql/${postgresql_major}/extension/ \;

####################
# Build sql_saga_native (Rust native planner for sql_saga temporal_merge)
####################
FROM pgrx-builder as sql_saga_native-builder
ARG sql_saga_release
ARG postgresql_major
WORKDIR /tmp

RUN git clone https://github.com/veridit/sql_saga.git && \
  cd sql_saga && \
  git checkout ${sql_saga_release} && \
  cd native && \
  cargo pgrx install --release --features pg18

# See pg_graphql-builder above for the full rationale on scoped-find + sanity.
# sql_saga_native is a pgrx extension with NO generated SQL file (only .so and
# .control), which is why the previous literal-glob `cp <name>--*.sql` failed:
# the unexpanded glob reached `cp` and errored.  Scoped find handles this
# correctly — if no .sql file exists, find just doesn't invoke cp on it.
RUN grep -qE "default_version = '[0-9]" \
      /usr/share/postgresql/${postgresql_major}/extension/sql_saga_native.control
RUN mkdir -p /tmp/sql_saga_native-dist/usr/lib/postgresql/${postgresql_major}/lib \
             /tmp/sql_saga_native-dist/usr/share/postgresql/${postgresql_major}/extension && \
  cp /usr/lib/postgresql/${postgresql_major}/lib/sql_saga_native.so \
     /tmp/sql_saga_native-dist/usr/lib/postgresql/${postgresql_major}/lib/ && \
  find /usr/share/postgresql/${postgresql_major}/extension -maxdepth 1 \
       \( -name "sql_saga_native.control" -o -name "sql_saga_native--*.sql" \) \
       -exec cp {} /tmp/sql_saga_native-dist/usr/share/postgresql/${postgresql_major}/extension/ \;

####################
# pg-runtime-base — assembled pg + extensions + entrypoint.
#
# Renamed from `final` (was the historical last stage) to make room for
# additional ship targets: the seed-builder + seed stages append below,
# and the trailing `pg-runtime` alias re-exports this base as the
# default `docker build` (no --target) result.
#
# This is the production pg image consumed by every running StatBus
# deployment. The seed stage downstream uses this as its base.
####################
FROM base as pg-runtime-base
ARG postgresql_major

# Copy built extensions from builder stages
COPY --from=pgtap-builder /tmp/pgtap-dist/ /
COPY --from=plpgsql_check-builder /tmp/plpgsql_check-dist/ /
COPY --from=pg_safeupdate-builder /tmp/pg_safeupdate-dist/ /
COPY --from=wal2json-builder /tmp/wal2json-dist/ /
COPY --from=pg_hashids-builder /tmp/pg_hashids-dist/ /
COPY --from=pgsql_http-builder /tmp/pgsql_http-dist/ /
COPY --from=sql_saga-builder /tmp/sql_saga-dist/ /
COPY --from=sql_saga_native-builder /tmp/sql_saga_native-dist/ /
COPY --from=pg_stat_monitor-builder /tmp/pg_stat_monitor-dist/ /
COPY --from=pg_repack-builder /tmp/pg_repack-dist/ /
COPY --from=hypopg-builder /tmp/hypopg-dist/ /
COPY --from=index_advisor-builder /tmp/index_advisor-dist/ /
COPY --from=pgjwt-builder /tmp/pgjwt-dist/ /
COPY --from=pg_graphql-builder /tmp/pg_graphql-dist/ /
COPY --from=jsonb_stats-builder /tmp/jsonb_stats-dist/ /

# Add initialization script
COPY init-db.sh /docker-entrypoint-initdb.d/init-db.sh

# Set up the entrypoint
RUN apt-get update && apt-get install -y --no-install-recommends \
  wget \
  gosu \
  && rm -rf /var/lib/apt/lists/*

# Create directory for PostgreSQL configuration
RUN wget -O /usr/local/bin/docker-entrypoint.sh https://raw.githubusercontent.com/docker-library/postgres/master/18/bookworm/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Database configuration variables
ENV POSTGRES_ADMIN_DB=${POSTGRES_ADMIN_DB:-postgres}
ENV POSTGRES_ADMIN_USER=${POSTGRES_ADMIN_USER:-postgres}
ENV POSTGRES_ADMIN_PASSWORD=${POSTGRES_ADMIN_PASSWORD}
ENV POSTGRES_APP_DB=${POSTGRES_APP_DB:-statbus_dev}
ENV POSTGRES_APP_USER=${POSTGRES_APP_USER:-statbus_dev}
ENV POSTGRES_APP_PASSWORD=${POSTGRES_APP_PASSWORD}
ENV POSTGRES_AUTHENTICATOR_PASSWORD=${POSTGRES_AUTHENTICATOR_PASSWORD}

# Expose the ADMIN variables used by docker-entrypoint.sh
ENV POSTGRES_DB=${POSTGRES_ADMIN_DB:-postgres}
ENV POSTGRES_USER=${POSTGRES_ADMIN_USER:-postgres}
ENV POSTGRES_PASSWORD=${POSTGRES_ADMIN_PASSWORD}

ENTRYPOINT ["docker-entrypoint.sh"]
EXPOSE 5432
CMD ["postgres"]

####################
# seed-builder — hermetic seed build. FROM pg-runtime-base so it has the exact
# extensions + init-db.sh the real cluster has. Boots postgres in-build (the
# official entrypoint inits the empty PGDATA → init-db.sh creates template_statbus
# + the cluster roles), then runs the REAL sb seed code (ZERO hand-mirrored SQL),
# dumps, stops. Throwaway: never published. Built with `--target seed` (the seed
# stage below COPYs the dump out).
#
# Multi-context build (same command locally and in CI):
#   --build-context migrations=./migrations
#   --build-context statbus-sb=docker-image://ghcr.io/.../statbus-sb:<commit_short>
#   --build-context prior-seed=<dir>   (REQUIRED; pass an EMPTY dir for a full
#                                       rebuild — the default. STATBUS-116 AC#1.)
# Plan: install-any-commit-via-images.md §canonical-seed-sequence.
####################
FROM pg-runtime-base AS seed-builder
ARG postgresql_major
# Full 40-char commit SHA (images.yaml passes ${{ github.sha }}). Feeds
# seed.json's CommitSHA via `sb db seed dump --commit` — the hermetic /build has
# no .git, so DumpSeed's git rev-parse falls back to this flag. (The sb binary's
# OWN identity for the staleness guard comes from the statbus-sb image's ldflags,
# which CI builds with the same full COMMIT; freshness.IsStale silently skips a
# no-.git projDir, so a valid identity is all the guard needs here.)
ARG COMMIT=unknown
# STATBUS-116 AC#1 — incremental seed enable-gate. 0 (default) → `sb db seed build`
# does a full from-empty rebuild, byte-identical to the pre-AC#1 3-call sequence.
# CI (images.yaml) sets it to 1 ONLY when the repo-level SEED_INCREMENTAL_ENABLED
# knob is on (the single reviewable flip, taken after AC#6). Must default 0 here.
ARG SEED_INCREMENTAL=0
USER root

# sb binary from the published statbus-sb image (distroless: /sb at root).
COPY --from=statbus-sb /sb /usr/local/bin/sb
# Migrations via a named build-context (keeps the main context small).
COPY --from=migrations . /build/migrations/
# Reference-data CSVs the migrations \copy from (dbseed/, repo root, ~2.5MB).
# Migrations resolve these relative to projDir, so they must land at /build/dbseed/.
COPY --from=dbseed . /build/dbseed/
# STATBUS-116 AC#1 — the incremental base. ALWAYS present (build-context is
# required), but EMPTY by default → no /build/.prior-seed/seed.json → `sb db seed
# build` sees no prior → full rebuild. CI injects the closest published ancestor's
# seed here (seed.pg_dump + seed.json) ONLY when incremental is enabled.
COPY --from=prior-seed . /build/.prior-seed/

# Faux project dir: config.ProjectDir() walks up for `.statbus`; PsqlCommand /
# PgDumpCommand read connection keys from .env ONLY. DOCKER_PSQL=0 forces
# host-psql against the in-build postgres; CADDY_DEPLOYMENT_MODE=standalone dodges
# the dev-only rebuild branch (maybeRebuildTestTemplate no-ops).
WORKDIR /build
RUN touch .statbus && printf '%s\n' \
      'SITE_DOMAIN=127.0.0.1' \
      'CADDY_DEPLOYMENT_MODE=standalone' \
      'CADDY_DB_BIND_ADDRESS=127.0.0.1' \
      'CADDY_DB_PORT=5432' \
      'DOCKER_PSQL=0' \
      'POSTGRES_ADMIN_DB=postgres' \
      'POSTGRES_ADMIN_USER=postgres' \
      'POSTGRES_ADMIN_PASSWORD=build' \
      'POSTGRES_APP_DB=statbus_app' \
      'POSTGRES_APP_USER=statbus_app' \
      'POSTGRES_APP_PASSWORD=build' \
      'POSTGRES_AUTHENTICATOR_PASSWORD=build' \
      'POSTGRES_NOTIFY_USER=notify_reader_user' \
      'POSTGRES_NOTIFY_PASSWORD=build' \
      'POSTGRES_SEED_DB=statbus_seed' \
      'UPGRADE_CHANNEL=seed-build' \
      > .env

# Boot pg (entrypoint inits the empty PGDATA → init-db.sh → template_statbus +
# cluster roles), then build the seed via the REAL sb subcommands (no
# hand-mirrored SQL): create-db → migrate up --target seed → dump (--commit, no
# .git here). `set -e` → any failure aborts the build LOUDLY (no silently-bad
# seed). pg_isready -h 127.0.0.1 only returns 0 AFTER the post-init exec of
# postgres binds TCP, so the wait also guarantees init-db.sh has run.
RUN set -eu; \
    export PGDATA="${PGDATA:-/var/lib/postgresql/data}" \
           POSTGRES_PASSWORD=build POSTGRES_USER=postgres POSTGRES_DB=postgres \
           POSTGRES_ADMIN_USER=postgres POSTGRES_ADMIN_PASSWORD=build \
           POSTGRES_APP_DB=statbus_app POSTGRES_APP_USER=statbus_app POSTGRES_APP_PASSWORD=build \
           POSTGRES_AUTHENTICATOR_PASSWORD=build \
           POSTGRES_NOTIFY_USER=notify_reader_user POSTGRES_NOTIFY_PASSWORD=build \
           SEED_INCREMENTAL="${SEED_INCREMENTAL:-0}"; \
    docker-entrypoint.sh postgres & \
    entrypoint_pid="$!"; \
    echo "seed-builder: waiting for postgres (TCP 127.0.0.1:5432)..."; \
    for _ in $(seq 1 120); do pg_isready -h 127.0.0.1 -U postgres -q && break; sleep 1; done; \
    pg_isready -h 127.0.0.1 -U postgres; \
    echo "seed-builder: postgres up — sb db seed build (SEED_INCREMENTAL=$SEED_INCREMENTAL)"; \
    sb db seed build --commit "$COMMIT"; \
    test -s /build/.db-seed/seed.pg_dump; \
    test -s /build/.db-seed/seed.json; \
    echo "seed-builder: stopping postgres"; \
    su postgres -c "pg_ctl -D \"$PGDATA\" stop -m fast" || kill "$entrypoint_pid" || true

####################
# seed — busybox:musl self-documenting shipping image (~8MB measured: the
# ~4.6MB seed.pg_dump + the 2.72MB busybox:musl base — ~3.6MB more than a
# FROM scratch image shipping the seed alone). Built with `--target seed`,
# published as statbus-seed:<commit_short>. Ships BOTH seed.pg_dump AND
# seed.json — the restore path REQUIRES seed.json (without it install degrades
# to the full-migration fallback). busybox:musl (vs FROM scratch) gives the
# image a shell, so its CMD documents extraction: `docker run` prints usage
# instead of erroring on a command-less image — the cost of a self-documenting,
# registry-discoverable artifact. The seed is architecture-independent pg_dump
# data extracted via docker cp (never executed), so the amd64-only image is
# usable from any host.
####################
FROM busybox:musl AS seed
LABEL org.opencontainers.image.description="StatBus pre-migration DB seed (/seed.pg_dump + /seed.json). Not a runnable service; docker run prints extraction usage. Operators: ./sb db seed fetch."
COPY --from=seed-builder /build/.db-seed/seed.pg_dump /seed.pg_dump
COPY --from=seed-builder /build/.db-seed/seed.json    /seed.json
CMD ["sh","-c","printf '%s\\n' \\\n  'statbus-seed: the StatBus pre-migration database seed (not a runnable service).' \\\n  '' \\\n  'This image ships two files:' \\\n  '  /seed.pg_dump   pg_dump of the seeded database' \\\n  '  /seed.json      seed metadata (migration version)' \\\n  '' \\\n  'Operators: ./sb db seed fetch   (does the extraction for you)' \\\n  '' \\\n  'By hand:' \\\n  '  cid=$(docker create IMAGE)' \\\n  '  docker cp $cid:/seed.pg_dump ./ && docker cp $cid:/seed.json ./' \\\n  '  docker rm $cid'"]

####################
# pg-runtime — DEFAULT build target. Zero-cost alias of pg-runtime-base,
# placed LAST so `docker build` (no --target) produces this stage (NOT the seed).
#
# The `seed-builder` + `seed` stages above sit BETWEEN pg-runtime-base and this
# alias; this alias must remain LAST to preserve default-target behavior.
#
# Plan reference: install-any-commit-via-images.md §Dockerfile structure.
####################
FROM pg-runtime-base as pg-runtime
