"""Protocol checks using temporary keys and unprivileged loopback sockets only."""

import importlib.util
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest

import paramiko


ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "assets/ssh-prank/server.py"
spec = importlib.util.spec_from_file_location("ssh_prank", SERVER)
prank = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prank)


class AdmissionChecks(unittest.TestCase):
    def test_caps_and_cleanup(self):
        gate = prank.Admission(2, 1, 100)
        self.assertTrue(gate.acquire("one"))
        self.assertFalse(gate.acquire("one"))
        self.assertTrue(gate.acquire("two"))
        self.assertFalse(gate.acquire("three"))
        gate.release("one")
        self.assertTrue(gate.acquire("three"))
        gate.release("two")
        gate.release("three")
        self.assertEqual(gate.total, 0)
        self.assertEqual(gate.active, {})

    def test_rate_limit(self):
        gate = prank.Admission(10, 10, 1)
        self.assertTrue(gate.acquire("one"))
        gate.release("one")
        self.assertFalse(gate.acquire("two"))
        gate.updated -= 2
        self.assertTrue(gate.acquire("two"))

    def test_channels_and_forwarding_are_denied(self):
        server = prank.RejectAll("banner")
        denied = paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED
        self.assertEqual(server.check_channel_request("session", 0), denied)
        self.assertEqual(server.check_channel_direct_tcpip_request(0, (), ()), denied)
        self.assertFalse(server.check_port_forward_request("127.0.0.1", 1234))
        self.assertFalse(server.check_channel_shell_request(None))
        self.assertFalse(server.check_channel_exec_request(None, b"id"))
        self.assertFalse(server.check_channel_subsystem_request(None, "sftp"))
        self.assertEqual(server.check_auth_interactive("ops", ""), paramiko.AUTH_FAILED)


class ModuleChecks(unittest.TestCase):
    def shell(self, body):
        return subprocess.run(
            ["bash", "-c", "set -euo pipefail\nsource lib/common.sh\n"
             "source lib/modules/35-ssh-prank.sh\n" + body],
            cwd=ROOT, text=True, capture_output=True,
        )

    def test_unchanged_dry_run_does_not_restart(self):
        result = self.shell("""
DRY_RUN=1 SSH_PORT=1
install_pkgs() { :; }
write_file() { cat >/dev/null; LAST_WRITE_CHANGED=0; }
service_active() { return 0; }
service_enabled() { return 0; }
module_ssh_prank
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ssh prank unchanged", result.stdout)
        self.assertNotIn("systemctl", result.stdout)

    def test_changed_dry_run_plans_one_restart(self):
        result = self.shell("""
DRY_RUN=1 SSH_PORT=1
install_pkgs() { log_dry "install $*"; }
write_file() { cat >/dev/null; LAST_WRITE_CHANGED=1; }
service_active() { return 1; }
service_enabled() { return 1; }
module_ssh_prank
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[dry-run] install python3 python3-paramiko", result.stdout)
        self.assertEqual(result.stdout.count("systemctl restart"), 1)
        self.assertEqual(result.stdout.count("systemctl daemon-reload"), 1)

    def test_conflicting_real_port_aborts(self):
        result = self.shell("DRY_RUN=1 SSH_PORT=22; module_ssh_prank")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("different port", result.stderr)

    def test_unrelated_listener_is_left_alone(self):
        result = self.shell("""
DRY_RUN=0 SSH_PORT=1
ss() {
  if [[ $* == *':22'* ]]; then
    printf 'LISTEN 0 128 *:22 *:* users:(("other",pid=555,fd=3))\\n'
  else
    printf 'LISTEN 0 128 *:1 *:* users:(("sshd",pid=100,fd=3))\\n'
  fi
}
sshd() { printf 'port 1\\n'; }
systemctl() { printf '999\\n'; }
install_pkgs() { log_err 'unexpected package mutation'; return 90; }
module_ssh_prank
""")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("leaving it alone", result.stderr)
        self.assertNotIn("unexpected package mutation", result.stderr)


class ProtocolChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.directory = Path(cls.temp.name)
        cls.key = cls.directory / "host_key"
        cls.host_key = prank.load_host_key(cls.key)
        cls.banner = ROOT / "assets/ssh-prank/banner.txt"

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def setUp(self):
        self.notify_path = self.directory / "notify.sock"
        self.notify_path.unlink(missing_ok=True)
        self.notification = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        self.notification.bind(str(self.notify_path))
        self.notification.settimeout(10)
        with socket.socket() as candidate:
            candidate.bind(("127.0.0.1", 0))
            self.port = candidate.getsockname()[1]
        env = dict(os.environ, NOTIFY_SOCKET=str(self.notify_path))
        self.server = subprocess.Popen(
            [sys.executable, "-B", str(SERVER), "--host", "127.0.0.1",
             "--port", str(self.port), "--key", str(self.key),
             "--banner", str(self.banner), "--lifetime", "2", "--per-ip", "2"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env,
        )
        self.addCleanup(self.stop_server)
        self.assertEqual(self.notification.recv(256), b"READY=1")

    def stop_server(self):
        self.server.terminate()
        stdout, stderr = self.server.communicate(timeout=5)
        self.notification.close()
        self.assertEqual(self.server.returncode, 0, stderr.decode())
        for sensitive in (b"secret-password-fixture", b"fixture-username"):
            self.assertNotIn(sensitive, stdout + stderr)

    def transport(self):
        connection = socket.create_connection(("127.0.0.1", self.port), timeout=5)
        client = paramiko.Transport(connection)
        self.addCleanup(client.close)
        client.start_client(timeout=5)
        self.assertEqual(client.get_remote_server_key(), self.host_key)
        return client

    def test_authentication_fails_and_banner_arrives(self):
        client = self.transport()
        with self.assertRaises(paramiko.AuthenticationException):
            client.auth_none("fixture-username")
        self.assertEqual(client.get_banner(), self.banner.read_bytes())
        with self.assertRaises(paramiko.AuthenticationException):
            client.auth_password("fixture-username", "secret-password-fixture")
        with self.assertRaises(paramiko.AuthenticationException):
            client.auth_publickey("fixture-username", paramiko.RSAKey.generate(2048))
        self.assertFalse(client.is_authenticated())
        with self.assertRaises(paramiko.SSHException):
            client.open_session(timeout=1)

    def test_silent_client_deadline_and_per_ip_limit(self):
        clients = []
        for _ in range(2):
            connection = socket.create_connection(("127.0.0.1", self.port), timeout=5)
            clients.append(connection)
            self.addCleanup(connection.close)
            self.assertTrue(connection.recv(256).startswith(b"SSH-2.0-"))
        with socket.create_connection(("127.0.0.1", self.port), timeout=5) as extra:
            self.assertEqual(extra.recv(256), b"")
        clients[0].settimeout(4)
        started = time.monotonic()
        self.assertEqual(clients[0].recv(256), b"")
        self.assertLess(time.monotonic() - started, 4)

    def test_host_key_is_private_and_persistent(self):
        self.assertEqual(self.key.stat().st_mode & 0o777, 0o600)
        before = self.key.stat().st_mtime_ns
        self.assertEqual(prank.load_host_key(self.key), self.host_key)
        self.assertEqual(self.key.stat().st_mtime_ns, before)

    def test_insecure_host_key_is_rejected(self):
        path = self.directory / "unsafe_key"
        path.write_text("not a private key")
        path.chmod(0o644)
        with self.assertRaises(ValueError):
            prank.load_host_key(path)


if __name__ == "__main__":
    unittest.main()
