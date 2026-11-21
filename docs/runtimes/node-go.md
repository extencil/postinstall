# node and go

both optional, both off by default. a box that runs containers usually does not
need a host toolchain.

## node

`ENABLE_NODE=1`, `NODE_MAJOR=24` (current lts as of late 2026). the module adds
the nodesource repo with a signed keyring, installs `nodejs` (node + npm), then
skips itself when `node -v` already matches the pinned major.

```bash
node -v
npm -v
npx --version
```

version managers (`nvm`, `fnm`, `volta`) fight with the apt package and expect
a login shell. pick one strategy per box. this repo picks apt because a service
running `node app.js` under systemd does not source your shell rc.

## go

`ENABLE_GO=1` installs `golang-go` from trixie. that is go 1.24, which is fine
for building tools. if you need the bleeding edge:

```bash
GO_VERSION=1.25.1
curl -fsSLO "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
```

then `export PATH=$PATH:/usr/local/go/bin` in the dotfiles. do not mix the tarball
with the apt package; the audit only checks `go version`, not where it came from.

## cross compile

both toolchains are happy to emit linux/amd64, linux/arm64 and the rest:

```bash
GOOS=linux GOARCH=arm64 go build ./cmd/thing
```

that is usually the reason to have them on a build box instead of on the server.
