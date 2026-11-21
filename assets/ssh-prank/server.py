#!/usr/bin/env python3
"""A bounded SSH decoy. Sends a banner and refuses all authentication."""

import argparse
import ipaddress
import logging
import os
from pathlib import Path
import signal
import socket
import stat
import threading
import time

import paramiko


class RejectAll(paramiko.ServerInterface):
    def __init__(self, banner):
        self.banner = banner

    def get_banner(self):
        return self.banner, "en-US"

    def get_allowed_auths(self, username):
        return "publickey,password"

    def check_auth_none(self, username):
        return paramiko.AUTH_FAILED

    def check_auth_password(self, username, password):
        return paramiko.AUTH_FAILED

    def check_auth_publickey(self, username, key):
        return paramiko.AUTH_FAILED

    def check_channel_request(self, kind, chanid):
        return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

    def check_channel_direct_tcpip_request(self, chanid, origin, destination):
        return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

    def check_port_forward_request(self, address, port):
        return False

    def check_channel_subsystem_request(self, channel, name):
        return False


def load_host_key(path):
    if path.exists():
        metadata = path.lstat()
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_mode & 0o077:
            raise ValueError("host key must be a regular private file (mode 0600)")
        return paramiko.RSAKey.from_private_key_file(str(path))

    # Set permissions at creation, not after writing private material.
    key = paramiko.RSAKey.generate(bits=3072)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="ascii") as stream:
            key.write_private_key(stream)
            stream.flush()
            os.fsync(stream.fileno())
    except BaseException:
        path.unlink(missing_ok=True)
        raise
    return key


class Admission:
    """Bound active work and new handshakes without keeping a peer history."""

    def __init__(self, maximum, per_ip, rate):
        self.maximum = maximum
        self.per_ip = per_ip
        self.rate = rate
        self.tokens = float(rate)
        self.updated = time.monotonic()
        self.active = {}
        self.total = 0
        self.lock = threading.Lock()

    def acquire(self, peer):
        with self.lock:
            now = time.monotonic()
            self.tokens = min(self.rate, self.tokens + (now - self.updated) * self.rate)
            self.updated = now
            if (self.tokens < 1 or self.total >= self.maximum
                    or self.active.get(peer, 0) >= self.per_ip):
                return False
            self.tokens -= 1
            self.total += 1
            self.active[peer] = self.active.get(peer, 0) + 1
            return True

    def release(self, peer):
        with self.lock:
            self.total -= 1
            self.active[peer] -= 1
            if self.active[peer] == 0:
                del self.active[peer]


def handle_connection(client, peer, host_key, banner, admission, stopping, lifetime):
    transport = None
    deadline = time.monotonic() + lifetime
    try:
        client.settimeout(min(10, lifetime))
        transport = paramiko.Transport(client)
        transport.local_version = "SSH-2.0-postinstall-decoy"
        transport.banner_timeout = min(10, lifetime)
        transport.handshake_timeout = min(10, lifetime)
        transport.add_server_key(host_key)
        negotiated = threading.Event()
        # Async negotiation lets our deadline also bound silent or broken clients.
        transport.start_server(event=negotiated, server=RejectAll(banner))
        while transport.is_active() and time.monotonic() < deadline:
            if stopping.wait(0.1):
                break
    except (paramiko.SSHException, EOFError, OSError):
        # Peer-controlled exceptions can contain credentials or terminal escapes.
        pass
    finally:
        if transport is not None:
            transport.close()
            transport.join(timeout=1)
        client.close()
        admission.release(peer)


def serve(args):
    with args.banner.open("rb") as stream:
        banner = stream.read(16385)
    if not banner or len(banner) > 16384:
        raise ValueError("banner must contain between 1 and 16384 bytes")
    banner = banner.decode("utf-8")
    host_key = load_host_key(args.key)
    admission = Admission(args.max_connections, args.per_ip, args.rate)
    stopping = threading.Event()
    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, lambda _signum, _frame: stopping.set())

    dual = args.host == "::" and socket.has_dualstack_ipv6()
    family = socket.AF_INET6 if ":" in args.host else socket.AF_INET
    host = args.host
    if host == "::" and not dual:
        family, host = socket.AF_INET, "0.0.0.0"
    with socket.create_server((host, args.port), family=family,
                              backlog=64, dualstack_ipv6=dual) as listener:
        listener.settimeout(0.5)
        notify = os.environ.get("NOTIFY_SOCKET")
        if notify:
            address = "\0" + notify[1:] if notify.startswith("@") else notify
            with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as notification:
                notification.connect(address)
                notification.sendall(b"READY=1")
        logging.info("SSH decoy ready on tcp/%d; all authentication is refused", args.port)
        while not stopping.is_set():
            try:
                client, address = listener.accept()
            except socket.timeout:
                continue
            peer = ipaddress.ip_address(address[0])
            if isinstance(peer, ipaddress.IPv6Address) and peer.ipv4_mapped:
                peer = peer.ipv4_mapped
            peer = str(peer)
            if not admission.acquire(peer):
                client.close()
                continue
            try:
                threading.Thread(
                    target=handle_connection,
                    args=(client, peer, host_key, banner, admission, stopping, args.lifetime),
                    daemon=True,
                ).start()
            except RuntimeError:
                client.close()
                admission.release(peer)
        stopping.set()


def positive(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="::")
    parser.add_argument("--port", type=positive, default=22)
    parser.add_argument("--key", type=Path, required=True)
    parser.add_argument("--banner", type=Path, required=True)
    parser.add_argument("--max-connections", type=positive, default=32)
    parser.add_argument("--per-ip", type=positive, default=4)
    parser.add_argument("--rate", type=positive, default=8)
    parser.add_argument("--lifetime", type=positive, default=30)
    args = parser.parse_args()
    if args.port > 65535:
        parser.error("port must be between 1 and 65535")
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    # No per-client logging, including Paramiko's peer-controlled error strings.
    logging.getLogger("paramiko").disabled = True
    logging.getLogger("paramiko.transport").disabled = True
    try:
        serve(args)
    except (OSError, ValueError, paramiko.SSHException):
        logging.error("decoy startup failed; check listener, banner and private host key")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
