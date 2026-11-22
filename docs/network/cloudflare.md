# cloudflare tunnel

goal: publish the box through a remotely managed `cloudflared` tunnel, with no
inbound port and no container in the middle. routing lives in the cloudflare
dashboard, so hostname, access policy and origin changes apply without a
redeploy.

warp / mesh connectors are not part of the toolset anymore.

## create the tunnel

zero trust > networks > tunnels > create a tunnel.

- name it after the server: `hostname -s` is the obvious choice. the name is
  only a dashboard label; the token binds the service to the tunnel.
- pick debian and 64-bit, matching the host.
- copy the tunnel token. it is a long base64 blob and it is a credential.

do not put the token in `postinstall.env`. put it in a `0600` file:

```bash
sudo install -d -m 0700 /root/.secrets
sudo install -m 0600 /dev/stdin /root/.secrets/cf-tunnel.token <<'EOF'
eyJhIjoi...
EOF
```

config:

```bash
ENABLE_CLOUDFLARED=1
CLOUDFLARED_TOKEN_FILE=/root/.secrets/cf-tunnel.token
```

`CLOUDFLARED_TOKEN` works as a fallback, but the value shows up in process
tables, shell history and logs. use the file. the module accepts `0400` or
`0600` and refuses a group- or world-readable token file.

## what the module does

the module follows the official debian install path:

1. installs `curl` and `ca-certificates`
2. downloads the cloudflare apt key to
   `/usr/share/keyrings/cloudflare-main.gpg`
3. writes `/etc/apt/sources.list.d/cloudflared.list` with
   `https://pkg.cloudflare.com/cloudflared any main`
4. refreshes apt and installs the distro package `cloudflared`
5. runs `cloudflared service install <token>` and enables the host unit
6. refuses to report success when `cloudflared.service` is not active

the binary runs directly on the host, not in docker. the package and the unit
survive reboots, and the dashboard remains the source of truth for routes.

reruns keep the service. the installed service config already carries its
token, so the source token file is not needed after the first install. if the
unit exists but is inactive, the module starts it.

## routing and hot changes

in the tunnel page, add a public hostname:

| field | example |
| --- | --- |
| subdomain | `app` |
| domain | `example.com` |
| service | `http://localhost:3000` |

the origin stays bound to localhost. opening the origin port in nftables
defeats the point of the tunnel.

hostname, origin and access changes are applied by cloudflare and pushed to the
running connector. no restart, no new token, no rerun of the installer. only a
new tunnel or a rotated token requires touching the host.

## operational notes

```bash
systemctl status cloudflared
journalctl -u cloudflared -f
ss -ltnp | grep 3000             # origin should be localhost-only
```

- `cloudflared` dials out to cloudflare over tcp/udp `7844`. outbound only. the
  firewall module opens nothing for it.
- a tunnel is not a vpn. it exposes what you route, nothing more.
- the token is written to `/etc/cloudflared/token` (mode `0600`) by
  `cloudflared service install`. the unit points at it with `--token-file`.
  treat that file as a secret.
- rotating the token: delete the tunnel in the dashboard, create a new one,
  update the `0600` source file, remove the old unit and token, then rerun:

```bash
sudo systemctl disable --now cloudflared
sudo rm /etc/systemd/system/cloudflared.service /etc/cloudflared/token
sudo bash debian13-postinstall.sh --only cloudflared
```

- the audit checks the binary, the active unit, the enabled state, the host
  unit path and the token file mode. it does not prove that cloudflare accepted
  the token or that dns points at the tunnel.

## why not docker

the host service is the same connector with fewer moving parts:

- the dashboard token install is one command
- no docker socket or container network namespace to debug
- no image pull on a box that may be offline from the registry
- `systemctl status cloudflared` is the whole troubleshooting surface

if the host already runs docker, keep the tunnel on the host anyway. a broken
docker daemon should not take remote access down with it.

## why not open 443

because then you own certificates, dns, a waf you did not configure, and a port
that scanners find in an hour. the tunnel removes three of those and the fourth
is a dashboard toggle.
