# Replace Traefik with Caddy

## Summary

Replace Traefik reverse proxy with Caddy using a central Caddyfile, Cloudflare DNS challenge for TLS, and the same subdomain routing scheme.

## Requirements

1. **Create a `caddy/` directory** with a `docker-compose.yml` and `Caddyfile` replacing the current `traefik/` directory.

2. **Use a custom Caddy image** with the `caddy-dns/cloudflare` plugin. Add a `caddy/Dockerfile` that builds Caddy with this plugin using the official builder image.

3. **Configure TLS via Cloudflare DNS challenge** using the existing `CF_DNS_API_TOKEN` env var. Caddy should provision certs for all `*.rpi.${DOMAIN}` subdomains.

4. **Define all service routes in the Caddyfile** — one block per service, proxying to the service's container by name and port:

   | Subdomain | Upstream |
   |-----------|----------|
   | `traefik.rpi.{$DOMAIN}` | _(remove — Traefik dashboard goes away)_ |
   | `pihole.rpi.{$DOMAIN}` | `pihole:80` |
   | `photos.rpi.{$DOMAIN}` | `photoprism:2342` |
   | `logs.rpi.{$DOMAIN}` | `dozzle:8080` |
   | `sync.rpi.{$DOMAIN}` | `syncthing:8384` |
   | `changedetection.rpi.{$DOMAIN}` | `changedetection:5000` |
   | `happy.rpi.{$DOMAIN}` | `happy-server:3000` |

5. **Bind ports 80 and 443** on the Caddy container (same as Traefik today). Port 8080 (Traefik dashboard) is no longer needed.

6. **Remove Traefik labels** from all service compose files. Since Caddy uses a central Caddyfile, the Docker labels on each service are no longer needed.

7. **Update root `docker-compose.yml`** — replace the `traefik/docker-compose.yml` include with `caddy/docker-compose.yml`.

8. **Remove the `traefik/` directory** (traefik.yaml and docker-compose.yml).

9. **Update the Pi-hole CNAME records** — remove the `traefik.rpi.*` CNAME since there's no Traefik dashboard. Optionally add a `caddy.rpi.*` CNAME if we want a Caddy admin endpoint (likely not needed).

10. **Update CLAUDE.md** — replace Traefik references with Caddy.

## Acceptance Criteria

- [ ] `caddy/Dockerfile` builds a Caddy image with the Cloudflare DNS plugin
- [ ] `caddy/Caddyfile` defines routes for all active services using `{$DOMAIN}` env var
- [ ] `caddy/docker-compose.yml` runs the custom Caddy image with ports 80/443, mounts the Caddyfile, and passes `CF_DNS_API_TOKEN`
- [ ] All service compose files have Traefik labels removed
- [ ] Root `docker-compose.yml` includes `caddy/docker-compose.yml` instead of `traefik/docker-compose.yml`
- [ ] `traefik/` directory is deleted
- [ ] Pi-hole CNAME for `traefik.rpi.*` is removed
- [ ] CLAUDE.md reflects Caddy instead of Traefik
- [ ] No references to Traefik remain in any active config (commented-out monitoring stack excluded)

## Files to Modify

**Create:**
- `caddy/Dockerfile`
- `caddy/Caddyfile`
- `caddy/docker-compose.yml`

**Modify:**
- `docker-compose.yml` (root) — swap include
- `pihole/docker-compose.yml` — remove Traefik labels
- `photoprism/docker-compose.yml` — remove Traefik labels
- `dozzle/docker-compose.yml` — remove Traefik labels
- `syncthing/docker-compose.yml` — remove Traefik labels
- `changedetection/docker-compose.yml` — remove Traefik labels
- `happy-coder/docker-compose.yml` — remove Traefik labels
- `pihole/etc-dnsmasq.d/05-pihole-custom-cname.conf` — remove traefik CNAME
- `CLAUDE.md` — update references

**Delete:**
- `traefik/docker-compose.yml`
- `traefik/traefik.yaml`

## Resolved Questions

- **Caddy admin API:** Leave internal-only (default localhost:2019). It's a JSON REST API, not a dashboard — no subdomain needed.
- **Monitoring stack:** Leave the disabled monitoring stack's Traefik labels as-is. They can be updated if/when the stack is re-enabled.
