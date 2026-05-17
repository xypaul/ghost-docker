# Deploying this compose on Coolify

This fork of [TryGhost/ghost-docker](https://github.com/TryGhost/ghost-docker) is
deployed via [Coolify](https://coolify.io/) (which uses Traefik as its reverse
proxy) rather than the upstream's Caddy. The notes below capture the
fork-specific deployment behaviour so future-you (and contributors) don't have
to rediscover them.

## Architecture overview

```
Cloudflare (Full Strict) → Traefik (coolify-proxy) → service container
                                                     ├── ghost:2368
                                                     ├── traffic-analytics:3000   (analytics profile)
                                                     └── activitypub:8080         (activitypub profile)
```

- TLS termination at Traefik uses a **Cloudflare Origin Certificate** mounted
  via `/data/coolify/proxy/dynamic/cloudflare-origin-certs.yaml` (NOT
  Let's Encrypt; the `tls.certresolver: letsencrypt` label is decorative).
- All services are auto-attached by Coolify to its **project network**
  (named after `COOLIFY_RESOURCE_UUID`) in addition to whatever networks
  the compose declares.
- The Caddy service from upstream is removed (`441bd8c`) — Traefik does the
  reverse-proxying instead, which means **the Caddy snippets are not
  loaded** and equivalent routes have to live as Traefik labels on each
  service.

## Required env vars (Coolify UI)

| Variable | Value | Notes |
|---|---|---|
| `DOMAIN` | `blog.xy.co` | Used in Traefik rules and Ghost URLs |
| `DATABASE_ROOT_PASSWORD` | (secret) | Root creds, only consumed by MySQL init |
| `DATABASE_PASSWORD` | (secret) | The `ghost` user password |
| `TINYBIRD_*` | (4 vars) | See `TINYBIRD.md` |
| `COMPOSE_PROFILES` | `analytics,activitypub` | Required to start the optional services |
| `mail__*` | SMTP details | Mailgun in this deployment |

`ACTIVITYPUB_TARGET` is **not** consumed by Ghost in this setup — it was
only referenced by the (removed) Caddy snippet. Leave it unset.

## Traefik labels: required for Coolify+Ghost

Every service that needs to be reachable through Traefik has to set
`traefik.docker.network=${COOLIFY_RESOURCE_UUID:-}`. Without it, Traefik's
Docker provider randomly picks one of the multiple networks the service is on
(the user-declared `ghost_network` + the Coolify project network) and 504s
every request when it lands on the network it isn't joined to. See
[PR #1](https://github.com/xypaul/ghost-docker/pull/1) for the full diagnosis.

The Caddy routing snippets (`caddy/snippets/TrafficAnalytics`,
`caddy/snippets/ActivityPub`) had to be ported to Traefik labels on the
`traffic-analytics` and `activitypub` services. See
[PR #3](https://github.com/xypaul/ghost-docker/pull/3) for the labels and the
reasoning (in short: `stripprefix` for analytics, no prefix-strip for
activitypub, both at `priority=100` so they win the Ghost catch-all).

## One-shot containers need `restart: no`

Coolify defaults services to `restart: unless-stopped`, which restarts even on
clean (exit 0) exits. For `tinybird-deploy`/`tinybird-sync`/`tinybird-login`/
`activitypub-migrate` — all one-shot jobs that exit 0 on success — this causes
a restart loop and any service that `depends_on` them with
`condition: service_completed_successfully` (notably Ghost) waits forever and
stays in `Created`. See [PR #2](https://github.com/xypaul/ghost-docker/pull/2).
All four are now explicitly `restart: no` in `compose-prod.yml`.

## `MYSQL_MULTIPLE_DATABASES` only runs on fresh init

`mysql-init/create-multiple-databases.sh` runs **only the first time** MySQL
initialises a new data directory. If you add a service (e.g. `activitypub`)
that needs an extra database after MySQL has already been initialised, the
extra DB is never created and you'll see:

```
error: Error 1044: Access denied for user 'ghost'@'%' to database 'activitypub'
```

Fix it manually once:

```bash
ROOTPASS=$(grep ^DATABASE_ROOT_PASSWORD= /data/coolify/applications/<UUID>/.env | cut -d= -f2-)
DB=$(docker ps --filter 'name=db-<UUID>' --format '{{.Names}}' | head -1)
docker exec -e MYSQL_PWD="$ROOTPASS" "$DB" mysql -u root -e \
  "CREATE DATABASE IF NOT EXISTS \`activitypub\`;
   GRANT ALL ON \`activitypub\`.* TO 'ghost'@'%';
   FLUSH PRIVILEGES;"
```

Then trigger a Coolify redeploy so `activitypub-migrate` re-runs against the
now-existing DB.

## First-time Tinybird setup

The interactive `tinybird-login` (`tb login --method code`) cannot run under
Coolify's non-interactive deploy. SSH onto the host and run it once against
the same compose project:

```bash
cd /data/coolify/applications/<UUID>
docker compose -f docker-compose.yaml --env-file .env --profile analytics \
  run --rm tinybird-login
```

Follow the printed URL → paste the code in browser → paste the auth code back.
This writes `/home/tinybird/.tinyb` into the `tinybird-home` Docker volume;
subsequent `tinybird-sync` and `tinybird-deploy` runs (which happen
automatically on every redeploy when `analytics` is in `COMPOSE_PROFILES`)
will find it and exit 0.

## Ghost feature flags

The `web_analytics` setting in Ghost's `settings` table is enabled in this
deployment — it controls whether Ghost embeds the `ghost-stats.min.js` tracker
in the HTML. The setting alone is not enough to route the tracker POSTs;
that's the job of the Traefik label on `traffic-analytics` (above).

## Cheat sheet: where things live on the server

| Thing | Path |
|---|---|
| App working dir | `/data/coolify/applications/<UUID>/` |
| Rendered compose | `…/docker-compose.yaml` |
| Coolify-managed env | `…/.env` |
| Ghost content + logs | `…/data/ghost/` |
| MySQL data | `…/data/mysql/` |
| Tinybird `.tinyb` auth | `/var/lib/docker/volumes/<UUID>_tinybird-home/_data/.tinyb` |
| Tinybird synced schema | `/var/lib/docker/volumes/<UUID>_tinybird-files/_data/` |
| Traefik CF Origin Cert | `/data/coolify/proxy/certs/xy.cert` |
| Traefik dynamic config | `/data/coolify/proxy/dynamic/` |
