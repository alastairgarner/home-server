# workspace MCP

Gmail read and draft MCP server from
<https://github.com/alastairgarner/workspace-mcp> (`#main`), at
**`https://workspace.rpi.${DOMAIN}/mcp`** (all accounts) or `/mcp/<account>`.
Traefik terminates TLS; no host port is published. Covered by the rpi wildcard DNS.

## Private config (manual)

`workspace/.local/config/` (Git-ignored) is mounted read-only at `/config` and
must contain `client.json`, `accounts.json` and `auth.json`. Create them on the
laptop with the application's README setup steps (`pnpm auth:google --account
<name>`, token hashing), then copy them here. Keep the directory `0700` and files
`0600`, readable by UID 1000. `accounts.json` holds Google refresh tokens:
anyone with it can read your mail. Missing or invalid config stops startup.

## Operation

```sh
docker compose build --pull --no-cache workspace   # first build / update from main
docker compose up -d --no-deps --force-recreate workspace
docker compose restart workspace                   # after any config change
```

`GET /health` is liveness only. After deploying, check an unauthenticated
`POST /mcp` returns 401 and `list_accounts` works through mcp-hub.
