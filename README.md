# Peg

Peg is an elegant PostgreSQL container with built-in WAL-G backup.

> [!IMPORTANT]
> Peg is a B4CKSP4CE-specific project and is not intended for general use.

We created Peg to simplify the process of running small PostgreSQL instances.

Peg is designed to be an almost drop-in replacement for the official PostgreSQL image.
While we prioritized ease of use over some flexibility and performance aspects,
it still provides a robust solution for small database needs.

```yaml
service:
  app:
    image: acme.corp/awesome-app:latest
    environment:
      DATABASE_URL: postgresql://root:toor@db/app
    depends_on:
      - db

  db:
    image: ghcr.io/b4ck5p4c3/peg:16
    environment:
      # Default user and database to be created on a first run.
      POSTGRES_DB: "app"
      POSTGRES_USER: "root"
      POSTGRES_PASSWORD: "toor"

      # Prefix for the backup files within the bucket.
      # Generally, use your app name.
      BACKUP_PREFIX: "dev-awesome-app"

      # This should be a 32-byte random value encoded in base64.
      # Use `openssl rand -base64 32` to generate one.
      WALG_LIBSODIUM_KEY: "..."

      # Credentials for a service account with storage.uploader role.
      AWS_ACCESS_KEY_ID: "..."
      AWS_SECRET_ACCESS_KEY: "..."

      # BKSP Healthcheck UUID for WAL archiving job. 
      HEALTHCHECKS_UUID: "725ac523-9c1e-4709-9b7f-142e27aaba4b"

    volumes:
      - postgres:/var/lib/postgresql/data

volumes:
  postgres:

```
