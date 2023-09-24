# Create image with
#   docker build -t statbus_postgres .
# We use the same version supported by the latest Ubuntu LTS release
FROM postgres:14

RUN apt-get update && \
    apt-get install -y \
        locales && \
    rm -r /var/lib/apt/lists/*

RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    sed -i -e 's/# nb_NO.UTF-8 UTF-8/nb_NO.UTF-8 UTF-8/' /etc/locale.gen && \
    sed -i -e 's/# ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen && \
    sed -i -e 's/# ky_KG.UTF-8 UTF-8/ky_KG.UTF-8 UTF-8/' /etc/locale.gen && \
    sed -i -e 's/# ar_SA.UTF-8 UTF-8/ar_SA.UTF-8 UTF-8/' /etc/locale.gen && \
    dpkg-reconfigure --frontend=noninteractive locales

# Non Debian ways of adding locale, superseded by the block above.
# RUN localedef -i nb_NO -c -f UTF-8 -A /usr/share/locale/locale.alias nb_NO.UTF-8
# RUN localedef -i ru_RU -c -f UTF-8 -A /usr/share/locale/locale.alias ru_RU.UTF-8
# RUN localedef -i ky_KY -c -f UTF-8 -A /usr/share/locale/locale.alias ky_KG.UTF-8

ENV LANG en_US.utf8

ADD init-user-db.sh /docker-entrypoint-initdb.d/init-user-db.sh