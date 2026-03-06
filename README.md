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
      DATABASE_URL: postgresql://root:toor@postgres/app
    depends_on:
      - postgres

  postgres:
    image: ghcr.io/b4ck5p4c3/peg:18
    environment:
      # Default user and database to be created on a first run.
      POSTGRES_DB: app
      POSTGRES_USER: root
      POSTGRES_PASSWORD: toor

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

## FAQ

### How to disable Object Lock?

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
  localhost/peg:18 \
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
  localhost/peg:18 \
  peg restore-pitr "2024-06-01T12:00:00Z"
```
