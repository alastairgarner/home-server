# Vault MCP

The root Compose file includes Vault in normal `docker compose up -d` startup;
no profile is required. Prepare the private auth config before first startup.
Missing/invalid config prevents Vault from starting successfully.

The application is named Vault. The `brain` Compose service, hostname, local
paths, volume names, and MCP tool names are unchanged.

`restart: unless-stopped` restarts the container after a process exit/crash and
when Docker starts after reboot, unless explicitly stopped. A manually stopped
container stays stopped across Docker restarts until started again. An
`unhealthy` healthcheck status alone does not trigger a restart. Docker itself
must be configured to start on boot.

## Source and deployment status

- **Source is published and public.** The application repository is
  <https://github.com/alastairgarner/vault>, with `main` published at
  `220ec611d20fd1ed788c636ec858544f4b1bd864` at this update.
  The configured HTTPS Git build context
  `https://github.com/alastairgarner/vault.git#main` can be fetched anonymously:
  **no GitHub credentials, deploy key, or SSH forwarding are required**.
  This only makes the source available; **application bearer-token
  authentication remains mandatory** for HTTP MCP access.
- **`#main` is a Git branch ref, not an image tag.** It intentionally tracks the
  application's main branch rather than pinning a commit. A Git push alone does
  not update a running container: updates require an explicit rebuild/recreation.
- The user reports Vault is running on the Pi with auth provisioned; an
  authenticated MCP connection exposed seven tools at
  **`https://brain.rpi.affablegecko.net/mcp`**. This is a deployment smoke check,
  not an exhaustive ARM64 performance/resource validation. QMD dependency
  advisories remain outstanding (see the application's `docs/qmd-research.md`).
- Auth provisioning, DNS and deployment remain manual host setup steps. This
  repository change does not deploy/restart services or change DNS, global
  Traefik, router, Tailscale, or network settings. Keep access on trusted
  LAN/tailnet; DNS alone is not access control. Use the existing root
  `.env.template` convention for `DOMAIN`; no new secret environment variables
  are required.

## Private authentication setup (manual, first setup)

HTTP MCP requires a bearer token on **every** request, including initialization
and notifications. All registered clients have full allowed-root read/write
access. There is no OAuth flow, per-client scope, or unauthenticated HTTP mode;
`ALLOW_UNAUTHENTICATED_HTTP` no longer enables access.

1. On a trusted client machine, manually generate a separate high-entropy token
   per client (e.g. `openssl rand -hex 32`) and store the original in that MCP
   client's secret store. Never put it in Git, chat, URLs, exported environment
   variables, or command-line arguments. Do not generate/install tokens as part
   of this repository's build or validation.
2. Calculate its SHA-256 hash using the application's stdin-only hashing helper
   after building the application locally. From its checkout, in Bash:

   ```bash
   unset TOKEN
   read -rsp 'Client token: ' TOKEN; printf '\n'
   printf '%s' "$TOKEN" | node dist/src/token-hash.js
   unset TOKEN
   ```

   Only the hash is printed. See the application's `docs/authentication.md` for
   the complete client-side workflow. The original token stays in the client;
   the server gets **only its hash**, never the original.
3. From this repository's root, prepare a dedicated private config directory:

   ```sh
   mkdir -p brain/.local/config
   chmod 700 brain/.local brain/.local/config
   # Preserve any existing config:
   [ -e brain/.local/config/auth.json ] || cp brain/auth.example.json brain/.local/config/auth.json
   chmod 600 brain/.local/config/auth.json
   ```

   Replace the deliberately invalid placeholder with the client's **64 lowercase
   hex SHA-256 hash**. Do not use the template unchanged. The JSON schema is
   `{ "version": 1, "tokens": [{ "name": "client", "sha256": "..." }] }`.
   Append unique named hashes for more clients, preserving existing entries.
   Names are 1–64 ASCII letters/numbers/underscores/hyphens, starting with a
   letter or number; names and hashes must each be unique. Config supports
   1–128 entries, maximum 64 KiB, and rejects unknown fields or raw-token fields.
4. The process runs as **UID/GID 1000:1000**. Arrange ownership of the dedicated
   config directory/file so that UID 1000 can traverse/read them (typically
   `chown -R 1000:1000 brain/.local/config` with suitable admin permissions).
   Keep directory/file modes `0700`/`0600`; do not loosen unrelated permissions.
   On SELinux hosts, arrange a container label for this directory, such as a
   local Compose override setting `bind.selinux: Z` on this bind mount.
   `auth.json` must be a regular file, not a symlink.

`brain/.local/` is Git-ignored. The **whole directory** is mounted read-only at
`/config`, allowing atomic host file replacement; Docker will not create it if
missing. It is outside notes, index/state, and the remote Git build context.
Protect and back it up separately: anyone able to edit it can grant access.
Missing/invalid config prevents startup.

Config is loaded **once at startup**. Adding or removing a hash requires a
mandatory restart. To rotate, add a fresh named hash, restart, switch the client,
remove the old hash, and restart again. To revoke all clients, stop the service;
an empty token list intentionally prevents startup. Already accepted work may
finish during graceful shutdown.

## Operation (commands not executed by this repository change)

Run from the repository root after preparing application auth and host routing.
The public HTTPS source requires no GitHub authentication.

```sh
# Normal parent-stack startup now includes Vault:
docker compose up -d
# Explicit first build or deliberate update from application main:
docker compose build --pull --no-cache brain
docker compose up -d --no-deps --force-recreate brain
# Mandatory after every auth config change:
docker compose restart brain
# Stop without deleting notes/state (a later stack up starts it again):
docker compose stop brain
```

Review changes on application main before rebuilding. No automatic updater is
configured. Do not use `down -v`: that could delete notes and unrelated stack
volumes. Only the first command operates on the whole stack; the remaining
commands target Vault. Traefik must be running to serve HTTPS.

Configure a stateless Streamable HTTP client to use
**`https://brain.rpi.${DOMAIN}/mcp`** (substitute the actual domain), sending
`Authorization: Bearer <original-token-not-the-hash>` on every request. Native
clients need no `Origin` header. `POST /mcp` is supported; authenticated
`GET`/`DELETE /mcp` return 405, not SSE or a persistent session.

Traefik uses the existing `websecure` entrypoint, `myresolver` certificate
resolver and internal port **3000** on the same implicit default Compose network.
No Vault port is published on the host. TLS terminates at Traefik; the private
proxy-to-container hop is HTTP. Do not log Authorization headers.
`HTTP_ALLOWED_HOSTS` includes the chosen DNS hostname **without a port** plus
`localhost,127.0.0.1,[::1]` for the image's healthcheck. Host validation does not
trust forwarded headers. Origins are rejected by default; do not enable broad
CORS. `GET /health` is unauthenticated **liveness only**, still subject to
Host/Origin checks; it does not prove auth, indexing, or MCP functionality.
After a separately authorized deployment, verify missing-token MCP rejection,
authenticated read/write with a disposable test note, and revocation after restart;
use `brain_status` to verify index freshness after Syncthing delivers external edits.

## Data, isolation and resource bounds

Vault bind-mounts `${RAID_MOUNT}/docker-volumes/syncthing/obsidian` read/write
at `/data/notes`, sharing only the Obsidian vault with Syncthing. On the Pi,
`RAID_MOUNT` must be `/mnt/raid`; the existing vault is at
`/mnt/raid/docker-volumes/syncthing/obsidian`. An unset/empty `RAID_MOUNT` is
rejected, and `create_host_path: false` prevents Docker creating a missing vault.
Ensure the RAID filesystem is mounted before starting Vault.

Both services are configured for UID/GID 1000:1000. The existing vault must allow
that user to traverse directories and read/write notes; do not loosen unrelated
permissions. SELinux hosts need an appropriate shared-container bind label.
All authenticated MCP clients have access to the real vault. Application main
restricts new Markdown notes to the existing lowercase `ai/` directory (and
existing subdirectories), while preserving reads/search and edits elsewhere.
This policy and the Vault rename were merged in
<https://github.com/alastairgarner/vault/pull/1> at commit
`220ec611d20fd1ed788c636ec858544f4b1bd864`.
Ensure `obsidian/ai` exists and is writable by UID/GID 1000:1000 before using that
version; no policy configuration is required. Running deployments only acquire
this restriction after rebuilding/recreating the service from the updated main.
MCP edits propagate to other devices through Syncthing. Concurrent
edits can conflict: Vault's writer lock does not coordinate Syncthing or Obsidian.

Full Markdown is authoritative. `restic/backup.sh` already backs up
`/mnt/raid/docker-volumes/syncthing`, including this vault; no additional vault
backup job is needed. Verify backup success and restores separately.

The existing `brain-fixture-state` volume remains at `/data/state`, outside the
synced vault and exclusive to Vault. It contains the disposable search index
and copies of note text: treat it as sensitive, not a backup. It can be rebuilt
from the vault and does not need backing up. Stop Vault before clearing state;
do not remove writer locks after a crash until confirming no writer is running.
The old `brain-fixture-notes` volume is no longer mounted; this configuration
change does not delete it or migrate its contents.

Runtime preserves the application's read-only root filesystem, dropped `ALL`
capabilities, `no-new-privileges`, init process, **1 CPU, 128 PIDs**, a
**64 MiB `/tmp` tmpfs** (mode 1777), **384 MiB V8 old-space** ceiling, and
**60-second** shutdown grace. **Docker imposes no container memory or swap cap.**
The V8 heap ceiling and application workload limits remain separate controls,
not a total-process memory cap; Vault can exhaust host memory. These settings do
not bound image/build size, persistent disk usage, or execution time. Native
work/OOM/forced termination may require manual lock recovery. Monitor disk growth; never discard authoritative
notes when rebuilding the index.

Application defaults (optional overrides belong under service `environment`,
not automatically in root `.env`; restart after changing):

| Setting | Default |
| --- | --- |
| `MAX_PENDING_OPERATIONS` (running + waiting) | 8 |
| `MAX_HTTP_REQUESTS` (admitted HTTP) | 8 |
| `MAX_HTTP_CONNECTIONS` (TCP sockets) | 32 |
| `MAX_COLLECTION_FILES` | 10,000 notes |
| `MAX_COLLECTION_BYTES` | 67,108,864 bytes (64 MiB source) |
| `MAX_SCAN_ENTRIES` | 20,000 |
| `MAX_SCAN_DEPTH` | 32 |

These limits are not a Pi capacity guarantee. Invalid limits prevent startup.
Overflow refuses admission (HTTP 503 with `Retry-After: 1`); use backoff. A write
may still commit after disconnect, so re-read before retrying ambiguous failures.
