# ScullyOS Quickstart

**Production-grade backend for startups. On day one.**

Spin up the ScullyOS platform on a single host with four commands. Identity, authorization, a backoffice with a built-in AI agent — all auto-MCPified and ready to build on.

**Before you run:**

- **Docker must be running.** Start Docker Desktop (or your Docker daemon) before invoking the wrappers.
- **Windows users: use a bash terminal** — Git Bash or WSL. The `scripts/sh/*.sh` wrappers are POSIX shell and won't run from `cmd.exe` / PowerShell directly.
- **Default LLM provider is Google Gemini** — swappable to Anthropic (or left disabled) via `LLM_PROVIDER` / `LLM_MODEL` / `LLM_API_KEY` in `.env`; see [Enabling the Admin Agent](#enabling-the-admin-chat-panel-optional).
- **Safe to re-run on failure.** `docker compose up -d` is idempotent — if `up` fails partway (network blip, slow image pull, mistyped env), fix the cause and run `./scripts/sh/up.sh` again; already-created containers are reused.

```bash
git clone https://github.com/scullyos/quickstart.git
cd quickstart
cp .env.example .env    # then edit .env — at minimum set SEED_USER_NAME / SEED_USER_PASSWORD before the first up
./scripts/sh/up.sh
```

**Use the `./scripts/sh/*` wrappers, not bare `docker compose`.** Image versions live in a checked-in `.env.base` so a `git pull` delivers new versions automatically; the wrappers stitch `.env.base` + your `.env` together via `docker compose --env-file ... --env-file ...`. Calling `docker compose up -d` on its own won't see the version pins and will fail to resolve the image tags. If you must invoke compose directly, see [Calling docker compose directly](#calling-docker-compose-directly).

After ~2 min the stack is up. Open:

- **Web app:** http://127.0.0.1:18080
- **Kibana (logs):** http://127.0.0.1:15601
- **bo-orc API (direct):** http://127.0.0.1:18001

> Use `127.0.0.1`, not `localhost`. `localhost` resolves to both `::1` and
> `127.0.0.1`; browsers generally try IPv6 first; Docker Desktop's IPv6
> forwarding is unreliable on Windows and Linux's native Docker doesn't bind
> IPv6 unless the daemon is started with `--ipv6`. `127.0.0.1` works
> identically on every host. Override the bind via `HOST_BIND` in `.env` if
> you need a different address.

Log in to the web app with the seed admin (set in `.env`).

---

## What's Running

| Service                    | Role                                                         |
| -------------------------- | ------------------------------------------------------------ |
| `scullyosapp`              | React/Vite SPA, served by nginx                              |
| `bo-orc-ms`                 | Backoffice entrypoint API — what the SPA calls               |
| `person-ms`                | People + auth provider service                               |
| `authorization-ms`         | Roles, Permissions and resources based authorization service |
| `mysql`                    | Single MySQL 8 instance, `main_db` schema                    |
| `elasticsearch` + `kibana` | Log storage + viewer                                         |
| `fluent-bit`               | Tails docker container logs and ships them to ES             |

Every service API is automatically exposed as an MCP tool. The backoffice agent can operate all services out of the box.

Full architecture in [docs/scullyos-quickstart-design.md](../docs/scullyos-quickstart-design.md).

### Architecture

```
┌──────────────────────┐  ┌──────────────────────┐
│  Your Application    │  │  Backoffice + Agent   │
│  (calls APIs or MCP) │  │  (calls APIs or MCP)  │
└──────────┬───────────┘  └──────────┬────────────┘
           │                         │
┌──────────▼─────────────────────────▼────────────┐
│              ScullyOS Services                  │
│  ┌──────────────┐  ┌───────────────────┐        │
│  │   Person      │  │  Authorization    │        │
│  │   Service     │  │  Service          │        │
│  └──────────────┘  └───────────────────┘        │
│                                                 │
│  ┌─────────────────────────────────────┐        │
│  │         Operating Layer             │        │
│  │  Logging · Auditing · Config · MCP  │        │
│  └─────────────────────────────────────┘        │
└─────────────────────────────────────────────────┘
```

---

## Prerequisites

- Docker Engine 20.10+ (or Docker Desktop) with `compose` **v2.24+** (Jan 2024 — needed for stacked `--env-file` flags). Check with `docker compose version`.
- Git
- ~3 GB free disk space (mysql + ES indices + image layers)
- Ports `18080`, `18001`, `15601` free on `127.0.0.1` (override in `.env` if not — see `HOST_BIND` / `HOST_PORT_*`)

---

## First-Run Flow

1. `cp .env.example .env`, then open `.env` and edit values you care about (seed admin credentials, Kibana password, host bind/ports, `LLM_API_KEY` — leave the shipped placeholder to keep the agent disabled, or replace it with a real key to enable the Backoffice AI Agent). Image versions are NOT in `.env` — they ship in `.env.base` (checked-in, refreshed by `git pull`). The shipped defaults boot a working stack but use a placeholder admin email and a well-known password — change them before the first `up -d` since the bootstrap migration is idempotent.
2. `./scripts/sh/pull.sh` — downloads four ScullyOS images plus mysql, ES, Kibana, fluent-bit, curl. ~30-60 s on a decent connection, ~2 GB.
3. `./scripts/sh/up.sh` — starts everything in dependency order:
   - mysql comes up healthy
   - three `*-db-init` one-shots run migrations (creates schema, seeds admin user + password)
   - person-ms / authorization-ms / bo-orc-ms come up healthy
   - elasticsearch + es-setup + kibana + kibana-setup + fluent-bit come up
   - scullyosapp comes up last (waits for bo-orc healthy)
4. `docker compose --env-file ./.env.base --env-file ./.env ps` — every service should be `Up` or, for `*-db-init` and `*-setup`, `Exited (0)`. (See [Calling docker compose directly](#calling-docker-compose-directly) to set `COMPOSE_ENV_FILES` once and skip the flags.)

### Logging In

**The platform (web app)**

The seed admin's email and password come from your `.env`:

- **Email:** value of `SEED_USER_NAME` (default `your-email-here@scullyos.ai`)
- **Password:** value of `SEED_USER_PASSWORD` (default `ChangeMeImmediately!1`)

The `BootstrapAdminPassword` migration consumes these on first boot of `person-ms` and seeds the credential row. Change them in `.env` BEFORE the first `up -d` to set custom values; changes afterwards have no effect (the migration is idempotent).

**Kibana**

- **Username:** value of `KIBANA_USERNAME` (default `scullyos`)
- **Password:** value of `KIBANA_PASSWORD` (default `changeme-kibana-password`)

These same credentials back an Elasticsearch superuser created by `setup/es-setup.sh` on first boot — see the comment in `.env` for the full mechanism.

---

## Try It Out

You're up and running. Here's how to see what ScullyOS actually does.

### 1. Explore the UI

Open the backoffice at `http://127.0.0.1:18080` and try the following:

**Users & Identity**

- Create a new user (give them a name and email)
- Add a tag to the user (e.g. `vip`, `beta-tester`)
- Add a custom attribute (e.g. `Name: department, Type: Enum, Values: Division, Group, Team`)

**Roles & Permissions**

- Create a new role (e.g. `editor`)
- Grant permission to the role (e.g. `Role: editor, Permission:  create, Resource: file`)
- Assign the role to your user

### 2. Now Do It All With the Agent

Open the agent chat in the backoffice and try these prompts:

```
Create a user called Jane Smith with email jane@example.com
```

```
Add the tag "beta-tester" to Jane Smith
```

```
Assign the viewer role to Jane Smith
```

```
Which user created Jane Smith and when
```

Everything the UI can do, the agent can do (and even more). Every action is logged and auditable. This is the agentic core — your system's built-in agent that operates all services through auto-generated MCP tools.

**Bonus:** Using the UI try to create another user with the same email, when you get the error toast, click the error number and you will see the full log and error in Kibana!

### 3. Check the Logs

Click the **Logging** link in the backoffice (or open Kibana directly at `http://127.0.0.1:15601`).

Find the user you just created — you'll see the full audit trail: who created them, what roles were assigned, what the agent did, with full request context. This is structured, searchable, production-grade logging — not `console.log`.

### 4. Build on Top

Your own services can call the Person and Authorization APIs directly Or connect via MCP, every service endpoint is available as a tool for your own agents. Build your services on top of ScullyOS, and your agents get identity and authorization for free.

---

## Configuration

All knobs live in `.env` (this directory). Common edits:

### Host bind address

By default the stack publishes its host-facing ports on `127.0.0.1` only —
not the LAN — and the SPA's runtime config points at the same address. If
you need to reach the stack from another machine (e.g. a VM host, a
phone on the same network), override the bind:

```bash
HOST_BIND=0.0.0.0           # listen on every interface
# or
HOST_BIND=192.168.1.42      # listen on a specific NIC
```

`HOST_BIND` is consumed by both the `ports:` entries and the SPA env vars
in `docker-compose.yml`, so the SPA, the API, and Kibana all stay on the
same origin (no CORS surprises).

### Host ports

If `18080` / `18001` / `15601` collide with something on your machine:

```bash
HOST_PORT_FRONTEND=28080
HOST_PORT_BO_ORC=28001
HOST_PORT_KIBANA=25601
```

The browser-facing URLs the SPA calls are derived from these in `docker-compose.yml`, so you only edit one place.

### Image versions

Image version pins live in **`.env.base`** (checked into the repo, refreshed by `git pull`) — not in your `.env`:

```bash
VERSION_PERSON=0.0.57
VERSION_AUTHORIZATION=0.0.51
VERSION_BO_ORC=0.0.68
VERSION_SCULLYOSAPP=0.0.50
```

Normal flow when a new release ships: `git pull && ./scripts/sh/pull.sh && ./scripts/sh/up.sh`. No env editing required.

**Pinning a specific version locally** (e.g. for a rollback): add a `VERSION_*` line to your `.env`. The wrappers pass `.env` after `.env.base` so same-named vars in `.env` override `.env.base`. Remove the override later to flow with `git pull` again.

### Enabling the Admin Agent (optional)

The Admin Agent uses an LLM to drive the agent. **It's optional.** The shipped `.env.example` sets `LLM_API_KEY` to a placeholder so the stack boots without any LLM credentials; in that state the chat panel stays hidden and the SPA shows a dismissible notice explaining how to enable it.

To turn it on, replace the placeholder `LLM_API_KEY` in `.env` with a real key. Defaults for `LLM_PROVIDER` / `LLM_MODEL` already point at Google's Gemini Flash; switch the trio if you'd rather use Anthropic:

```bash
# Google (default) — get a key at https://aistudio.google.com/apikey
LLM_PROVIDER=google
LLM_MODEL=gemini-2.5-flash
LLM_API_KEY=AIza...

# OR Anthropic
# LLM_PROVIDER=anthropic
# LLM_MODEL=claude-haiku-4-5-20251001
# LLM_API_KEY=sk-ant-api03-...
```

**Your key never leaves your machine.** It's read by your local `bo-orc-ms` container and used to call the LLM provider directly. The platform does not phone home and does not relay your key anywhere.

After replacing the key, recreate `bo-orc-ms` so it picks up the new env:

```bash
./scripts/sh/up.sh --force-recreate --no-deps bo-orc-ms
```

`--no-deps` is important: without it, compose walks the `depends_on` chain and also recreates mysql / person-ms / authorization-ms (and the db-init one-shots). With `--no-deps` only `bo-orc-ms` is touched.

To go back to the disabled state, restore the placeholder value (copy it back from `.env.example`) and recreate `bo-orc-ms` the same way.

### Sending YOUR containers' logs to Kibana

Fluent Bit ships logs from any container whose `container_name` matches a regex in `.env`. Default is just the three platform MSs. To include your own containers:

```bash
# Allows logs from `my-app` AND `worker-*` containers in addition to the defaults.
FLUENT_BIT_CONTAINER_INCLUDE_REGEX=^(person|authorization|bo-orc)-ms$|^my-app$|^worker-.+$
```

Restart fluent-bit for the change to take effect:

```bash
./scripts/sh/up.sh --force-recreate --no-deps fluent-bit
```

Logs appear in Kibana under index pattern `dev-ms-logs-*` once `microservices-logs` is selected.

Your services get structured, searchable, production-grade logging — just by adding their container name to a regex. No logging library to integrate. No ELK stack to configure. It's already running.

---

## Wrapper Scripts

`scripts/sh/` ships the entry points for the most common compose actions. **They're load-bearing, not optional** — they're how `.env.base` (image versions, checked-in) and `.env` (your local config) get stacked into one compose invocation. Without them, compose only sees `.env` and can't resolve image tags. They also report wall-clock time at the end (`Xm YYs`), useful for benchmarking on different hardware / connections.

```bash
./scripts/sh/pull.sh            # docker compose pull
./scripts/sh/up.sh              # docker compose up -d
./scripts/sh/up.sh --wait       # ...and block until all healthchecks pass
./scripts/sh/down.sh            # docker compose down (volumes KEPT)
./scripts/sh/down.sh --wipe     # docker compose down -v (volumes wiped)
```

Sample output:

```
▶ compose pull — starting...
... [normal docker compose output streams here]
✔ compose pull — done in 1m 27s (exit 0)
```

The underlying timing utility is `scripts/sh/timed.sh` and works for any command:

```bash
./scripts/sh/timed.sh "ES warm" curl -sf 'http://127.0.0.1:9200/_cluster/health?wait_for_status=green'
```

All four scripts forward extra args to docker compose, so e.g. `./scripts/sh/up.sh person-ms` brings up just person-ms (still timed).

### Calling docker compose directly

If you need to invoke `docker compose` without a wrapper (e.g. `logs`, `ps`, `restart`), pass both env files explicitly so version interpolation resolves:

```bash
docker compose --env-file ./.env.base --env-file ./.env <subcommand>
```

Or export `COMPOSE_ENV_FILES` once per shell (compose v2.24+):

```bash
export COMPOSE_ENV_FILES=./.env.base:./.env
docker compose ps        # now works without --env-file flags
docker compose logs -f
```

## Common Operations

> The bare `docker compose ...` examples below assume you've exported `COMPOSE_ENV_FILES=./.env.base:./.env` in this shell, or are prefixing each call with `--env-file ./.env.base --env-file ./.env`. See [Calling docker compose directly](#calling-docker-compose-directly).

```bash
# Tail all logs
docker compose logs -f

# Tail one service's logs
docker compose logs -f bo-orc-ms

# Restart one service after editing its env file (--no-deps keeps compose
# from also recreating the depends_on chain)
./scripts/sh/up.sh --force-recreate --no-deps bo-orc-ms

# Stop everything (keeps volumes — your data persists)
./scripts/sh/down.sh

# Stop everything AND wipe volumes (fresh start; admin re-seeded on next up)
./scripts/sh/down.sh --wipe
```

---

## Persistence — What Survives What

All long-lived state lives in named docker volumes (`mysql-data`, `es-data`). Containers come and go; data stays — until you explicitly wipe it.

| Action                                                        | DB rows   | Kibana saved views / dashboards / index patterns | Container instances |
| ------------------------------------------------------------- | --------- | ------------------------------------------------ | ------------------- |
| `docker compose restart <svc>`                                | survive   | survive                                          | restart             |
| `docker compose stop && docker compose start`                 | survive   | survive                                          | same containers     |
| `docker compose down && docker compose up -d`                 | survive   | survive                                          | recreated           |
| `docker compose pull && docker compose up -d` (image upgrade) | survive   | survive                                          | recreated           |
| **`docker compose down -v`**                                  | **wiped** | **wiped**                                        | recreated           |

### Where state actually lives

- **MySQL data** (people, auth roles, audit log, agent sessions): `mysql-data` named volume → `/var/lib/mysql` in the container.
- **Kibana saved objects** (saved searches, dashboards, visualizations, index patterns, advanced settings, space settings): all stored in Elasticsearch `.kibana_*` indexes. Persisted by the `es-data` named volume → `/usr/share/elasticsearch/data` in the elasticsearch container. Kibana itself is stateless.
- **Elasticsearch indexes** (`dev-ms-logs-*` from Fluent Bit, `.kibana_*` from Kibana, the `microservices-template` index template): all in `es-data`.

### One thing worth pinning yourself: `KIBANA_ENCRYPTION_KEY`

If you plan to use Kibana **alerting**, **action connectors that store credentials**, or **reporting** — set `KIBANA_ENCRYPTION_KEY` in `.env` to a stable value before first `up -d`:

```bash
# generate once and paste into .env
openssl rand -hex 32
```

```
# in quickstart/.env
KIBANA_ENCRYPTION_KEY=<the-hex-string-from-openssl>
```

Without this, Kibana auto-generates an encryption key in memory each time the container is recreated. Encrypted saved objects from the previous instance then become undecryptable. **For typical Discover / Visualize / Dashboard usage (no alerting, no stored connector creds): you can safely leave it blank — none of that is encrypted.**

### Backing up

```bash
# stop the stack so the on-disk state is consistent
docker compose stop

# back up both volumes by tar-streaming through a throwaway container
docker run --rm -v scullyos_mysql-data:/data -v "$(pwd)":/backup alpine tar czf /backup/mysql-data-$(date +%F).tar.gz -C /data .
docker run --rm -v scullyos_es-data:/data    -v "$(pwd)":/backup alpine tar czf /backup/es-data-$(date +%F).tar.gz    -C /data .

docker compose start
```

Restore: reverse the tar, with the stack stopped + volumes empty (`docker compose down -v` first).

---

## Troubleshooting

- **`scullyosapp` container exits immediately** — usually a missing/wrong env var. Check `docker compose logs scullyosapp`. Re-confirm `HOST_PORT_BO_ORC` matches the URL the SPA gets via `window.__env__`.
- **`person-ms` exits with a DB error** — `mysql` may not be healthy yet. The `depends_on: condition: service_healthy` handles this on a normal `up`, but a `restart person-ms` alone won't wait. Use `./scripts/sh/up.sh` to re-trigger the dependency wait.
- **Kibana shows no logs** — check fluent-bit logs (e.g. `./scripts/sh/up.sh --no-deps fluent-bit` to recreate, then inspect via `docker logs fluent-bit`). The container regex (`FLUENT_BIT_CONTAINER_INCLUDE_REGEX`) controls which containers are shipped. Default is the three MSs.
- **Port already in use** — override `HOST_PORT_*` in `.env`, then `./scripts/sh/up.sh` to apply.
- **`docker compose` says image is not pinned / `:` after empty tag** — you're invoking compose without seeing `.env.base`. Either use the wrapper scripts, export `COMPOSE_ENV_FILES=./.env.base:./.env`, or pass `--env-file ./.env.base --env-file ./.env` explicitly.
- **MySQL or ES port conflict** — both are commented out in the compose file by default. Uncomment the `ports:` block under each only if you need direct access.

---

## What's NOT Included

- TLS / HTTPS — quickstart is plaintext; do not expose it to the internet.
- Replicas / HA — single instance per service. For prod, use the gitops k8s deploy.
- Telemetry — `USE_APM=no` for all services. No OTel collector in this stack.
- Outbound event publishing — Localstack is NOT included; `IS_PUBLISHER=no` for the publishing services.

For the full design, including how the quickstart relates to the production k8s deployment, see [docs/scullyos-quickstart-design.md](../docs/scullyos-quickstart-design.md).

---

## What's in the Full Version

The quickstart gives you the foundation. The full ScullyOS platform adds:

**More services** — Email, search, feature flags, organizations/spaces — all with the same provider-agnostic architecture and auto-MCPification.

**Provider portability** — Every service is a wrapper. Switch from one provider to another by changing configuration. No code changes.

**Full operating layer** — OpenTelemetry, GitOps CD, Terraform scripts, CLS-level DB transactions, Husky, enforced API guidelines.

**Source code access** — Own and extend every service. Add providers, customize behavior, deploy on your cloud.

Interested? Visit [scullyos.ai](https://scullyos.ai) or reach out for Design Partner access.

---

## License

ScullyOS quickstart is free to use for building your own products. You may not redistribute, resell, or offer the ScullyOS containers as part of a product or service you provide to others.

---

**ScullyOS** — Production-grade backend for startups. On day one.

[scullyos.ai](https://scullyos.ai)
