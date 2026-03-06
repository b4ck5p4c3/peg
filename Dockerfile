# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv;error=true
FROM docker.io/postgres:18-trixie

# Install Peg dependencies
RUN <<-EOF
    set -x

    # Install curl, ca-certificates, and B4CKSP4CE Root CA
    apt update
    apt install -y curl ca-certificates
    mkdir -p /usr/share/ca-certificates/bksp
    curl -fSsl https://ca.bksp.in/root/bksp-root.crt -o /usr/share/ca-certificates/bksp/B4CKSP4CE_Root_CA.crt
    echo "bksp/B4CKSP4CE_Root_CA.crt" | tee -a /etc/ca-certificates.conf
    update-ca-certificates

    # Determine WALG download URL and digest depending on architecture
    ARCH=$(uname -m)
    if [ "$ARCH" = "aarch64" ]; then
        WALG_URL="https://github.com/wal-g/wal-g/releases/download/v3.0.8/wal-g-pg-22.04-aarch64"
        WALG_SHA256="794d1a81f0c27825a1603bd39c0f2cf5dd8bed7cc36b598ca05d8d963c3d5fcf"
    elif [ "$ARCH" = "x86_64" ]; then
        WALG_URL="https://github.com/wal-g/wal-g/releases/download/v3.0.8/wal-g-pg-22.04-amd64"
        WALG_SHA256="f30544c5ce93cf83b87578e3c4a2e9c0e0ffc3d160ef89ecddaf75f397d98deb"
    else
        echo "Unsupported architecture"
        exit 1
    fi

    # Download wal-g and verify its checksum
    curl -fsSL -o "/usr/local/bin/wal-g" "$WALG_URL"
    echo "${WALG_SHA256}  /usr/local/bin/wal-g" | sha256sum -c -
    chmod +x /usr/local/bin/wal-g

    # Tidy up
    apt clean
    rm -rf /var/lib/apt/lists/* /var/cache/* /var/log/*
EOF

# Define B4CKSP4CE-specific environment variables
ENV \
    # Prefer unix socket connection for wal-g 
    PGHOST=/var/run/postgresql \
    # Set Governance Object Lock for 10 years by default
    S3_RETENTION_MODE=GOVERNANCE \
    S3_RETENTION_PERIOD=315569520 \
    # Set default compression method to zstd
    WALG_COMPRESSION_METHOD=zstd \
    # Use Yandex Cloud as default storage
    AWS_ENDPOINT=https://storage.yandexcloud.net

# Enable pg_isready healthcheck
HEALTHCHECK \
    --interval=10s \
    --start-period=10s \
    --timeout=5s \
    --retries=5 \
    CMD [ "pg_isready" ]

# Copy wal-g wrapper, ensuring it is executable
COPY --chmod=0755 ./peg.sh /usr/local/bin/peg

# Copy includeable WAL-G PostgreSQL config
COPY ./config/walg.conf /etc/postgresql/walg.conf

# Copy initdb scripts that wire the WAL-G config and take an initial backup
COPY --chmod=0755 ./initdb/90-walg-config.sh ./initdb/91-walg-initial-backup.sh /docker-entrypoint-initdb.d/

# Drop privileges to postgres user
USER postgres
