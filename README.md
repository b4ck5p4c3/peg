# Peg

Peg is an elegant PostgreSQL container with built-in WAL-G backup.

> [!IMPORTANT]
> Peg is a B4CKSP4CE-specific project and is not intended for general use.

We created Peg to simplify the process of running small PostgreSQL instances.

Peg is designed to be an almost drop-in replacement for the official PostgreSQL image.
While we prioritized ease of use over some flexibility and performance aspects,
it still provides a robust solution for small database needs.

```yaml
services:
  app:
    image: acme.corp/awesome-app:latest
    environment:
      DATABASE_URL: postgresql://postgres:postgres@postgres/app
    depends_on:
      - postgres

  postgres:
    image: ghcr.io/b4ck5p4c3/peg:18
    environment:
      # Default user and database to be created on a first run.
      POSTGRES_DB: app
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres

      # Prefix for the backup files within the bucket.
      # Generally, use your app name.
      BACKUP_PREFIX: dev-awesome-app

      # Optional path to a PGP key.
      # For encryption (push) this should be your public key.
      # Private key only required for backup decryption (pull).
      WALG_PGP_KEY_PATH: /run/secrets/walg_pgp_key

      # Credentials for a service account with storage.uploader role.
      AWS_ACCESS_KEY_ID: ...
      AWS_SECRET_ACCESS_KEY: ...

      # BKSP Healthcheck UUID for WAL archiving job.
      HEALTHCHECKS_UUID: 725ac523-9c1e-4709-9b7f-142e27aaba4b

    volumes:
      - postgres:/var/lib/postgresql

volumes:
  postgres:
```

## Configuration

Peg supports environmental configuration variables from both
[WAL-G](https://wal-g.readthedocs.io/) and [PostgreSQL image](https://hub.docker.com/_/postgres).

But it also introduces additional parameters and alternates some defaults:

### Storage

| Variable | Description | Required? |
| --- | --- | --- |
| BACKUP_PREFIX | Prefix for the backup files within the default bucket | One of `BACKUP_PREFIX` or `WALG_S3_PREFIX` must be set |
| WALG_S3_PREFIX | Full S3 prefix for the backup files, including bucket name (e.g. `s3://my-bucket/backups`) | One of `BACKUP_PREFIX` or `WALG_S3_PREFIX` must be set |
| S3_ENDPOINT | S3 API endpoint URL | No, defaults to `https://storage.yandexcloud.net` |
| S3_RETENTION_MODE | S3 Object Lock retention mode | No, defaults to `GOVERNANCE` |
| S3_RETENTION_PERIOD | S3 Object Lock retention period in seconds | No, defaults to `315569520` (10 years) |
| WALG_COMPRESSION_METHOD | Compression method for the backup files | No, defaults to `lzma` |

### Status reporting

| Variable | Description | Required? |
| --- | --- | --- |
| HEALTHCHECKS_UUID | Healthcheck.io WAL archive check UUID | No. |
| HEALTHCHECKS_BASE_URL | Healthchecks.io Base URL | No, defaults to `https://hc.bksp.in/ping` |
| SENTRY_URL | Webhook URL for [Sentry Cron Monitoring](https://docs.sentry.io/product/crons/getting-started/http/) | No. |

## FAQ

### How to disable Object Lock?

As a safety measure, Peg by default enables Object Lock in
[Governance Mode](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html#object-lock-retention-modes)
on all backup objects, preventing them from being accidentally or maliciously deleted for a certain period of time (default: 10 years)
unless you have a special bypass permission.

If you want disable Object Lock at all, set the `S3_RETENTION_PERIOD` environment variable to `-1`:

```yaml
services:
  postgres:
    environment:
      # Object Lock is enabled by default; set to -1 to disable
      S3_RETENTION_PERIOD: -1
```

### Make a physical (full) backup

Peg doesn't make full backups on its own schedule, but you can trigger them manually using the `backup` command.

```bash
docker compose exec -it postgres peg backup
```

### Recovery

There are two recovery modes available:

#### Full

Restores the latest backup and replays all available WAL files to bring the database up to date.

```bash
# Shut the existing Postgres instance down (if running)
docker compose stop

# Trigger restore in a separate container
docker run \
  --rm \
  --env-file .env.peg \
  -v postgres:/var/lib/postgresql \
  
  # Following configuration is only required if you used encryption for your backups.
  -v /home/user/gpg-secret-key:/run/secrets/walg_pgp_key:ro \
  -e WALG_PGP_KEY_PATH=/run/secrets/walg_pgp_key \
  -e WALG_PGP_KEY_PASSPHRASE=1234 \

  ghcr.io/b4ck5p4c3/peg:18 \
  peg restore
```

#### Point-in-Time

Restores the latest backup and replays WAL files up to a specified timestamp.

```bash
# Shut the existing Postgres instance down (if running)
docker compose stop

# Trigger restore in a separate container
docker run \
  --rm \
  --env-file .env.peg \
  -v postgres:/var/lib/postgresql \

  # Following configuration is only required if you used encryption for your backups.
  -v /home/user/gpg-secret-key:/run/secrets/walg_pgp_key:ro \
  -e WALG_PGP_KEY_PATH=/run/secrets/walg_pgp_key \
  -e WALG_PGP_KEY_PASSPHRASE=1234 \

  ghcr.io/b4ck5p4c3/peg:18 \
  peg restore-pitr "2024-06-01T12:00:00Z"
```

### Additional configuration

You may sideload additional configuration files by mounting them into `/etc/postgresql/postgresql.conf.d/`
