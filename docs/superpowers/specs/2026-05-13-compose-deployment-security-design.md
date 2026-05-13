# Compose Deployment And Network Security Design

## Goal

Replace the interactive one-click deployment workflow with Docker Compose and move deployment-specific values into a `.env` file, while fixing concrete network-facing security issues.

## Scope

The deployment should use a single container, matching the existing image layout and persistent volumes. The default behavior should publish all required services to the public host interface:

- ZeroTier transport: `ZT_PORT` over TCP and UDP
- ztncui management UI: `API_PORT` over TCP
- planet/moon file download service: `FILE_SERVER_PORT` over TCP

The one-click script should no longer be the documented install path. Compose commands become the supported install, upgrade, restart, uninstall, log, and password reset workflow.

## Configuration

Add `.env.example` as the documented configuration template. Operators copy it to `.env` and edit runtime values there. `.env` must not be committed.

Required dynamic values:

- `DOCKER_IMAGE`
- `IP_ADDR4`
- `IP_ADDR6`
- `ZT_PORT`
- `API_PORT`
- `FILE_SERVER_PORT`
- `FILE_KEY`
- host data directories for `dist`, `ztncui`, `zerotier-one`, and config

The compose file should read all dynamic values through variable substitution and pass the values into the container environment.

## Security Fixes

The file download service currently accepts a URL path and joins it to `/app/dist` without validating the resolved path. It must resolve and validate paths so a request cannot escape `/app/dist`.

The file download key should come from `FILE_KEY` when provided. If not provided, the service should reuse an existing `/app/config/file_server.key`; only if neither exists should it generate a random key and persist it.

The file download key comparison should avoid direct string equality. The service should use a timing-safe comparison after validating equal byte lengths.

The file download service should only accept `GET` and `HEAD`. Other methods return `405`.

The entrypoint should quote paths and write config consistently from environment variables. The ztncui UI may continue binding all interfaces because the required default is public exposure.

## Documentation

Update Chinese and English README deployment sections so Compose is the primary path:

- install Docker and Docker Compose plugin
- clone the repository
- copy `.env.example` to `.env`
- edit IP, ports, and `FILE_KEY`
- run `docker compose up -d`
- view generated files in the configured dist directory
- reset password with a Compose `exec` command
- upgrade with `docker compose pull && docker compose up -d`
- uninstall with `docker compose down`

Remove the old interactive script workflow from the main deployment path and avoid recommending public access without changing the default public exposure requirement.

## Verification

Add a lightweight static security check script that validates:

- compose file exists and uses environment variables for ports, image, and volumes
- `.env.example` contains the required keys
- `.gitignore` excludes `.env`
- the file server contains path resolution checks, timing-safe comparison, method restrictions, and persisted key behavior

Run shell syntax checks for modified shell scripts and Node syntax checks for the file server.
