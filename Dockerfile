# vim:set ft=dockerfile:
FROM postgres:9.4

RUN apt-get update && apt-get install -y \
    daemontools \
    libevent-dev \
    python3-pip \
    lzop \
    pv \
 && pip3 install wal-e boto \
 && rm -rf /var/lib/apt/lists/* \
 && apt-get remove -y python3-pip

COPY postgres_repl.sh     /
COPY docker-entrypoint.sh /

ADD gestalt.sh            /docker-entrypoint-initdb.d/
