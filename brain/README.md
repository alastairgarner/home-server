# Markdown Brain MCP (opt-in, not deployed)

The root Compose file includes this service, but the `brain` profile is disabled
by default. Ordinary `docker compose up -d` does not build or start it and needs
neither its source nor its auth config. Explicitly targeting `brain` also enables
the service; do not do that until the prerequisites below are met.

## Prerequisites / current blockers

- **Source is published, but private.** The application repository is
  <https://github.com/alastairgarner/markdown-brain>, with `main` published at
  `abee19e4930ee1e3d34c068fc518c9cca2f8d127` at this update.
  The configured build context
  `https://github.com/alastairgarner/markdown-brain.git#main` **cannot be fetched
  anonymously**. Pi BuildKit repository authentication remains a prerequisite;
  MCP bearer tokens do not authenticate GitHub builds. A host GitHub login alone
  does not necessarily give the builder access. Arrange narrowly scoped,
  read-only builder access separately, without embedding credentials in URLs,
  Compose, build arguments, or Git. Options include BuildKit Git authentication
  for the HTTPS context, or an SSH Git context with SSH forwarding and a
  read-only deploy key (requiring a deliberate build-context/config change).
  Making the repository public is an alternative only with explicit user
  approval. This integration configures no credentials and changes no visibility.
- **`#main` is a Git branch ref, not an image tag.** It intentionally tracks the
  application's main branch rather than pinning a commit. A Git push alone does
  not update a running container: updates require an explicit rebuild/recreation.
- Raspberry Pi **ARM64 builds/runtime are unverified**. Only local amd64 Docker
  tests passed upstream; native dependencies may need additional work. QMD
  dependency advisories remain outstanding (see the application's
  `docs/qmd-research.md`). Review these before deployment.
- Private auth config, DNS resolution for `brain.rpi.${DOMAIN}`, and Pi deployment
  are separate **manual later actions**. No DNS, global Traefik, router, Tailscale,
  or network changes are made here. Keep access on trusted LAN/tailnet; DNS alone
  is not access control. Use the existing root `.env.template` convention for
  `DOMAIN`; no new secret environment variables are required.

## Private authentication setup (manual, later)

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

## Future operation (not executed by this integration)

Only after private-repository BuildKit access, application auth setup, ARM64
verification, and DNS approval, run these commands from the repository root on
the intended host. The build command assumes the builder's repository
credentials have been configured separately; it does not configure them:

```sh
# Explicit first build/start or deliberate update from application main:
docker compose --profile brain build --pull --no-cache brain
docker compose --profile brain up -d --no-deps --force-recreate brain
# Mandatory after every auth config change:
docker compose --profile brain restart brain
# Disable without deleting notes/state:
docker compose --profile brain stop brain
```

Review changes on application main before rebuilding. No automatic updater is
configured. Do not use `down -v`: that could delete notes and unrelated stack
volumes. The commands above target only Brain; Traefik must already be running.

Configure a stateless Streamable HTTP client to use
**`https://brain.rpi.${DOMAIN}/mcp`** (substitute the actual domain), sending
`Authorization: Bearer <original-token-not-the-hash>` on every request. Native
clients need no `Origin` header. `POST /mcp` is supported; authenticated
`GET`/`DELETE /mcp` return 405, not SSE or a persistent session.

Traefik uses the existing `websecure` entrypoint, `myresolver` certificate
resolver and internal port **3000** on the same implicit default Compose network.
No Brain port is published on the host. TLS terminates at Traefik; the private
proxy-to-container hop is HTTP. Do not log Authorization headers.
`HTTP_ALLOWED_HOSTS` includes the chosen DNS hostname **without a port** plus
`localhost,127.0.0.1,[::1]` for the image's healthcheck. Host validation does not
trust forwarded headers. Origins are rejected by default; do not enable broad
CORS. `GET /health` is unauthenticated **liveness only**, still subject to
Host/Origin checks; it does not prove auth, indexing, or MCP functionality.
After a separately authorized deployment, verify missing-token MCP rejection,
authenticated fixture read/write, and revocation after restart; use `brain_status`
for index freshness.

## Data, isolation and resource bounds

Start with the dedicated empty/fixture named volumes `brain-fixture-notes` and
`brain-fixture-state`, mounted read/write at `/data/notes` and `/data/state`.
**Do not mount or access the real Obsidian vault.** The image initializes these
paths for UID/GID 1000. Bind mounts would require explicit ownership/security
label setup and separate approval.

Full Markdown is authoritative and needs backups. The disposable state includes
copies of note text as well as the search index: treat it as sensitive, not a
backup. Root and state must remain disjoint and exclusive to this process.
Do not remove writer locks after a crash until confirming no writer is running.

Runtime preserves the application's read-only root filesystem, dropped `ALL`
capabilities, `no-new-privileges`, init process, **768 MiB RAM with no extra swap,
1 CPU, 128 PIDs**, a **64 MiB `/tmp` tmpfs** (mode 1777), **384 MiB V8 old-space**
ceiling, and **60-second** shutdown grace. These do not bound image/build size,
persistent disk usage, or execution time. Native work/OOM/forced termination may
require manual lock recovery. Monitor disk growth; never discard authoritative
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
