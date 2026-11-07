#!/usr/bin/env python3
"""Run the Dockerfile's real key-import shell instruction against local faults.

Run: python3 postgres/test_key_download.py (requires curl and gpg).
Only the download URL and output keyring are redirected into disposable fixtures.
"""
import http.server
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import unittest


class KeyDownloadTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = tempfile.TemporaryDirectory(prefix="statbus-575-key-")
        cls.home = Path(cls.fixture.name)
        cls.home.chmod(0o700)
        subprocess.run([
            "gpg", "--homedir", str(cls.home), "--batch", "--passphrase", "",
            "--quick-generate-key", "STATBUS download test <test@example.invalid>",
            "rsa2048", "sign", "0",
        ], check=True, capture_output=True)
        cls.key = subprocess.check_output([
            "gpg", "--homedir", str(cls.home), "--armor", "--export",
        ])
        cls.binary = subprocess.check_output(["gpg", "--dearmor"], input=cls.key)
        cls.fingerprint = subprocess.check_output([
            "gpg", "--homedir", str(cls.home), "--with-colons", "--list-keys",
        ]).decode().split("fpr:::::::::")[1].split(":")[0]
        # Docker continuation processing, not a duplicate implementation of curl.
        instructions = Path(__file__).with_name("Dockerfile").read_text().replace("\\\n", " ").splitlines()
        cls.command = next(line[4:] for line in instructions
                           if line.startswith("RUN ") and "gpg --dearmor" in line)

    @classmethod
    def tearDownClass(cls):
        subprocess.run(["gpgconf", "--homedir", str(cls.home), "--kill", "gpg-agent"], check=True)
        cls.fixture.cleanup()

    def run_import(self, url, directory):
        output = Path(directory) / "keyring.gpg"
        command = self.command.replace(
            "https://www.postgresql.org/media/keys/ACCC4CF8.asc", url
        ).replace("/usr/share/keyrings/postgresql-archive-keyring.gpg", str(output))
        env = dict(os.environ, PGDG_KEY_URL=url, GNUPGHOME=str(self.home), TMPDIR=directory)
        return subprocess.run(["/bin/sh", "-c", command], env=env,
                              capture_output=True, timeout=140), output

    def serve(self, mode):
        test = self
        self.requests = 0

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                test.requests += 1
                if mode == "transient" and test.requests == 1:
                    self.send_response(200)
                    self.send_header("Content-Length", str(len(test.key)))
                    self.end_headers()
                    self.wfile.write(test.key[:len(test.key) // 2])
                    self.wfile.flush()
                    self.close_connection = True
                elif mode == "http" or (mode == "transient" and test.requests == 2):
                    self.send_response(503)
                    self.end_headers()
                    self.wfile.write(b"temporarily unavailable")
                else:
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(test.key if mode == "transient" else b"invalid key")

            def log_message(self, *_):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return f"http://127.0.0.1:{server.server_port}/ACCC4CF8.asc"

    def test_transient_failure_imports_complete_valid_key(self):
        url = self.serve("transient")
        with tempfile.TemporaryDirectory() as directory:
            result, output = self.run_import(url, directory)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual(self.requests, 3)
            self.assertEqual(output.read_bytes(), self.binary)
            imported = subprocess.check_output([
                "gpg", "--homedir", str(self.home), "--show-keys", "--with-colons", str(output),
            ]).decode()
            self.assertIn(f"fpr:::::::::{self.fingerprint}:", imported)
            self.assertEqual(sorted(p.name for p in Path(directory).iterdir()), ["keyring.gpg"])

    def test_unreachable_url_fails_bounded_with_url(self):
        with socket.socket() as reserved:
            reserved.bind(("127.0.0.1", 0))
            url = f"http://127.0.0.1:{reserved.getsockname()[1]}/unreachable.asc"
            with tempfile.TemporaryDirectory() as directory:
                start = time.monotonic()
                result, _ = self.run_import(url, directory)
                self.assertNotEqual(result.returncode, 0)
                self.assertLess(time.monotonic() - start, 130)
                self.assertIn(url, result.stderr.decode())
                self.assertEqual(list(Path(directory).iterdir()), [])

    def test_http_error_fails_bounded_with_url(self):
        url = self.serve("http")
        with tempfile.TemporaryDirectory() as directory:
            result, _ = self.run_import(url, directory)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.requests, 4)
            self.assertIn(url, result.stderr.decode())
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_invalid_key_is_rejected(self):
        url = self.serve("invalid")
        with tempfile.TemporaryDirectory() as directory:
            result, _ = self.run_import(url, directory)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.requests, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
