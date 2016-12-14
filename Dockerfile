# vim:set ft=dockerfile:
FROM postgres:9.4

COPY postgres_repl.sh     /
COPY docker-entrypoint.sh /

ADD gestalt.sh            /docker-entrypoint-initdb.d/
