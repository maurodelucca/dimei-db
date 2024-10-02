FROM --platform=linux/amd64 ubuntu:14.04

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        firebird2.5-superclassic; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    sed -i '/^RemoteBindAddress = localhost/s/^/# /' /etc/firebird/2.5/firebird.conf

# Data directory
ENV FIREBIRD_DATA /data
RUN set -eux; \
    mkdir -p "$FIREBIRD_DATA"; \
    chown -R firebird:firebird "$FIREBIRD_DATA"; \
    chmod 644 "$FIREBIRD_DATA"
VOLUME $FIREBIRD_DATA

# Entrypoint
COPY entrypoint.sh /usr/local/bin/
RUN set -eux; \
    chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]

EXPOSE 3050/tcp

# Fix terminfo location
ENV TERMINFO=/lib/terminfo/

CMD ["firebird"]