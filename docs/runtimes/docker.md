# docker

upstream repo, not the distro package. the distro one lags and splits the
compose plugin into a separate riddle.

## install

key and repo under `/etc/apt/keyrings`, then:

```
docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

the script only rewrites the repo file when it changes, so reruns are cheap.

## daemon.json

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true,
  "no-new-privileges": true,
  "userland-proxy": false
}
```

- log rotation: without it, a chatty container fills the disk and takes the box
  with it. 30mb per container is plenty for something you debug with `docker
  logs`, not an audit trail.
- `live-restore`: containers keep running while the daemon restarts. `apt
  upgrade` on containerd stops being an outage.
- `no-new-privileges`: a container cannot gain privileges through setuid
  binaries. opt out per container when something genuinely needs it.
- `userland-proxy: false`: no per-published-port proxy process. the kernel does
  the forwarding. fewer moving parts, better throughput.

not set: `iptables: false`, because then published ports and the firewall stop
talking to each other. not set: an insecure registry mirror. not set: userns
remap, because it breaks bind mounts in ways you discover at 2am.

## the docker group

`DOCKER_ADD_USER_TO_GROUP=1` adds `NEW_USER` to `docker`. that is root
equivalent: `docker run -v /:/host` is a root shell with extra steps. it is on
because the point of this box is running containers without `sudo` every time.
turn it off if the box is shared or the user account is not fully trusted.

## compose

`docker compose` (space, plugin) is installed. the old `docker-compose` binary
is not. projects live wherever you put them, the scripts do not create a
`/srv` layout for you.

## common checks

```bash
docker info --format '{{.LoggingDriver}} {{.LiveRestoreEnabled}}'
docker ps --format 'table {{.Names}}\t{{.Ports}}'
docker compose logs -f
journalctl -u docker --since -15min
```

the audit verifies `daemon.json` parses and that the three opinions above are
actually in it. it does not verify which containers you run, that is your
problem and mine.

## firewall

published ports bypass the input chain through nat and the forward chain, which
is documented in [../hardening/firewall.md](../hardening/firewall.md). if a port
should not be public, publish it as `127.0.0.1:8080:80` and put cloudflared in
front.
