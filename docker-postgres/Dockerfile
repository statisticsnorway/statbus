# syntax=docker/dockerfile:1.6
# Create image with
#   docker build -t statbus_postgres -f docker-postgres/Dockerfile docker-postgres
# Using PostgreSQL 17 on Ubuntu

# Set PostgreSQL version
ARG postgresql_major=17
ARG postgresql_release=${postgresql_major}.0

# Set extension versions
ARG pg_cron_release=1.6.2
ARG pgtap_release=1.2.0
ARG plpgsql_check_release=2.2.5
ARG pg_safeupdate_release=1.4
ARG wal2json_release=2_5
ARG pg_hashids_release=cd0e1b31d52b394a0df64079406a14a4f7387cd6
ARG pgsql_http_release=1.5.0
ARG pg_trgm_release=1.6
ARG sql_saga_release=c65b6f850f3d123003b073fa59c666f1d44e7021

####################
# Setup Postgres PPA
####################
FROM ubuntu:jammy as ppa
# Redeclare args for use in subsequent stages
ARG postgresql_major
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*
# Add Postgres PPA
RUN curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-archive-keyring.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/postgresql-archive-keyring.gpg] http://apt.postgresql.org/pub/repos/apt/ jammy-pgdg main" > /etc/apt/sources.list.d/pgdg.list

####################
# Base image with PostgreSQL installed
####################
FROM ppa as base
# Redeclare args for use in subsequent stages
ARG postgresql_major
ARG postgresql_release

# Install PostgreSQL with non-interactive timezone setting
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Oslo
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-${postgresql_major} \
    postgresql-contrib-${postgresql_major} \
    tzdata \
    locales \
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
ARG postgresql_release

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
    && rm -rf /var/lib/apt/lists/*

####################
# Build pg_cron
####################
FROM builder as pg_cron-builder
ARG pg_cron_release
WORKDIR /tmp
RUN git clone https://github.com/citusdata/pg_cron.git && \
    cd pg_cron && \
    # Use main branch which has PostgreSQL 17 compatibility fixes
    git checkout main && \
    make && \
    make DESTDIR=/tmp/pg_cron-dist install
    
####################
# Build pgtap
####################
FROM builder as pgtap-builder
ARG pgtap_release
WORKDIR /tmp
RUN git clone https://github.com/theory/pgtap.git && \
    cd pgtap && \
    git checkout v${pgtap_release} && \
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
    # Use master branch for PostgreSQL 17 compatibility
    git checkout master && \
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
    make DESTDIR=/tmp/pg_safeupdate-dist install

####################
# Build wal2json
####################
FROM builder as wal2json-builder
ARG wal2json_release
WORKDIR /tmp
RUN git clone https://github.com/eulerto/wal2json.git && \
    cd wal2json && \
    # Use master branch for PostgreSQL 17 compatibility
    git checkout master && \
    make && \
    make DESTDIR=/tmp/wal2json-dist install

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
    # Use master branch for PostgreSQL 17 compatibility
    git checkout master && \
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
    # Use master branch for PostgreSQL 17 compatibility
    git checkout master && \
    make install && \
    make DESTDIR=/tmp/sql_saga-dist install

####################
# Final image
####################
FROM base as final
ARG postgresql_major

# Copy built extensions from builder stages
COPY --from=pg_cron-builder /tmp/pg_cron-dist/ /
COPY --from=pgtap-builder /tmp/pgtap-dist/ /
COPY --from=plpgsql_check-builder /tmp/plpgsql_check-dist/ /
COPY --from=pg_safeupdate-builder /tmp/pg_safeupdate-dist/ /
COPY --from=wal2json-builder /tmp/wal2json-dist/ /
COPY --from=pg_hashids-builder /tmp/pg_hashids-dist/ /
COPY --from=pgsql_http-builder /tmp/pgsql_http-dist/ /
COPY --from=sql_saga-builder /tmp/sql_saga-dist/ /

# Add initialization script
COPY init-user-db.sh /docker-entrypoint-initdb.d/init-user-db.sh

# Set up the entrypoint
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    && rm -rf /var/lib/apt/lists/*
RUN wget -O /usr/local/bin/docker-entrypoint.sh https://raw.githubusercontent.com/docker-library/postgres/master/17/bookworm/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Set default environment variables that can be overridden
ENV POSTGRES_DB=statbus_development
ENV POSTGRES_USER=statbus_development
ENV POSTGRES_PASSWORD=postgres

ENTRYPOINT ["docker-entrypoint.sh"]
EXPOSE 5432
CMD ["postgres"]
