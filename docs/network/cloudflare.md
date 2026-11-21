# cloudflare tunnel and mesh

two products, both outbound, both remove the need to expose a port. pick per
need. they can live on the same box.

| | tunnel (`cloudflared`) | mesh (`warp-cli`) |
| --- | --- | --- |
| what it does | publishes an app to the internet or to your zero trust org | joins the server to your private cloudflare network |
| dns | a hostname you own, proxied | private dns, no public record |
| auth | service token, access policy | zero trust identity, warp profile |
| inbound port | none | none |
| module flag | `ENABLE_CLOUDFLARED` | `ENABLE_WARP` |

## tunnel

create it in the dashboard: zero trust > networks > tunnels > create a tunnel >
debian. copy the token. it looks like a long base64 blob.

do not put it in `postinstall.env`. put it in a file:

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

the module adds the cloudflare apt repo, installs `cloudflared`, and runs
`cloudflared service install <token>`. that writes
`/etc/systemd/system/cloudflared.service` with the token in `ExecStart=`, which
is why the source file is `0600` and why you do not paste the token in chat.

route traffic in the dashboard (public hostname -> `http://localhost:3000`) and
keep the app bound to localhost. opening the port too defeats the point.

## mesh / warp connector

zero trust > networks > tunnels > create a warp connector. copy the token into
another `0600` file:

```bash
ENABLE_WARP=1
CLOUDFLARE_WARP_TOKEN_FILE=/root/.secrets/cf-warp.token
```

the module adds the cloudflare client repo and installs `cloudflare-warp`. it
tries `warp-cli connector new <token>` first, then falls back to the older
`registration token` flow. the connector shows up in the dashboard under
networks. then route private networks to it.

note: upstream has no trixie repo yet. `WARP_CODENAME=bookworm` is the default
and the package runs fine. bump it when cloudflare ships trixie.

## operational notes

```bash
systemctl status cloudflared
journalctl -u cloudflared -f
cloudflared tunnel info <name>       # from the dashboard, not the box
warp-cli --accept-tos status
warp-cli --accept-tos networks
```

- tunnels survive reboots through the systemd unit. no cron, no screen.
- `cloudflared` dials out to cloudflare over 7844 tcp/udp. outbound only. the
  firewall script opens nothing for it.
- a tunnel is not a vpn. it exposes what you route, nothing more.
- rotating a token: delete the tunnel in the dashboard, create a new one, update
  the file, rerun `--only cloudflared`. the unit is rewritten only if the
  service is missing, so delete the unit first if you need a new token in it:

```bash
sudo systemctl disable --now cloudflared
sudo rm /etc/systemd/system/cloudflared.service
sudo bash debian13-postinstall.sh --only cloudflared
```

- mesh connectors appear as `warp-svc` and a `warp-cli` connector. if the status
  says `Disconnected`, the token was probably already used or expired.

## why not just open 443

because then you own certificates, dns, a waf you did not configure, and a port
that scanners find in an hour. the tunnel removes three of those and the fourth
is a dashboard toggle.
