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

# Prepare files for installation
RUN mkdir -p /tmp/pg_graphql-dist/usr/lib/postgresql/${postgresql_major}/lib && \
  mkdir -p /tmp/pg_graphql-dist/usr/share/postgresql/${postgresql_major}/extension && \
  cp /usr/lib/postgresql/18/lib/pg_graphql.so /tmp/pg_graphql-dist/usr/lib/postgresql/${postgresql_major}/lib/ && \
  find / -name "pg_graphql.control" -exec cp {} /tmp/pg_graphql-dist/usr/share/postgresql/${postgresql_major}/extension/ \; && \
  find / -name "pg_graphql--*.sql" -exec cp {} /tmp/pg_graphql-dist/usr/share/postgresql/${postgresql_major}/extension/ \;

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

# Prepare files for installation
RUN mkdir -p /tmp/jsonb_stats-dist/usr/lib/postgresql/${postgresql_major}/lib && \
  mkdir -p /tmp/jsonb_stats-dist/usr/share/postgresql/${postgresql_major}/extension && \
  cp /usr/lib/postgresql/${postgresql_major}/lib/jsonb_stats.so /tmp/jsonb_stats-dist/usr/lib/postgresql/${postgresql_major}/lib/ && \
  find / -name "jsonb_stats.control" -exec cp {} /tmp/jsonb_stats-dist/usr/share/postgresql/${postgresql_major}/extension/ \; && \
  find / -name "jsonb_stats--*.sql" -exec cp {} /tmp/jsonb_stats-dist/usr/share/postgresql/${postgresql_major}/extension/ \;

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

# Prepare files for installation
RUN mkdir -p /tmp/sql_saga_native-dist/usr/lib/postgresql/${postgresql_major}/lib && \
  mkdir -p /tmp/sql_saga_native-dist/usr/share/postgresql/${postgresql_major}/extension && \
  cp /usr/lib/postgresql/${postgresql_major}/lib/sql_saga_native.so /tmp/sql_saga_native-dist/usr/lib/postgresql/${postgresql_major}/lib/ && \
  find / -name "sql_saga_native.control" -exec cp {} /tmp/sql_saga_native-dist/usr/share/postgresql/${postgresql_major}/extension/ \; && \
  find / -name "sql_saga_native--*.sql" -exec cp {} /tmp/sql_saga_native-dist/usr/share/postgresql/${postgresql_major}/extension/ \;

####################
# Final image
####################
FROM base as final
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
