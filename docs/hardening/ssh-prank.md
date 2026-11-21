# ssh prank

real ssh defaults to `1/tcp`. this module puts a separate, reject-only ssh
service on `22/tcp`. it sends a prank banner after key exchange and refuses
every login, shell, channel and forwarding request.

the point is to occupy some automated clients aimed at port 22. it is not an
endless tarpit, and moving real ssh does not prevent a full port scan.

## deployment

`ENABLE_SSH_PRANK=1` enables the module by default. the order is firewall,
real ssh, decoy, fail2ban. the target host gets `python3` and
`python3-paramiko` through apt. the installer never uses pip or fetches a live
gist. the reviewed implementation is shipped in `assets/ssh-prank/`.

source reference: [original script](https://gist.github.com/extencil/659287bc46c31d8d8ffb6fb90b7cddb7).
the implementation keeps the banner and reject-all behavior, with bounded
workers, session deadlines, private key creation and service isolation added.
the bundled banner is generic; personal text can be supplied separately.

```bash
SSH_PORT=1
ENABLE_SSH_PRANK=1
SSH_PRANK_BANNER_FILE=""  # empty uses the bundled banner
```

a custom banner must be UTF-8, nonempty and at most 16384 bytes. it is public
text. do not put credentials in it. the banner is sent during ssh user
authentication; netcat only sees the ssh identification string.

existing configs keep their explicit ssh port. `SSH_PORT=22` conflicts with
the decoy and aborts before modules change the host. allow the real port at
the provider firewall before migrating. from a target host's existing shell:

```bash
sudo bash debian13-postinstall.sh --only firewall,ssh,ssh_prank,fail2ban
```

the decoy refuses to start if real ssh has no listener on `SSH_PORT`, if
`sshd -T` lists unexpected ports, or if another process still owns port 22.
it never stops an unrelated listener to claim that port. these checks do not
replace proving a new login with your own private key.

## files and limits

| path | purpose |
| --- | --- |
| `/usr/local/lib/postinstall/ssh-prank.py` | bundled python implementation |
| `/etc/postinstall/ssh-prank-banner.txt` | public banner, mode 0644 |
| `/etc/systemd/system/postinstall-ssh-prank.service` | service and sandbox |
| `/var/lib/postinstall-ssh-prank/host_key` | generated RSA host key, mode 0600 |

systemd owns the private state directory through `DynamicUser=yes` and
`StateDirectory=postinstall-ssh-prank`. the host key is separate from real
sshd keys and survives service restarts. managed script, banner and unit
writes use `write_file` and its backups. unchanged reruns leave the service
alone. a full dry-run prints planned changes without creating files or keys.

runtime defaults:

- at most 32 simultaneous connections and 4 per source address
- at most 8 new admitted connections per second, with a burst of 8
- at most 30 seconds per connection; handshake timeout at most 10 seconds
- memory limited to 192 MiB, CPU quota 50%, 96 tasks and 256 file descriptors

excess connections are closed. the peer table only retains active sources.
these limits also mean a busy decoy can refuse new connections without sending
a banner. clients may disconnect early; there is no promise to keep bots busy.

the service runs with a dynamic unprivileged identity, only
`CAP_NET_BIND_SERVICE`, a read-only system filesystem and a private temporary
directory. it sends readiness to systemd only after binding the listener.
passwords, usernames, client keys, peer addresses and client-controlled error
strings are not logged. startup and fatal local errors go to the journal.

fail2ban continues watching real sshd on `SSH_PORT`. it does not ban traffic
from the decoy's separate service.

## verification and failure modes

```bash
sudo systemctl status postinstall-ssh-prank.service
sudo journalctl -u postinstall-ssh-prank.service --since -10min
sudo ss -ltnp 'sport = :22'
sudo bash audit/debian13-audit.sh
ssh -p 1 ops@example.com
ssh -o PreferredAuthentications=none -p 22 ops@example.com
```

the first ssh command must open real access from a separate terminal. the
second must show the prank banner and fail authentication. do not close the
provider shell until real access and sudo both work.

port conflicts, a malformed banner or an unreadable private host key make the
decoy fail; they must not cause changes to real ssh authentication. the audit
checks service state, listener ownership, private key mode, effective sandbox
settings, banner presence and the live firewall rule for port 22. it does not
perform a client handshake or prove that a provider firewall permits access.

local code checks and container protocol checks are separate from a completed
deployment. socket migration, systemd sandbox behavior, external reachability
and login on a disposable Debian 13 system still need live verification.

the regression checks use the standard library's unittest runner and Paramiko
from the target distribution. in a disposable test container with that package
available, run `python3 -B -m unittest discover -s tests -v`. the checks use
temporary host keys and unprivileged loopback sockets, mock module mutations
and never execute the deploy entrypoint.

## recovery and disabling

use the provider console if real ssh is unavailable. for a broken decoy:

```bash
sudo systemctl disable --now postinstall-ssh-prank.service
sudo systemctl reset-failed postinstall-ssh-prank.service
```

then set `ENABLE_SSH_PRANK=0` in the config and rerun the firewall module to
remove its automatic port 22 allowance. remove `22` from `EXTRA_TCP_PORTS` too
if it was added there. disabling or skipping a module alone does not stop a
previously deployed service; an active decoy keeps its firewall allowance.

for a bad banner or script update, restore the affected file from
`/var/backups/postinstall/<timestamp>/`, correct the source/config and restart
the decoy. for a unit restore, run `systemctl daemon-reload` before restarting.
keep the private state directory to retain the decoy's host identity.
